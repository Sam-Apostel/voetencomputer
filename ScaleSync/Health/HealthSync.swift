//
//  HealthSync.swift
//  ScaleSync
//
//  Writes measurements into Apple Health. Uses HKMetadataKeySyncIdentifier so
//  re-writing the same measurement replaces the sample instead of duplicating.
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

    @Published var authorized = false

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

    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let t = types
        let share: Set<HKSampleType> = [t.mass, t.fat, t.lean, t.bmi]
        store.requestAuthorization(toShare: share, read: []) { [weak self] ok, _ in
            DispatchQueue.main.async { self?.authorized = ok }
        }
    }

    /// Push every measurement not yet written to Health. Must be called from
    /// the main queue (all current call sites are).
    func pushUnsynced(container: ModelContainer) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
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
            guard let pending = try? context.fetch(FetchDescriptor(predicate: predicate)), !pending.isEmpty else { return }

            var samples: [HKQuantitySample] = []
            var syncedKeys: [String] = []

            for m in pending {
                samples.append(contentsOf: makeSamples(for: m))
                syncedKeys.append(m.key)
            }
            guard !samples.isEmpty else { return }

            store.save(samples) { ok, error in
                guard ok else {
                    print("HealthKit save failed: \(error?.localizedDescription ?? "?")")
                    return
                }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        let ctx = container.mainContext
                        for key in syncedKeys {
                            let p = #Predicate<ScaleMeasurement> { $0.key == key }
                            if let obj = (try? ctx.fetch(FetchDescriptor(predicate: p)))?.first {
                                obj.healthSynced = true
                            }
                        }
                        try? ctx.save()
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

    /// Force a re-push of everything (used after changing settings).
    func resyncAll(container: ModelContainer) {
        MainActor.assumeIsolated {
            let context = container.mainContext
            if let all = try? context.fetch(FetchDescriptor<ScaleMeasurement>()) {
                for m in all { m.healthSynced = false }
                try? context.save()
            }
        }
        pushUnsynced(container: container)
    }

    private func makeSamples(for m: ScaleMeasurement) -> [HKQuantitySample] {
        let t = types
        var result: [HKQuantitySample] = []

        func meta(_ suffix: String) -> [String: Any] {
            [HKMetadataKeySyncIdentifier: "scalesync-\(m.key)-\(suffix)",
             HKMetadataKeySyncVersion: 1]
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
