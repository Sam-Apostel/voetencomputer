//
//  TrendsView.swift
//  ScaleSync
//

import SwiftUI
import SwiftData
import Charts

enum TrendMetric: String, CaseIterable, Identifiable {
    case weight = "Weight"
    case fat = "Body fat"
    case water = "Water"
    case muscle = "Muscle"
    case bone = "Bone"
    case bmi = "BMI"

    var id: String { rawValue }

    var unit: String {
        switch self {
        case .weight, .bone: return "kg"
        case .fat, .water, .muscle: return "%"
        case .bmi: return ""
        }
    }

    var color: Color {
        switch self {
        case .weight: return MetricColor.weight
        case .fat: return MetricColor.fat
        case .water: return MetricColor.water
        case .muscle: return MetricColor.muscle
        case .bone: return MetricColor.bone
        case .bmi: return MetricColor.lean
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
}

struct TrendsView: View {
    @EnvironmentObject var health: HealthSync
    @AppStorage("myUserSlot") private var myUserSlot = 0

    @State private var metric: TrendMetric = .weight
    @State private var range: TrendRange = .quarter

    @Query(sort: \ScaleMeasurement.date)
    private var measurements: [ScaleMeasurement]

    private var points: [(date: Date, value: Double)] {
        measurements.compactMap { m -> (Date, Double)? in
            if myUserSlot != 0 && m.userId != myUserSlot { return nil }
            if let cutoff = range.cutoff, m.date < cutoff { return nil }
            guard let v = value(of: metric, in: m) else { return nil }
            return (m.date, v)
        }
    }

    private func value(of metric: TrendMetric, in m: ScaleMeasurement) -> Double? {
        switch metric {
        case .weight: return m.weightKg > 0 ? convert(m.weightKg) : nil
        case .fat: return m.fatPercent
        case .water: return m.waterPercent
        case .muscle: return m.musclePercent
        case .bone: return m.boneKg.map(convert)
        case .bmi: return m.bmi(heightCm: health.heightCm)
        }
    }

    private func convert(_ kg: Double) -> Double {
        Units.kgToDisplay(kg)
    }

    private var unitLabel: String {
        if metric.unit == "kg" { return Units.weightUnit }
        return metric.unit
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Metric", selection: $metric) {
                    ForEach(TrendMetric.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)

                Picker("Range", selection: $range) {
                    ForEach(TrendRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if points.isEmpty {
                    ContentUnavailableView("No data for this range",
                                           systemImage: "chart.xyaxis.line")
                    Spacer()
                } else {
                    chart
                    summary
                    Spacer()
                }
            }
            .padding()
            .navigationTitle("Trends")
        }
    }

    private var chart: some View {
        Chart(points, id: \.date) { point in
            LineMark(
                x: .value("Date", point.date),
                y: .value(metric.rawValue, point.value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(metric.color)

            PointMark(
                x: .value("Date", point.date),
                y: .value(metric.rawValue, point.value)
            )
            .symbolSize(20)
            .foregroundStyle(metric.color)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 280)
    }

    private var summary: some View {
        let values = points.map(\.value)
        let latest = values.last ?? 0
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 0
        let delta = values.count > 1 ? latest - values[0] : 0

        return HStack {
            stat("Latest", latest)
            stat("Δ range", delta, signed: true)
            stat("Min", minV)
            stat("Max", maxV)
        }
        .frame(maxWidth: .infinity)
    }

    private func stat(_ title: String, _ value: Double, signed: Bool = false) -> some View {
        VStack {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(signed && value > 0 ? "+" : "")\(value.formatted(.number.precision(.fractionLength(1)))) \(unitLabel)")
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
    }
}
