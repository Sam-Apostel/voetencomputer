//
//  HealthSync.swift
//  ScaleSync
//
//  Writes measurements into Apple Health and reads history back for Trends.
//  Uses HKMetadataKeySyncIdentifier so re-writing the same measurement replaces
//  the sample instead of duplicating it.
//
//  Mapped to HealthKit: weight, body fat %, lean body mass, BMI (if height set).
//  Water %, muscle % and bone mass have no HealthKit types — those live in the
//  app's own history and charts.
//

import Foundation
import Combine
import HealthKit
import SwiftData

final class HealthSync: ObservableObject {

    /// Whether the app may write weight to Health. Only write access can be
    /// checked: HealthKit deliberately hides whether reading was allowed.
    @Published private(set) var authorized = false

    enum PushResult {
        case saved(Int)
        case nothingToDo
        case failed(String)
        case unavailable
    }

    private let store = HKHealthStore()

    private var types: (mass: HKQuantityType, fat: HKQuantityType, lean: HKQuantityType, bmi: HKQuantityType) {
        (HKQuantityType(.bodyMass),
         HKQuantityType(.bodyFatPercentage),
         HKQuantityType(.leanBodyMass),
         HKQuantityType(.bodyMassIndex))
    }

    var heightCm: Double {
        UserDefaults.standard.double(forKey: "heightCm")
    }

    init() {
        refreshAuthorizationStatus()
    }

    func refreshAuthorizationStatus() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        authorized = store.authorizationStatus(for: types.mass) == .sharingAuthorized
    }

    /// Asks for write and read access. iOS only shows the sheet for types not
    /// decided yet, so this is cheap to call whenever access matters.
    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let t = types
        let share: Set<HKSampleType> = [t.mass, t.fat, t.lean, t.bmi]
        let read: Set<HKObjectType> = [t.mass, t.fat, t.lean, t.bmi]
        try? await store.requestAuthorization(toShare: share, read: read)
        refreshAuthorizationStatus()
    }

    /// Push every measurement not yet written to Health. Must be called from
    /// the main queue (all current call sites are).
    func pushUnsynced(container: ModelContainer, completion: (@MainActor (PushResult) -> Void)? = nil) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion?(.unavailable)
            return
        }
        // ModelContext is not Sendable, so all context work stays inside the
        // closure; only the (Sendable) keys are captured by the completion.
        MainActor.assumeIsolated {
            let context = container.mainContext
            // Only the user's own profile goes to Apple Health. Slot 0 ("All
            // users") means no profile is selected — then everything syncs,
            // matching the pre-profile behavior.
            let slot = UserDefaults.standard.integer(forKey: "myUserSlot")
            let predicate: Predicate<ScaleMeasurement> = slot > 0
                ? #Predicate { $0.healthSynced == false && $0.weightKg > 0 && $0.userId == slot }
                : #Predicate { $0.healthSynced == false && $0.weightKg > 0 }
            guard let pending = try? context.fetch(FetchDescriptor(predicate: predicate)), !pending.isEmpty else {
                completion?(.nothingToDo)
                return
            }

            // A version that grows with every write, so writing a measurement
            // again replaces the sample in Health. With a fixed version Health
            // keeps the old sample — corrected values (e.g. BMI after a height
            // change) would never arrive.
            let version = Int(Date().timeIntervalSince1970)
            var samples: [HKQuantitySample] = []
            var syncedKeys: [String] = []
            for m in pending {
                samples.append(contentsOf: makeSamples(for: m, version: version))
                syncedKeys.append(m.key)
            }

            store.save(samples) { ok, error in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard ok else {
                            completion?(.failed(error?.localizedDescription ?? "unknown error"))
                            return
                        }
                        let ctx = container.mainContext
                        for key in syncedKeys {
                            let p = #Predicate<ScaleMeasurement> { $0.key == key }
                            if let obj = (try? ctx.fetch(FetchDescriptor(predicate: p)))?.first {
                                obj.healthSynced = true
                            }
                        }
                        try? ctx.save()
                        completion?(.saved(syncedKeys.count))
                    }
                }
            }
        }
    }

    /// Delete samples this app wrote for the given measurement keys. Used to
    /// undo data that should never have reached Health (e.g. debug samples).
    /// Works with share-only authorization: HealthKit lets an app delete the
    /// samples it saved itself.
    func removeSamples(keys: [String]) {
        guard HKHealthStore.isHealthDataAvailable(), !keys.isEmpty else { return }
        let t = types
        let byType: [(HKQuantityType, String)] = [
            (t.mass, "mass"), (t.fat, "fat"), (t.lean, "lean"), (t.bmi, "bmi"),
        ]
        for (type, suffix) in byType {
            let identifiers = keys.map { "scalesync-\($0)-\(suffix)" }
            let predicate = HKQuery.predicateForObjects(
                withMetadataKey: HKMetadataKeySyncIdentifier,
                allowedValues: identifiers)
            store.deleteObjects(of: type, predicate: predicate) { _, _, error in
                if let error {
                    print("HealthKit delete failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Write every measurement again, replacing what Health has.
    func resyncAll(container: ModelContainer, completion: (@MainActor (PushResult) -> Void)? = nil) {
        MainActor.assumeIsolated {
            let context = container.mainContext
            if let all = try? context.fetch(FetchDescriptor<ScaleMeasurement>()) {
                for m in all { m.healthSynced = false }
                try? context.save()
            }
        }
        pushUnsynced(container: container, completion: completion)
    }

    /// One quantity's history from Apple Health — every source, not only this
    /// app — oldest first. Empty when reading wasn't allowed.
    func history(of identifier: HKQuantityTypeIdentifier, unit: HKUnit,
                 since start: Date?) async -> [(date: Date, value: Double)] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let predicate = start.map { HKQuery.predicateForSamples(withStart: $0, end: nil) }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(identifier), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)])
        let samples = (try? await descriptor.result(for: store)) ?? []
        return samples.map { ($0.startDate, $0.quantity.doubleValue(for: unit)) }
    }

    private func makeSamples(for m: ScaleMeasurement, version: Int) -> [HKQuantitySample] {
        let t = types
        var result: [HKQuantitySample] = []

        func meta(_ suffix: String) -> [String: Any] {
            [HKMetadataKeySyncIdentifier: "scalesync-\(m.key)-\(suffix)",
             HKMetadataKeySyncVersion: version]
        }

        let kg = HKUnit.gramUnit(with: .kilo)
        result.append(HKQuantitySample(
            type: t.mass,
            quantity: HKQuantity(unit: kg, doubleValue: m.weightKg),
            start: m.date, end: m.date, metadata: meta("mass")))

        if let fat = m.fatPercent {
            result.append(HKQuantitySample(
                type: t.fat,
                quantity: HKQuantity(unit: .percent(), doubleValue: fat / 100.0),
                start: m.date, end: m.date, metadata: meta("fat")))
        }
        if let lean = m.leanBodyMassKg {
            result.append(HKQuantitySample(
                type: t.lean,
                quantity: HKQuantity(unit: kg, doubleValue: lean),
                start: m.date, end: m.date, metadata: meta("lean")))
        }
        if let bmi = m.bmi(heightCm: heightCm) {
            result.append(HKQuantitySample(
                type: t.bmi,
                quantity: HKQuantity(unit: .count(), doubleValue: bmi),
                start: m.date, end: m.date, metadata: meta("bmi")))
        }
        return result
    }
}
