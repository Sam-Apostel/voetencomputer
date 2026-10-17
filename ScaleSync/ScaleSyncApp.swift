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
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                DashboardView()
                    .tabItem { Label("Now", systemImage: "scalemass") }
                TrendsView()
                    .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
            .environmentObject(health)
            .environmentObject(scaleManager)
            .task { ScaleNotifications.requestAuthorization() }
            // Shaking shows or hides the Advanced section in Settings.
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.deviceDidShake)) { _ in
                showAdvancedSettings.toggle()
            }
            .sensoryFeedback(.selection, trigger: showAdvancedSettings)
        }
        .modelContainer(container)
    }
}
