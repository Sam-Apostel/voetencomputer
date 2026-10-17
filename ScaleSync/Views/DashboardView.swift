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
    @AppStorage(RecognitionHelp.timestampKey) private var recognitionHelpAt = 0.0
    @AppStorage(RecognitionHelp.slotKey) private var recognitionHelpSlot = 0

    @Query(sort: \ScaleMeasurement.date, order: .reverse)
    private var measurements: [ScaleMeasurement]

    private func isMine(_ m: ScaleMeasurement) -> Bool {
        myUserSlot == 0 || m.userId == myUserSlot
    }

    private var latest: ScaleMeasurement? {
        measurements.first(where: isMine)
    }

    private var previous: ScaleMeasurement? {
        let mine = measurements.filter(isMine)
        return mine.count > 1 ? mine[1] : nil
    }

    /// Body composition only exists when the scale recognised the user, so it
    /// can lag behind the latest weight. Show the most recent one there is.
    private var latestComposition: ScaleMeasurement? {
        measurements.first { isMine($0) && $0.fatPercent != nil }
    }

    /// The newest weigh-in from the last week that neither the scale nor the
    /// weight matching could assign to anyone.
    private var unassigned: ScaleMeasurement? {
        guard myUserSlot > 0 else { return nil }
        let cutoff = Date.now.addingTimeInterval(-7 * 24 * 3600)
        return measurements.first {
            $0.userId == 0 && $0.source == "scale" && $0.weightKg > 0 && $0.date > cutoff
        }
    }

    /// Profiles worth offering when assigning a weigh-in: named ones, ones
    /// with history, and always this phone's own profile (listed first).
    private var assignableSlots: [Int] {
        let named = Set(UserProfiles.decode(userNamesJSON).keys)
        let withHistory = Set(measurements.lazy.filter { $0.userId > 0 }.map(\.userId))
        return named.union(withHistory).union([myUserSlot])
            .filter { (1...8).contains($0) }
            .sorted { ($0 == myUserSlot ? 0 : $0) < ($1 == myUserSlot ? 0 : $1) }
    }

    private var showRecognitionHelp: Binding<Bool> {
        Binding(
            get: {
                recognitionHelpAt > 0
                    && Date.now.timeIntervalSince1970 - recognitionHelpAt < RecognitionHelp.window
            },
            set: { if !$0 { recognitionHelpAt = 0 } }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let m = unassigned {
                        unassignedCard(m)
                    }
                    if let m = latest {
                        weightCard(m)
                        if let comp = latestComposition {
                            compositionSection(comp, olderThan: m)
                        }
                        if let bmi = m.bmi(heightCm: health.heightCm) {
                            BMIGauge(bmi: bmi)
                        }
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
            .sheet(isPresented: showRecognitionHelp) {
                RecognitionHelpSheet(
                    slot: recognitionHelpSlot,
                    name: recognitionHelpSlot == myUserSlot
                        ? nil
                        : UserProfiles.displayName(slot: recognitionHelpSlot, json: userNamesJSON))
            }
        }
    }

    // MARK: - Unrecognised weigh-ins

    private func unassignedCard(_ m: ScaleMeasurement) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Who weighed in?", systemImage: "person.crop.circle.badge.questionmark")
                .font(.headline)
            Text("The scale didn't recognise who weighed \(Units.weightString(m.weightKg)) on \(m.date.formatted(date: .abbreviated, time: .shortened)).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 8) {
                ForEach(assignableSlots, id: \.self) { slot in
                    Button(UserProfiles.displayName(slot: slot, json: userNamesJSON)) {
                        assign(m, to: slot)
                    }
                    .buttonStyle(.bordered)
                }
            }
            Button("Not one of us", role: .destructive) {
                context.delete(m)
                try? context.save()
            }
            .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    /// Move a weigh-in to a profile. The key encodes the profile, so it changes
    /// too; if that profile already has this weigh-in, the duplicate goes.
    private func assign(_ m: ScaleMeasurement, to slot: Int) {
        let newKey = ScaleMeasurement.makeKey(date: m.date, userId: slot)
        let existing = try? context.fetch(FetchDescriptor<ScaleMeasurement>(
            predicate: #Predicate { $0.key == newKey })).first
        if existing != nil {
            context.delete(m)
        } else {
            m.userId = slot
            m.key = newKey
            m.healthSynced = false
        }
        try? context.save()
        health.pushUnsynced(container: context.container)
    }

    private var statusColor: Color {
        switch scaleManager.status {
        case .bluetoothOff: return .red
        case .syncing, .connecting, .scanning: return .orange
        case .done: return .green
        case .idle: return .gray
        }
    }

    // MARK: - Cards

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

    @ViewBuilder
    private func compositionSection(_ comp: ScaleMeasurement, olderThan latest: ScaleMeasurement) -> some View {
        if comp.key != latest.key {
            Text("Body composition from \(comp.date.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        compositionDonut(comp)
        metricsGrid(comp)
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
                BodyCompositionDonut.Segment(label: "Fat", icon: "circle.hexagongrid.fill",
                                             fraction: fat / 100, color: MetricColor.fat),
                BodyCompositionDonut.Segment(label: "Muscle", icon: "dumbbell.fill",
                                             fraction: muscle / 100, color: MetricColor.muscle),
                BodyCompositionDonut.Segment(label: "Bone", icon: "figure.stand",
                                             fraction: bonePercent / 100, color: MetricColor.bone),
                BodyCompositionDonut.Segment(label: "Other", icon: "ellipsis.circle.fill",
                                             fraction: other / 100, color: Color(.systemGray3)),
            ].filter { $0.fraction > 0 }

            BodyCompositionDonut(segments: segments)
                .frame(height: 280)
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

/// Steps to make the scale recognise someone again, shown right after a
/// weigh-in it couldn't assign.
struct RecognitionHelpSheet: View {
    let slot: Int
    /// nil when it's this phone's own profile ("you").
    let name: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let steps = [
            "Tap the middle of the scale with your foot until it shows 0.00.",
            "Press SET, choose P\(slot) with ▲ ▼, then press SET.",
            "Press SET three more times to confirm gender, height and age. Correct the age if it has changed.",
            "Step on barefoot and stand still.",
        ]
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(name.map { "The scale only measured \($0)'s weight. That's saved, but body composition needs the scale to recognise who's standing on it." }
                         ?? "The scale only measured your weight. That's saved, but body composition needs the scale to recognise you.")
                        .font(.body)
                    Text("To fix it:")
                        .font(.headline)
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.subheadline.weight(.bold))
                                .monospacedDigit()
                                .frame(width: 24, height: 24)
                                .background(Color.orange.opacity(0.18), in: Circle())
                            Text(step)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(name.map { "\($0) wasn't recognised" } ?? "You weren't recognised")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
