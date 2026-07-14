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

    /// Writes one meal's nutrition only after the caller has explicitly
    /// requested HealthKit authorization. `externalID` is stable for future
    /// duplicate/update/delete handling in SF-1503.
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
