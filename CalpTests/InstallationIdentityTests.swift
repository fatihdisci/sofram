//
//  InstallationIdentityTests.swift
//  CalpTests — load-or-create + persistence coverage for the anonymous
//  installation UUID, exercised against an in-memory Keychain double.
//

import XCTest
@testable import Calp

final class InstallationIdentityTests: XCTestCase {

    func testMintsAndPersistsOnFirstAccess() {
        let store = InMemoryKeychainStore()
        let identity = InstallationIdentity(store: store)

        let id = identity.installationID

        // The freshly minted UUID was written to the store under the documented key.
        XCTAssertEqual(store.writeCount, 1)
        let stored = store.data(forKey: InstallationIdentity.keychainKey)
            .flatMap { String(data: $0, encoding: .utf8) }
        XCTAssertEqual(stored, id.uuidString)
    }

    func testRepeatedReadsReturnSameValueAndDoNotRewrite() {
        let store = InMemoryKeychainStore()
        let identity = InstallationIdentity(store: store)

        let first = identity.installationID
        let second = identity.installationID

        XCTAssertEqual(first, second)
        // "Generated exactly once" — no second write on the cache hit.
        XCTAssertEqual(store.writeCount, 1)
    }

    func testSecondInstanceReadsBackPersistedValue() {
        let store = InMemoryKeychainStore()

        // First install lifetime mints the UUID.
        let original = InstallationIdentity(store: store).installationID

        // A fresh instance over the same Keychain must read it back, not re-mint.
        let reloaded = InstallationIdentity(store: store)
        XCTAssertEqual(reloaded.installationID, original)
        XCTAssertEqual(store.writeCount, 1, "reload must not write a new UUID")
    }

    func testCorruptStoredValueIsReplacedWithFreshUUID() {
        let store = InMemoryKeychainStore()
        store.set(Data("not-a-uuid".utf8), forKey: InstallationIdentity.keychainKey)
        store.resetWriteCount()

        let identity = InstallationIdentity(store: store)
        let id = identity.installationID

        // Garbage is overwritten with a valid, round-trippable UUID.
        XCTAssertEqual(store.writeCount, 1)
        let stored = store.data(forKey: InstallationIdentity.keychainKey)
            .flatMap { String(data: $0, encoding: .utf8) }
        XCTAssertEqual(stored, id.uuidString)
        XCTAssertNotNil(UUID(uuidString: stored ?? ""))
    }

    func testSeparateInstallsGetDistinctIDs() {
        let a = InstallationIdentity(store: InMemoryKeychainStore()).installationID
        let b = InstallationIdentity(store: InMemoryKeychainStore()).installationID
        XCTAssertNotEqual(a, b, "each empty install should mint its own random UUID")
    }

    func testHeaderValueMatchesUUIDString() {
        let identity = InstallationIdentity(store: InMemoryKeychainStore())
        XCTAssertEqual(identity.headerValue, identity.installationID.uuidString)
    }
}

/// In-memory `InstallationKeychainStore` double that also counts writes so tests
/// can assert the UUID is minted exactly once.
private final class InMemoryKeychainStore: InstallationKeychainStore {
    private var storage: [String: Data] = [:]
    private(set) var writeCount = 0

    func data(forKey key: String) -> Data? { storage[key] }

    @discardableResult
    func set(_ data: Data, forKey key: String) -> Bool {
        storage[key] = data
        writeCount += 1
        return true
    }

    func resetWriteCount() { writeCount = 0 }
}
