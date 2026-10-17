//
//  ScaleSyncApp.swift
//  ScaleSync
//

import SwiftUI
import SwiftData

@main
struct ScaleSyncApp: App {

    let container: ModelContainer
    @StateObject private var health: HealthSync
    @StateObject private var scaleManager: ScaleManager
    @AppStorage("showAdvancedSettings") private var showAdvancedSettings = false
    @State private var tab = 0

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: ScaleMeasurement.self)
        } catch {
            // The on-disk store doesn't match the current model (schema
            // changed between builds). Local data is recoverable — the scale
            // re-sends stored measurements on every connection and Health
            // keeps what was already pushed — so wipe the store and retry
            // rather than crash with "invalid reuse after initialization
            // failure" on every launch.
            let store = URL.applicationSupportDirectory.appendingPathComponent("default.store")
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(atPath: store.path + suffix)
            }
            container = try! ModelContainer(for: ScaleMeasurement.self)
        }
        self.container = container
        let health = HealthSync()
        _health = StateObject(wrappedValue: health)
        _scaleManager = StateObject(wrappedValue: ScaleManager(modelContainer: container, health: health))
        ScaleNotifications.configure()
        #if DEBUG
        DemoData.applyLaunchArguments(container: container)
        _tab = State(initialValue: DemoData.initialTab)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                Tab("Now", systemImage: "shoeprints.fill", value: 0) { NowView() }
                Tab("Trends", systemImage: "chart.line.uptrend.xyaxis", value: 1) { TrendsView() }
                Tab("Household", systemImage: "house", value: 2) { HouseholdView() }
            }
            .tint(.crayon)
            .fontDesign(.rounded)
            .foregroundStyle(.ink)
            .environmentObject(health)
            .environmentObject(scaleManager)
            .task {
                #if DEBUG
                if DemoData.isActive { return }
                #endif
                ScaleNotifications.requestAuthorization()
            }
            // Shaking shows or hides the Advanced section in Household.
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.deviceDidShake)) { _ in
                showAdvancedSettings.toggle()
            }
            .sensoryFeedback(.selection, trigger: showAdvancedSettings)
        }
        .modelContainer(container)
    }
}
