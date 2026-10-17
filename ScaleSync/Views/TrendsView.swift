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

    var color: Color {
        switch self {
        case .weight: MetricColor.weight
        case .fat: MetricColor.fat
        case .muscle: MetricColor.muscle
        case .water: MetricColor.water
        case .bone: MetricColor.bone
        case .lean: MetricColor.lean
        case .bmi: Color.purple
        }
    }

    var icon: String {
        switch self {
        case .weight: "scalemass"
        case .fat: "circle.hexagongrid"
        case .muscle: "dumbbell"
        case .water: "drop"
        case .bone: "figure.stand"
        case .lean: "figure"
        case .bmi: "chart.bar"
        }
    }

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

    var phrase: String {
        switch self {
        case .month: "in 30 days"
        case .quarter: "in 90 days"
        case .year: "in a year"
        case .all: "overall"
        }
    }
}

struct TrendsView: View {
    @EnvironmentObject var health: HealthSync
    @AppStorage("myUserSlot") private var myUserSlot = 0

    @State private var range: TrendRange = .quarter
    @State private var healthPoints: [TrendMetric: [TrendPoint]] = [:]

    @Query(sort: \ScaleMeasurement.date)
    private var measurements: [ScaleMeasurement]

    /// This phone's profile, within the selected range.
    private var mine: [ScaleMeasurement] {
        let cutoff = range.cutoff
        return measurements.filter { m in
            (myUserSlot == 0 || m.userId == myUserSlot) && (cutoff.map { m.date >= $0 } ?? true)
        }
    }

    private func localPoints(_ metric: TrendMetric, from source: [ScaleMeasurement]) -> [TrendPoint] {
        source.compactMap { m in
            metric.localValue(m, heightCm: health.heightCm).map { TrendPoint(date: m.date, value: $0) }
        }
    }

    private func points(for metric: TrendMetric) -> [TrendPoint] {
        guard let fromHealth = healthPoints[metric], !fromHealth.isEmpty else {
            return localPoints(metric, from: mine)
        }
        // Health already has everything this app wrote; only add what is
        // still waiting to be written.
        let pending = localPoints(metric, from: mine.filter { !$0.healthSynced })
        return (fromHealth + pending).sorted { $0.date < $1.date }
    }

    var body: some View {
        let charts = TrendMetric.allCases
            .map { MetricSeries(metric: $0, points: points(for: $0)) }
            .filter { !$0.points.isEmpty }

        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Picker("Range", selection: $range) {
                        ForEach(TrendRange.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if charts.isEmpty {
                        ContentUnavailableView("No data for this range",
                                               systemImage: "chart.xyaxis.line")
                            .padding(.top, 40)
                    } else {
                        ForEach(charts) { series in
                            chartCard(series.metric, points: series.points)
                        }
                        Text("Weight, body fat, lean mass and BMI include your full Apple Health history, from every app.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .navigationTitle("Trends")
            .task(id: range) {
                await health.requestAuthorization()
                await loadHealthHistory()
            }
        }
    }

    private func loadHealthHistory() async {
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

    private func chartCard(_ metric: TrendMetric, points: [TrendPoint]) -> some View {
        let latest = points.last?.value ?? 0
        let delta = latest - (points.first?.value ?? latest)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label(metric.rawValue, systemImage: metric.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(metric.color)
                Spacer()
                Text(metric.format(latest))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
            if points.count > 1 {
                Text("\(delta >= 0 ? "+" : "−")\(metric.format(abs(delta))) \(range.phrase)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Chart(points) { point in
                LineMark(x: .value("Date", point.date),
                         y: .value(metric.rawValue, point.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(metric.color)
                if points.count <= 60 {
                    PointMark(x: .value("Date", point.date),
                              y: .value(metric.rawValue, point.value))
                        .symbolSize(14)
                        .foregroundStyle(metric.color)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 130)
        }
        .padding()
        .background(metric.color.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}
