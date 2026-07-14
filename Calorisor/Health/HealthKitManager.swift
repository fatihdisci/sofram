import Foundation
import HealthKit

struct HealthKitSnapshot: Equatable, Sendable {
    var weightKg: Double?
    var heightCm: Double?
    var activeEnergyKcal: Double
    var steps: Double

    static let empty = HealthKitSnapshot(
        weightKg: nil,
        heightCm: nil,
        activeEnergyKcal: 0,
        steps: 0
    )
}

struct HealthKitWeightPoint: Equatable, Identifiable, Sendable {
    let date: Date
    let kilograms: Double

    var id: Date { date }
}

/// The only boundary between the app and HealthKit. Health data stays on-device
/// and is never part of an AI proxy request, telemetry event, or widget payload.
final class HealthKitManager {
    static let shared = HealthKitManager()

    private let store: HKHealthStore

    init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        Set([
            HKObjectType.quantityType(forIdentifier: .bodyMass),
            HKObjectType.quantityType(forIdentifier: .height),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
            HKObjectType.quantityType(forIdentifier: .stepCount),
        ].compactMap { $0 })
    }

    private var writeTypes: Set<HKSampleType> {
        Set([
            HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed),
            HKObjectType.quantityType(forIdentifier: .dietaryProtein),
            HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates),
            HKObjectType.quantityType(forIdentifier: .dietaryFatTotal),
        ].compactMap { $0 })
    }

    /// Requests only the types used by this feature. A denial is a normal state;
    /// callers can keep the rest of the app fully functional.
    func requestAuthorization() async -> Bool {
        guard Self.isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            return true
        } catch {
            return false
        }
    }

    func readToday() async -> HealthKitSnapshot {
        guard Self.isAvailable else { return .empty }
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)

        async let weight = latestQuantity(.bodyMass, unit: .gramUnit(with: .kilo), before: now)
        async let height = latestQuantity(.height, unit: .meterUnit(with: .centi), before: now)
        async let energy = summedQuantity(.activeEnergyBurned, unit: .kilocalorie(), from: start, to: now)
        async let steps = summedQuantity(.stepCount, unit: .count(), from: start, to: now)

        return HealthKitSnapshot(
            weightKg: try? await weight,
            heightCm: try? await height,
            activeEnergyKcal: (try? await energy) ?? 0,
            steps: (try? await steps) ?? 0
        )
    }

    func readActiveEnergyTotal(days: Int = 7, now: Date = .now) async -> Double? {
        guard Self.isAvailable, days > 0 else { return nil }
        let calendar = Calendar.current
        let end = now
        let today = calendar.startOfDay(for: end)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        return try? await summedQuantity(
            .activeEnergyBurned,
            unit: .kilocalorie(),
            from: start,
            to: end
        )
    }

    /// Returns body-mass samples for the requested trailing window. HealthKit
    /// can contain several readings per day; the trend view reduces these to
    /// one reading per day before rendering.
    func readWeightHistory(days: Int = 30, now: Date = .now) async -> [HealthKitWeightPoint] {
        guard Self.isAvailable, days > 0 else { return [] }

        let calendar = Calendar.current
        let end = now
        let today = calendar.startOfDay(for: end)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        guard let type = HKObjectType.quantityType(forIdentifier: .bodyMass) else { return [] }

        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: .strictStartDate
        )

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)]
            ) { _, samples, _ in
                let points = (samples as? [HKQuantitySample] ?? []).compactMap { sample -> HealthKitWeightPoint? in
                    let value = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                    guard value.isFinite, value > 0 else { return nil }
                    return HealthKitWeightPoint(date: sample.endDate, kilograms: value)
                }
                continuation.resume(returning: points)
            }
            self.store.execute(query)
        }
    }

    /// Replaces the HealthKit samples for one logged meal. All nutrient
    /// samples share the meal's stable ScanEntry UUID, so retrying an upload
    /// or editing a meal cannot create a second copy.
    func syncMealNutrition(
        externalID: UUID,
        date: Date,
        calories: Double,
        protein: Double,
        carbs: Double,
        fat: Double
    ) async -> Bool {
        guard [calories, protein, carbs, fat].allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            return false
        }
        guard await deleteMealNutrition(externalID: externalID) else { return false }
        return await writeMealNutrition(
            externalID: externalID,
            date: date,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat
        )
    }

    /// Deletes every nutrient sample associated with one meal UUID. Deleting
    /// a meal remains safe when HealthKit is unavailable or permission is
    /// missing: the local SwiftData meal is still deleted by its caller.
    func deleteMealNutrition(externalID: UUID) async -> Bool {
        guard Self.isAvailable else { return false }
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            allowedValues: [externalID.uuidString]
        )

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for type in writeTypes {
                    group.addTask {
                        try await self.store.deleteObjects(of: type, predicate: predicate)
                    }
                }
                try await group.waitForAll()
            }
            return true
        } catch {
            return false
        }
    }

    /// Writes one meal's nutrition after the caller has explicitly requested
    /// HealthKit authorization. Callers should normally use
    /// syncMealNutrition(externalID:date:calories:protein:carbs:fat:) so
    /// retries and edits remain duplicate-free.
    func writeMealNutrition(
        externalID: UUID,
        date: Date,
        calories: Double,
        protein: Double,
        carbs: Double,
        fat: Double
    ) async -> Bool {
        guard Self.isAvailable else { return false }
        let values: [(HKQuantityTypeIdentifier, HKUnit, Double)] = [
            (.dietaryEnergyConsumed, .kilocalorie(), calories),
            (.dietaryProtein, .gram(), protein),
            (.dietaryCarbohydrates, .gram(), carbs),
            (.dietaryFatTotal, .gram(), fat),
        ]
        let samples = values.compactMap { identifier, unit, value -> HKQuantitySample? in
            guard value.isFinite, value >= 0,
                  let type = HKObjectType.quantityType(forIdentifier: identifier)
            else { return nil }
            return HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: unit, doubleValue: value),
                start: date,
                end: date,
                metadata: [HKMetadataKeyExternalUUID: externalID.uuidString]
            )
        }
        guard !samples.isEmpty else { return false }
        do {
            try await store.save(samples)
            return true
        } catch {
            return false
        }
    }

    private func latestQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        before date: Date
    ) async throws -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(
            withStart: nil,
            end: date,
            options: .strictEndDate
        )
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let sample = samples?.first as? HKQuantitySample
                continuation.resume(returning: sample?.quantity.doubleValue(for: unit))
            }
            self.store.execute(query)
        }
    }

    private func summedQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from start: Date,
        to end: Date
    ) async throws -> Double {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return 0 }
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: .strictStartDate
        )
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            self.store.execute(query)
        }
    }
}
