//
//  InstallationIdentity.swift
//  Calp — anonymous, device-scoped installation identity.
//
//  The app has no accounts (see PROJECT_CONTEXT.md). To apply per-device usage
//  limits and anonymous analytics server-side, we mint a random UUID on first
//  use and keep it in the Keychain — NOT UserDefaults, so it survives an app
//  update and is never included in an unencrypted backup.
//
//  Guarantees / non-guarantees (scope doc §8.1):
//   • Generated exactly once, then read back stably for the life of the install.
//   • Kept in the Keychain under `com.fatih.calp.installation-id`.
//   • Accessible after first unlock (needed for background network requests),
//     device-only (never synced to iCloud Keychain or another device).
//   • Survival across delete+reinstall is NOT guaranteed — iOS may purge the
//     item, in which case a fresh UUID is minted. That is acceptable: this is an
//     abuse-limiting signal, not an authentication credential.
//
//  The raw UUID leaves the device only in a request header; the proxy hashes it
//  with a server secret before it ever touches a log (see scope doc §8.2 / §9).
//

import Foundation
import Security

// MARK: - Keychain abstraction (testable)

/// The narrow slice of Keychain behaviour `InstallationIdentity` needs. Abstracted
/// behind a protocol so tests can inject an in-memory store and exercise the
/// load-or-create logic without touching the real system Keychain.
protocol InstallationKeychainStore {
    func data(forKey key: String) -> Data?
    @discardableResult
    func set(_ data: Data, forKey key: String) -> Bool
}

/// Real Keychain-backed store using a generic-password item.
struct SystemKeychainStore: InstallationKeychainStore {

    /// Service namespace for the item (paired with `account` = the key).
    private let service: String

    init(service: String = "com.fatih.calp") {
        self.service = service
    }

    private func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    func data(forKey key: String) -> Data? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    func set(_ data: Data, forKey key: String) -> Bool {
        // Available after first unlock so a request firing while the phone is
        // locked-but-booted can still read it; device-only so it never syncs.
        let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        // Update in place if the item already exists, otherwise add it.
        let updateStatus = SecItemUpdate(
            baseQuery(forKey: key) as CFDictionary,
            [
                kSecValueData as String: data,
                kSecAttrAccessible as String: accessibility,
            ] as CFDictionary
        )
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        var addQuery = baseQuery(forKey: key)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = accessibility
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }
}

// MARK: - Installation identity

/// Resolves (and, on first use, mints) the anonymous installation UUID.
///
/// Reference type with a cached value + lock so it is safe to read from the
/// networking layer on any thread/actor without re-hitting the Keychain each
/// time. Not `@MainActor`: request-building may run off the main thread.
final class InstallationIdentity {

    static let shared = InstallationIdentity()

    /// Keychain account key for the stored UUID (scope doc §8.1).
    static let keychainKey = "com.fatih.calp.installation-id"

    private let store: InstallationKeychainStore
    private let lock = NSLock()
    private var cached: UUID?

    init(store: InstallationKeychainStore = SystemKeychainStore()) {
        self.store = store
    }

    /// The stable installation UUID. Reads the Keychain on first access, mints a
    /// new UUID if none is stored (or the stored value is unreadable), then keeps
    /// it cached for the lifetime of this instance.
    var installationID: UUID {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        let resolved = resolveLocked()
        cached = resolved
        return resolved
    }

    /// Its `uuidString` form, ready to drop into the `x-calp-installation-id`
    /// request header (SF-1102).
    var headerValue: String { installationID.uuidString }

    /// Caller must hold `lock`.
    private func resolveLocked() -> UUID {
        if let data = store.data(forKey: Self.keychainKey),
           let string = String(data: data, encoding: .utf8),
           let existing = UUID(uuidString: string) {
            return existing
        }
        let created = UUID()
        store.set(Data(created.uuidString.utf8), forKey: Self.keychainKey)
        return created
    }
}
