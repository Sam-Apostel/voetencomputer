//
//  DemoData.swift
//  ScaleSync
//
//  Debug-only sample household for the simulator and screenshots. Invented
//  values (the repo is public): Sam on P1, Lien on P2, 90 days of readings.
//
//  Launch arguments (Xcode scheme or `simctl launch … -demo`):
//    -demo          insert the sample household if the store is empty
//    -tab N         open on tab N (0 Now, 1 Trends, 2 Household)
//    -who           add an unrecognised 23,8 kg weigh-in from yesterday
//    -body          open Now › Body
//    -footprints    replay the Footprints moment at a tenth of the speed
//

#if DEBUG
import Foundation
import SwiftData

enum DemoData {
    static func insert(into context: ModelContext) {
        let cal = Calendar.current
        let now = Date.now
        for day in 0..<90 where day % 2 == 0 || day < 14 {
            guard let date = cal.date(byAdding: .day, value: -day, to: now)?
                .addingTimeInterval(-Double((day * 37) % 50) * 60 - (day == 0 ? 120 : 0)) else { continue }
            let drift = Double(day)
            context.insert(ScaleMeasurement(
                date: date, userId: 1,
                weightKg: day == 0 ? 78.4 : (day == 2 ? 78.9 : 78.4 + min(drift, 76) * 0.024 + sin(drift * 1.3) * 0.25),
                fatPercent: day == 0 ? 18.4 : 18.4 + drift * 0.009 + sin(drift * 0.7) * 0.3,
                waterPercent: day == 0 ? 57.9 : 57.9 - drift * 0.002 + cos(drift * 0.5) * 0.3,
                musclePercent: day == 0 ? 40.1 : 40.1 - drift * 0.004 + sin(drift * 0.3) * 0.2,
                boneKg: 3.4, kcal: 2637,
                source: "debug", healthSynced: true))
        }
        context.insert(ScaleMeasurement(date: now.addingTimeInterval(-26 * 60), userId: 2, weightKg: 61.7,
                                        fatPercent: 24.1, waterPercent: 54.2, musclePercent: 36.0,
                                        boneKg: 2.6, kcal: 1940, source: "debug", healthSynced: true))
        let d = UserDefaults.standard
        var names = UserProfiles.decode(d.string(forKey: UserProfiles.defaultsKey) ?? "{}")
        if names[1] == nil { names[1] = "Sam" }
        if names[2] == nil { names[2] = "Lien" }
        d.set(UserProfiles.encode(names), forKey: UserProfiles.defaultsKey)
        if d.integer(forKey: "myUserSlot") == 0 { d.set(1, forKey: "myUserSlot") }
        if d.double(forKey: "heightCm") == 0 { d.set(180.0, forKey: "heightCm") }
        try? context.save()
    }

    static func addUnrecognised(into context: ModelContext) {
        let date = Calendar.current.date(byAdding: .hour, value: -15, to: .now) ?? .now
        context.insert(ScaleMeasurement(date: date, userId: 0, weightKg: 23.8, source: "scale"))
        try? context.save()
    }

    @MainActor
    static func applyLaunchArguments(container: ModelContainer) {
        let args = ProcessInfo.processInfo.arguments
        let context = container.mainContext
        if args.contains("-demo"),
           ((try? context.fetchCount(FetchDescriptor<ScaleMeasurement>())) ?? 0) == 0 {
            insert(into: context)
            // Seen, so the demo opens settled rather than replaying Footprints.
            if !args.contains("-footprints"), let latest = try? context.fetch(FetchDescriptor<ScaleMeasurement>(
                predicate: #Predicate { $0.userId == 1 },
                sortBy: [SortDescriptor(\.date, order: .reverse)])).first {
                UserDefaults.standard.set(latest.key, forKey: "celebratedKey")
            }
        }
        if args.contains("-who") { addUnrecognised(into: context) }
    }

    /// Screenshots: no permission prompts over the screens.
    static var isActive: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    static func has(_ flag: String) -> Bool { ProcessInfo.processInfo.arguments.contains(flag) }

    static var initialTab: Int {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-tab"), i + 1 < args.count else { return 0 }
        return Int(args[i + 1]) ?? 0
    }
}
#endif
