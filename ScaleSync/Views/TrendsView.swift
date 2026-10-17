//
//  TrendsView.swift
//  ScaleSync
//
//  Every metric as its own chart. Weight, body fat, lean mass and BMI come
//  from Apple Health — all sources, so history from before this app or from
//  other apps shows up too. Muscle, water and bone have no Health type and
//  come from the app's own measurements.
//

import SwiftUI
import SwiftData
import Charts
import HealthKit
import Combine

struct TrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

private struct MetricSeries: Identifiable {
    let metric: TrendMetric
    let points: [TrendPoint]
    var id: TrendMetric { metric }
}

enum TrendMetric: String, CaseIterable, Identifiable {
    case weight = "Weight"
    case fat = "Body fat"
    case muscle = "Muscle"
    case water = "Water"
    case bone = "Bone"
    case lean = "Lean mass"
    case bmi = "BMI"

    var id: String { rawValue }

    var unit: String {
        switch self {
        case .weight, .bone, .lean: Units.weightUnit
        case .fat, .muscle, .water: "%"
        case .bmi: ""
        }
    }

    /// The Apple Health quantity behind this metric, if there is one.
    var healthQuantity: (identifier: HKQuantityTypeIdentifier, unit: HKUnit)? {
        switch self {
        case .weight: (.bodyMass, .gramUnit(with: .kilo))
        case .fat: (.bodyFatPercentage, .percent())
        case .lean: (.leanBodyMass, .gramUnit(with: .kilo))
        case .bmi: (.bodyMassIndex, .count())
        case .muscle, .water, .bone: nil
        }
    }

    /// Converts a Health value (kilograms, or a 0–1 fraction) to display units.
    func displayValue(fromHealth value: Double) -> Double {
        switch self {
        case .weight, .lean, .bone: Units.kgToDisplay(value)
        case .fat, .muscle, .water: value * 100
        case .bmi: value
        }
    }

    /// Value of a locally stored measurement, in display units.
    func localValue(_ m: ScaleMeasurement, heightCm: Double) -> Double? {
        switch self {
        case .weight: m.weightKg > 0 ? Units.kgToDisplay(m.weightKg) : nil
        case .fat: m.fatPercent
        case .muscle: m.musclePercent
        case .water: m.waterPercent
        case .bone: m.boneKg.map { Units.kgToDisplay($0) }
        case .lean: m.leanBodyMassKg.map { Units.kgToDisplay($0) }
        case .bmi: m.bmi(heightCm: heightCm)
        }
    }

    func format(_ value: Double) -> String {
        let number = value.formatted(.number.precision(.fractionLength(1)))
        switch self {
        case .fat, .muscle, .water: return number + "%"
        case .bmi: return number
        default: return number + " " + unit
        }
    }
}

enum TrendRange: String, CaseIterable, Identifiable {
    case month = "30d"
    case quarter = "90d"
    case year = "1y"
    case all = "All"

    var id: String { rawValue }

    var cutoff: Date? {
        let cal = Calendar.current
        switch self {
        case .month: return cal.date(byAdding: .day, value: -30, to: .now)
        case .quarter: return cal.date(byAdding: .day, value: -90, to: .now)
        case .year: return cal.date(byAdding: .year, value: -1, to: .now)
        case .all: return nil
        }
    }

    var title: String {
        switch self {
        case .month: "30 days"
        case .quarter: "90 days"
        case .year: "1 year"
        case .all: "All"
        }
    }

    var phrase: String {
        switch self {
        case .month: "in 30 days"
        case .quarter: "in 90 days"
        case .year: "in a year"
        case .all: "overall"
        }
    }
}


/// Loads one profile's series for every metric: Apple Health history for the
/// Health types (all sources), the app's own readings for the rest.
@MainActor
final class TrendSource: ObservableObject {
    @Published private(set) var healthPoints: [TrendMetric: [TrendPoint]] = [:]

    func load(range: TrendRange, health: HealthSync) async {
        #if DEBUG
        if DemoData.isActive { return }
        #endif
        await health.requestAuthorization()
        var loaded: [TrendMetric: [TrendPoint]] = [:]
        for metric in TrendMetric.allCases {
            guard let quantity = metric.healthQuantity else { continue }
            let samples = await health.history(of: quantity.identifier, unit: quantity.unit, since: range.cutoff)
            loaded[metric] = samples.map {
                TrendPoint(date: $0.date, value: metric.displayValue(fromHealth: $0.value))
            }
        }
        healthPoints = loaded
    }

    func points(for metric: TrendMetric, mine: [ScaleMeasurement], heightCm: Double) -> [TrendPoint] {
        func local(_ source: [ScaleMeasurement]) -> [TrendPoint] {
            source.compactMap { m in
                metric.localValue(m, heightCm: heightCm).map { TrendPoint(date: m.date, value: $0) }
            }
        }
        guard let fromHealth = healthPoints[metric], !fromHealth.isEmpty else {
            return local(mine)
        }
        // Health already has everything this app wrote; only add what is
        // still waiting to be written.
        return (fromHealth + local(mine.filter { !$0.healthSynced })).sorted { $0.date < $1.date }
    }
}

enum TrendSentence {
    /// "Down 1,9 kg since the end of July." / "Steady since mid-August."
    static func headline(_ metric: TrendMetric, _ points: [TrendPoint]) -> String {
        guard points.count > 1, let first = smoothed(points).first, let last = points.last else {
            return points.isEmpty ? "No readings yet." : "One reading so far."
        }
        var since = Say.pointInMonth(first.date)
        let cal = Calendar.current
        if cal.component(.year, from: first.date) != cal.component(.year, from: last.date) {
            since += " " + first.date.formatted(.dateTime.year())
        }
        let delta = last.value - first.value
        if abs(delta) < metric.steadyBelow { return "Steady since \(since)." }
        return "\(delta < 0 ? "Down" : "Up") \(metric.format(abs(delta))) since \(since)."
    }

    /// "Steady for the last two weeks." / "Down 0,6 kg in the last two weeks."
    static func lately(_ metric: TrendMetric, _ points: [TrendPoint]) -> String? {
        guard let last = points.last else { return nil }
        let start = last.date.addingTimeInterval(-14 * 86400)
        let recent = points.filter { $0.date >= start }
        guard recent.count > 1, points.first!.date < start else { return nil }
        let line = smoothed(points)
        guard let then = line.min(by: { abs($0.date.timeIntervalSince(start)) < abs($1.date.timeIntervalSince(start)) }) else { return nil }
        let delta = last.value - then.value
        if abs(delta) < metric.steadyBelow { return "Steady for the last two weeks." }
        return "\(delta < 0 ? "Down" : "Up") \(metric.format(abs(delta))) in the last two weeks."
    }

    /// "−0,8 in 90 days" / "no change".
    static func rowDelta(_ metric: TrendMetric, _ points: [TrendPoint], _ range: TrendRange) -> String? {
        guard points.count > 1, let first = points.first, let last = points.last else { return nil }
        let delta = last.value - first.value
        if abs(delta) < 0.05 { return "no change" }
        let number = abs(delta).formatted(.number.precision(.fractionLength(1)))
        return "\(delta < 0 ? "−" : "+")\(number) \(range.phrase)"
    }
}

extension TrendMetric {
    /// Below this change the sentence says "steady".
    var steadyBelow: Double {
        switch self {
        case .weight, .lean: 0.3
        case .bmi: 0.1
        default: 0.2
        }
    }
}

struct TrendsView: View {
    @EnvironmentObject var health: HealthSync
    @AppStorage("myUserSlot") private var myUserSlot = 0
    @AppStorage("heightCm") private var heightCm = 0.0

    @State private var range: TrendRange = .quarter
    @StateObject private var source = TrendSource()

    @Query(sort: \ScaleMeasurement.date)
    private var measurements: [ScaleMeasurement]

    /// This phone's profile, within the selected range.
    private var mine: [ScaleMeasurement] {
        let cutoff = range.cutoff
        return measurements.filter { m in
            (myUserSlot == 0 ? !Household.isGuest(m.userId) : m.userId == myUserSlot)
                && (cutoff.map { m.date >= $0 } ?? true)
        }
    }

    private func points(_ metric: TrendMetric) -> [TrendPoint] {
        source.points(for: metric, mine: mine, heightCm: heightCm)
    }

    var body: some View {
        let weight = points(.weight)
        let rows = TrendMetric.allCases.filter { $0 != .weight }
            .map { ($0, points($0)) }
            .filter { !$0.1.isEmpty }

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    RangePicker(range: $range)
                        .padding(.top, Space.xs)

                    if weight.isEmpty && rows.isEmpty {
                        Text("Nothing in this range yet.")
                            .font(.screenTitle)
                            .padding(.top, Space.xxl)
                        Text("Step on the scale and the line starts here.")
                            .font(.body)
                            .foregroundStyle(.ink2)
                            .padding(.top, Space.s)
                    } else {
                        Text(TrendSentence.headline(.weight, weight))
                            .font(.screenTitle)
                            .tracking(-0.6)
                            .padding(.top, Space.xxl - 4)
                        if let lately = TrendSentence.lately(.weight, weight) {
                            Text(lately).font(.body).foregroundStyle(.ink2).padding(.top, Space.s)
                        }
                        if weight.count > 1 {
                            CrayonChart(points: weight, unit: Units.weightUnit)
                                .padding(.top, Space.xl)
                        }
                        Text("Weight, body fat, lean mass and BMI include your whole Apple Health history, from every app.")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.ink2)
                            .padding(.top, Space.s)
                            .padding(.bottom, Space.l)

                        ForEach(rows, id: \.0) { metric, pts in
                            NavigationLink(value: metric) {
                                MetricRow(metric: metric, points: pts, range: range)
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                }
                .padding(.horizontal, Space.margin)
                .padding(.bottom, Space.xl)
            }
            .background(Color.ground)
            .navigationTitle("Trends")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: TrendMetric.self) { metric in
                MetricDetailView(metric: metric, points: points(metric), range: $range)
            }
            .task(id: range) { await source.load(range: range, health: health) }
        }
    }
}

private struct MetricRow: View {
    let metric: TrendMetric
    let points: [TrendPoint]
    let range: TrendRange

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.rawValue).font(.system(.body, design: .rounded, weight: .semibold))
                    if let delta = TrendSentence.rowDelta(metric, points, range) {
                        Text(delta).font(.footnote.weight(.medium)).foregroundStyle(.ink2)
                    }
                }
                Spacer(minLength: Space.s)
                if points.count > 1 { Sparkline(points: points) }
                Text(points.last.map { metric.format($0.value) } ?? "–")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .frame(minWidth: 72, alignment: .trailing)
            }
            .foregroundStyle(.ink)
            .frame(minHeight: 58)
            .contentShape(.rect)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One metric full screen, same sentence-then-line pattern as weight.
struct MetricDetailView: View {
    let metric: TrendMetric
    let points: [TrendPoint]
    @Binding var range: TrendRange

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RangePicker(range: $range).padding(.top, Space.xs)
                Text(TrendSentence.headline(metric, points))
                    .font(.screenTitle).tracking(-0.6)
                    .padding(.top, Space.xxl - 4)
                if let lately = TrendSentence.lately(metric, points) {
                    Text(lately).font(.body).foregroundStyle(.ink2).padding(.top, Space.s)
                }
                if points.count > 1 {
                    CrayonChart(points: points, unit: metric.unit).padding(.top, Space.xl)
                }
                if metric.healthQuantity == nil {
                    Text("\(metric.rawValue) has no place in Apple Health, so this line is the app's own readings.")
                        .font(.footnote.weight(.medium)).foregroundStyle(.ink2).padding(.top, Space.s)
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.bottom, Space.xl)
        }
        .background(Color.ground)
        .navigationTitle(metric.rawValue)
        .navigationBarTitleDisplayMode(.inline)
    }
}
