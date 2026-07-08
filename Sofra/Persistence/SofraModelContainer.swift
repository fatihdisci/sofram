//
//  SofraModelContainer.swift
//  Sofra — the SwiftData stack, backed by the user's CloudKit PRIVATE database.
//
//  User data (scans, logs, profile, counters) lives in SwiftData and syncs through
//  the user's own iCloud account. The app's server never sees any of it.
//  Private database ONLY — no public/shared CloudKit database.
//

import Foundation
import SwiftData

enum SofraModelContainer {

    /// CloudKit container id. Declared in the entitlement
    /// `com.apple.developer.icloud-container-identifiers`; `.automatic` (below) picks
    /// it up from there in signed builds.
    static let cloudKitContainerID = "iCloud.com.fatih.sofra"

    static let schema = Schema([
        ScanEntry.self,
        LoggedItem.self,
        DailyQuickCounter.self,   // legacy — kept for store compatibility
        QuickAddItem.self,
        QuickAddCount.self,
        UserProfile.self,
    ])

    /// The app-wide container.
    ///
    /// `cloudKitDatabase: .automatic` means: sync via the CloudKit **private** database
    /// of the container declared in the entitlement **when the binary is entitled**
    /// (a signed build with the CloudKit capability), and quietly run local-only
    /// otherwise (unsigned simulator runs, CI, or a user who turned iCloud off for the
    /// app). SwiftData only supports the private database — no public/shared DB is or
    /// can be enabled here, which is exactly the required posture.
    ///
    /// We deliberately do NOT hard-code `.private(cloudKitContainerID)`: that forces
    /// CloudKit setup regardless of entitlement, which makes CloudKit trap during its
    /// asynchronous mirroring setup on an unentitled build — a crash the `do/catch`
    /// around container creation cannot catch.
    static let shared: ModelContainer = {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            #if DEBUG
            print("⚠️ ModelContainer creation failed (\(error)). Retrying local-only.")
            #endif
            let localConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            do {
                return try ModelContainer(for: schema, configurations: [localConfiguration])
            } catch {
                fatalError("Unable to create a SwiftData ModelContainer: \(error)")
            }
        }
    }()
}
