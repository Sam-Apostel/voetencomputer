//
//  DashboardView.swift
//  ScaleSync
//

import SwiftUI
import SwiftData

/// Per-metric accent colors (a nod to the VitaDock palette).
enum MetricColor {
    static let weight = Color.green
    static let fat = Color.orange
    static let water = Color.blue
    static let muscle = Color.mint
    static let bone = Color.teal
    static let lean = Color.indigo
    static let energy = Color.pink
}

struct DashboardView: View {
    @EnvironmentObject var scaleManager: ScaleManager
    @EnvironmentObject var health: HealthSync
    @Environment(\.modelContext) private var context

    @AppStorage("myUserSlot") private var myUserSlot = 0     // 0 = show all users
    @AppStorage(UserProfiles.defaultsKey) private var userNamesJSON = "{}"

    @Query(sort: \ScaleMeasurement.date, order: .reverse)
    private var measurements: [ScaleMeasurement]

    private var latest: ScaleMeasurement? {
        measurements.first { myUserSlot == 0 || $0.userId == myUserSlot }
    }

    private var previous: ScaleMeasurement? {
        let mine = measurements.filter { myUserSlot == 0 || $0.userId == myUserSlot }
        return mine.count > 1 ? mine[1] : nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let m = latest {
                        weightCard(m)
                        compositionDonut(m)
                        if let bmi = m.bmi(heightCm: health.heightCm) {
                            BMIGauge(bmi: bmi)
                        }
                        metricsGrid(m)
                    } else if !measurements.isEmpty {
                        // Readings exist but none match the selected profile —
                        // usually the scale never assigned a P-number, so they
                        // landed in the "unassigned" slot.
                        ContentUnavailableView(
                            "Nothing for this profile",
                            systemImage: "person.crop.circle.badge.questionmark",
                            description: Text("\(measurements.count) measurement\(measurements.count == 1 ? "" : "s") stored, but none under “\(UserProfiles.displayName(slot: myUserSlot, json: userNamesJSON))”. Stay on the scale until it shows your P-number, or set My profile to All users in Settings.")
                        )
                        .padding(.top, 40)
                    } else {
                        ContentUnavailableView(
                            "No measurements yet",
                            systemImage: "scalemass",
                            description: Text("Step on your scale with the app open. It will pair automatically and pull every stored reading.")
                        )
                        .padding(.top, 40)
                    }
                }
                .padding()
            }
            .navigationTitle("Voetencomputer")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        scaleManager.syncNow()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(statusColor)
                    }
                    .accessibilityLabel(scaleManager.status.label)
                }
            }
        }
    }

    private var statusColor: Color {
        switch scaleManager.status {
        case .bluetoothOff: return .red
        case .syncing, .connecting, .scanning: return .orange
        case .done: return .green
        case .idle: return .gray
        }
    }

    private func weightCard(_ m: ScaleMeasurement) -> some View {
        VStack(spacing: 4) {
            Text(Units.weightString(m.weightKg))
                .font(.system(size: 54, weight: .bold, design: .rounded))
                .foregroundStyle(MetricColor.weight.gradient)
            if let prev = previous, prev.weightKg > 0, m.weightKg > 0 {
                let delta = m.weightKg - prev.weightKg
                Text("\(delta >= 0 ? "▲" : "▼") \(Units.weightString(abs(delta))) since last")
                    .font(.footnote)
                    .foregroundStyle(delta >= 0 ? .orange : .green)
            }
            Text(m.date.formatted(date: .abbreviated, time: .shortened))
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                if m.userId > 0 {
                    Label(UserProfiles.displayName(slot: m.userId, json: userNamesJSON),
                          systemImage: "person")
                }
                Label(m.healthSynced ? "In Apple Health" : "Health pending",
                      systemImage: m.healthSynced ? "heart.fill" : "heart")
                    .foregroundStyle(m.healthSynced ? .pink : .secondary)
            }
            .font(.caption)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(MetricColor.weight.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    /// Fat, muscle and bone are disjoint compartments of body mass, so they
    /// work as slices of one donut (the rest is "other": organs, non-muscle
    /// water, etc.). The scale's water % overlaps muscle and is shown as its
    /// own tile instead of a slice.
    @ViewBuilder
    private func compositionDonut(_ m: ScaleMeasurement) -> some View {
        if m.weightKg > 0, let fat = m.fatPercent, let muscle = m.musclePercent {
            let bonePercent = (m.boneKg ?? 0) / m.weightKg * 100
            let other = max(0, 100 - fat - muscle - bonePercent)
            let segments = [
                BodyCompositionDonut.Segment(label: "Fat", icon: "figure.arms.open",
                                             fraction: fat / 100, color: MetricColor.fat),
                BodyCompositionDonut.Segment(label: "Muscle", icon: "figure.strengthtraining.traditional",
                                             fraction: muscle / 100, color: MetricColor.muscle),
                BodyCompositionDonut.Segment(label: "Bone", icon: "figure.stand",
                                             fraction: bonePercent / 100, color: MetricColor.bone),
                BodyCompositionDonut.Segment(label: "Other", icon: "circle.dashed",
                                             fraction: other / 100, color: Color(.systemGray3)),
            ].filter { $0.fraction > 0 }

            BodyCompositionDonut(segments: segments)
                .frame(height: 250)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
    }

    private func metricsGrid(_ m: ScaleMeasurement) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            metricTile("Water", m.waterPercent.map { "\($0.formatted(.number.precision(.fractionLength(1))))%" },
                       "drop", MetricColor.water)
            metricTile("Lean mass", m.leanBodyMassKg.map { Units.weightString($0) },
                       "figure", MetricColor.lean)
            metricTile("Bone", m.boneKg.map { Units.weightString($0) },
                       "figure.stand", MetricColor.bone)
            if let kcal = m.kcal, kcal > 0 {
                metricTile("Daily energy", "\(kcal) kcal", "flame", MetricColor.energy)
            }
        }
    }

    private func metricTile(_ title: String, _ value: String?, _ icon: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(tint)
            Text(value ?? "–")
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}
