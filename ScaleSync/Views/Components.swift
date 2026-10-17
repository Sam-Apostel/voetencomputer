//
//  Components.swift
//  ScaleSync
//
//  Drawn components shared by the screens: the composition bar and column,
//  the BMI band, the crayon line chart and sparkline, the range picker.
//  Composition fills always mean the same thing: solid = fat, hatched =
//  muscle, wash = bone, empty = the rest. Water overlaps muscle, so it is
//  never a slice.
//

import SwiftUI

// MARK: - Composition

struct Composition {
    let fatPercent: Double
    let musclePercent: Double
    let bonePercent: Double
    let boneKg: Double
    let waterPercent: Double?
    let weightKg: Double

    init?(_ m: ScaleMeasurement) {
        guard m.weightKg > 0, let fat = m.fatPercent, let muscle = m.musclePercent else { return nil }
        weightKg = m.weightKg
        fatPercent = fat
        musclePercent = muscle
        boneKg = m.boneKg ?? 0
        bonePercent = boneKg / m.weightKg * 100
        waterPercent = m.waterPercent
    }

    var restPercent: Double { max(0, 100 - fatPercent - musclePercent - bonePercent) }
    var fatKg: Double { weightKg * fatPercent / 100 }
    var muscleKg: Double { weightKg * musclePercent / 100 }
    var restKg: Double { max(0, weightKg - fatKg - muscleKg - boneKg) }
}

/// One crayon bar, left to right: fat, muscle, bone, rest.
struct CompositionBar: View {
    let composition: Composition

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 3
            let usable = geo.size.width - gap * 3
            HStack(spacing: gap) {
                CrayonCell(fill: .solid).frame(width: max(10, usable * composition.fatPercent / 100))
                CrayonCell(fill: .hatched).frame(width: max(10, usable * composition.musclePercent / 100))
                CrayonCell(fill: .wash).frame(width: max(10, usable * composition.bonePercent / 100))
                CrayonCell(fill: .empty)
            }
        }
        .frame(height: 28)
        .crayon(2.4, scale: 20)
        .accessibilityHidden(true)
    }
}

/// The legend under the bar; each value with a swatch of its fill.
struct CompositionLegend: View {
    let composition: Composition

    var body: some View {
        HStack(alignment: .top) {
            item(percent(composition.fatPercent), "fat", .solid)
            Spacer(minLength: 4)
            item(percent(composition.musclePercent), "muscle", .hatched)
            Spacer(minLength: 4)
            item(Units.weightString(composition.boneKg), "bone", .wash)
            Spacer(minLength: 4)
            if let water = composition.waterPercent {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(percent(water)).font(.system(.body, design: .rounded, weight: .bold))
                    Text("water").font(.footnote.weight(.medium)).foregroundStyle(.ink2)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .monospacedDigit()
    }

    private func item(_ value: String, _ label: String, _ fill: CrayonFill) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(.body, design: .rounded, weight: .bold))
            HStack(spacing: 5) {
                CrayonCell(fill: fill, radius: 3, lineWidth: 2).frame(width: 12, height: 12)
                Text(label).font(.footnote.weight(.medium)).foregroundStyle(.ink2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

func percent(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(1))) + "%"
}

/// Body's hero: the whole weight as one column, split into the fills.
struct CompositionColumn: View {
    let composition: Composition

    private var bands: [(fill: CrayonFill, kg: Double, title: String, detail: String)] {
        [
            (.dashed, composition.restKg, Units.weightString(composition.restKg), "the rest: organs, blood, skin"),
            (.solid, composition.fatKg, Units.weightString(composition.fatKg), "fat · \(percent(composition.fatPercent))"),
            (.hatched, composition.muscleKg, Units.weightString(composition.muscleKg), "muscle · \(percent(composition.musclePercent))"),
            (.wash, composition.boneKg, Units.weightString(composition.boneKg), "bone"),
        ]
    }

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 4
            let minBand: CGFloat = 24
            let total = bands.map(\.kg).reduce(0, +)
            let usable = geo.size.height - gap * CGFloat(bands.count - 1) - minBand
            HStack(alignment: .top, spacing: Space.l) {
                VStack(spacing: gap) {
                    ForEach(bands.indices, id: \.self) { i in
                        CrayonCell(fill: bands[i].fill, radius: 9)
                            .frame(height: height(i, total, usable, minBand))
                    }
                }
                .frame(width: 112)
                .crayon(2.4, scale: 22)
                VStack(alignment: .leading, spacing: gap) {
                    ForEach(bands.indices, id: \.self) { i in
                        label(i)
                            .frame(height: height(i, total, usable, minBand), alignment: .leading)
                    }
                }
            }
        }
        .frame(height: 360)
    }

    private func height(_ i: Int, _ total: Double, _ usable: CGFloat, _ minBand: CGFloat) -> CGFloat {
        max(minBand, usable * bands[i].kg / max(total, 1))
    }

    @ViewBuilder private func label(_ i: Int) -> some View {
        if bands[i].fill == .wash {
            HStack(spacing: 8) {
                Text(bands[i].title).font(.system(.body, design: .rounded, weight: .bold)).monospacedDigit()
                Text(bands[i].detail).font(.subheadline.weight(.medium)).foregroundStyle(.ink2)
            }
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(bands[i].title).font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit()
                Text(bands[i].detail).font(.subheadline.weight(.medium)).foregroundStyle(.ink2)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - BMI

/// WHO bands as outlines, only the healthy band washed, a marker at the value.
/// Never borrows the fat or muscle fills, never traffic-light colours.
struct BMIBand: View {
    let bmi: Double
    private let span = 15.0...40.0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let x: (Double) -> CGFloat = { v in
                CGFloat((min(max(v, span.lowerBound), span.upperBound) - span.lowerBound)
                        / (span.upperBound - span.lowerBound)) * w
            }
            ZStack(alignment: .topLeading) {
                HStack(spacing: 3) {
                    CrayonCell(fill: .empty, radius: 4, lineWidth: 2).frame(width: x(18.5) - 3)
                    CrayonCell(fill: .wash, radius: 4, lineWidth: 2).frame(width: x(25) - x(18.5) - 3)
                    CrayonCell(fill: .empty, radius: 4, lineWidth: 2).frame(width: x(30) - x(25) - 3)
                    CrayonCell(fill: .empty, radius: 4, lineWidth: 2)
                }
                .frame(height: 12)
                .crayon(1.6, scale: 16)
                Capsule()
                    .fill(Color.ink)
                    .frame(width: 4, height: 24)
                    .overlay(Capsule().stroke(Color.ground, lineWidth: 2))
                    .offset(x: x(bmi) - 2, y: -6)
                ForEach([18.5, 25.0, 30.0], id: \.self) { v in
                    Text(v.formatted(.number.precision(.fractionLength(v == 18.5 ? 1 : 0))))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.ink2)
                        .fixedSize()
                        .position(x: x(v), y: 28)
                }
            }
        }
        .frame(height: 40)
        .accessibilityElement()
        .accessibilityLabel("BMI \(bmi.formatted(.number.precision(.fractionLength(1)))), bands at 18.5, 25 and 30")
    }

    static func band(for bmi: Double) -> String {
        switch bmi {
        case ..<18.5: return "under the healthy band, 18,5 to 25"
        case ..<25: return "in the healthy band, 18,5 to 25"
        case ..<30: return "above the healthy band, 18,5 to 25"
        default: return "well above the healthy band, 18,5 to 25"
        }
    }
}

// MARK: - Charts

/// A smoothed line through readings: a centred moving average over
/// `windowDays`, sampled every few days, so the crayon line is a trend and
/// the readings are dots on both sides of it.
func smoothed(_ points: [TrendPoint], windowDays: Double = 7) -> [TrendPoint] {
    guard let first = points.first?.date, let last = points.last?.date, points.count > 2 else { return points }
    let half = windowDays * 86400 / 2
    let total = last.timeIntervalSince(first)
    let steps = max(2, min(30, Int(total / (3 * 86400))))
    var out: [TrendPoint] = []
    for i in 0...steps {
        let t = first.addingTimeInterval(total * Double(i) / Double(steps))
        let near = points.filter { abs($0.date.timeIntervalSince(t)) <= half }
        let values = near.isEmpty ? [points.min { abs($0.date.timeIntervalSince(t)) < abs($1.date.timeIntervalSince(t)) }!.value] : near.map(\.value)
        out.append(TrendPoint(date: t, value: values.reduce(0, +) / Double(values.count)))
    }
    // End exactly on the latest reading so the circle sits on the line.
    out[out.count - 1] = TrendPoint(date: last, value: points.last!.value)
    return out
}

struct CrayonChart: View {
    let points: [TrendPoint]
    var height: CGFloat = 200
    var unit: String = ""

    var body: some View {
        let line = smoothed(points)
        let values = points.map(\.value)
        let lo = floor((values.min() ?? 0) - 0.2), hi = ceil((values.max() ?? 1) + 0.2)
        let step = Self.gridStep(hi - lo)
        let grid = stride(from: (lo / step).rounded(.up) * step, through: hi, by: step).map { $0 }
        let start = points.first?.date ?? .now, end = points.last?.date ?? .now

        GeometryReader { geo in
            let leftPad: CGFloat = 34, rightPad: CGFloat = 22, bottomPad: CGFloat = 26
            let w = geo.size.width - leftPad - rightPad, h = geo.size.height - bottomPad - 8
            let span = max(end.timeIntervalSince(start), 1)
            let pt: (TrendPoint) -> CGPoint = { p in
                CGPoint(x: leftPad + w * CGFloat(p.date.timeIntervalSince(start) / span),
                        y: 8 + h * CGFloat((hi - p.value) / max(hi - lo, 0.001)))
            }
            ZStack(alignment: .topLeading) {
                ForEach(grid, id: \.self) { g in
                    let y = 8 + h * CGFloat((hi - g) / max(hi - lo, 0.001))
                    Rectangle().fill(Color.rule).frame(width: w + rightPad, height: 1).offset(x: leftPad, y: y)
                    Text(g.formatted(.number.precision(.fractionLength(step < 1 ? 1 : 0))))
                        .font(.footnote.weight(.medium)).foregroundStyle(.ink3)
                        .offset(y: y - 9)
                }
                ForEach(Self.monthTicks(start, end), id: \.self) { d in
                    Text(d.formatted(.dateTime.month(.abbreviated)))
                        .font(.footnote.weight(.medium)).foregroundStyle(.ink3)
                        .offset(x: leftPad + w * CGFloat(d.timeIntervalSince(start) / span), y: h + 14)
                }
                Canvas { ctx, _ in
                    for p in points {
                        let c = pt(p)
                        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 2.4, y: c.y - 2.4, width: 4.8, height: 4.8)),
                                 with: .color(.crayon.opacity(0.45)))
                    }
                }
                Canvas { ctx, _ in
                    var path = Path()
                    let pts = line.map(pt)
                    guard let first = pts.first else { return }
                    path.move(to: first)
                    for i in 1..<pts.count {
                        let mid = CGPoint(x: (pts[i - 1].x + pts[i].x) / 2, y: (pts[i - 1].y + pts[i].y) / 2)
                        path.addQuadCurve(to: mid, control: pts[i - 1])
                    }
                    path.addLine(to: pts.last!)
                    ctx.stroke(path, with: .color(.crayon), style: StrokeStyle(lineWidth: 3.6, lineCap: .round, lineJoin: .round))
                    // The latest reading, circled by hand.
                    let c = pts.last!
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3.6, y: c.y - 3.6, width: 7.2, height: 7.2)), with: .color(.crayon))
                    var ring = Path()
                    ring.addArc(center: CGPoint(x: c.x + 1, y: c.y), radius: 11, startAngle: .degrees(-100), endAngle: .degrees(250), clockwise: false)
                    ctx.stroke(ring, with: .color(.crayon), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                }
                .crayon(3, scale: 26)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        guard let first = points.first, let last = points.last else { return "No readings" }
        return "\(points.count) readings, from \(first.value.formatted(.number.precision(.fractionLength(1)))) to \(last.value.formatted(.number.precision(.fractionLength(1)))) \(unit)"
    }

    static func gridStep(_ range: Double) -> Double {
        switch range {
        case ..<3: return 1
        case ..<8: return 2
        case ..<20: return 5
        default: return 10
        }
    }

    static func monthTicks(_ start: Date, _ end: Date) -> [Date] {
        let cal = Calendar.current
        var ticks: [Date] = []
        var d = cal.date(from: cal.dateComponents([.year, .month], from: start)) ?? start
        if d < start { d = cal.date(byAdding: .month, value: 1, to: d) ?? end }
        let months = cal.dateComponents([.month], from: start, to: end).month ?? 0
        let every = max(1, months / 4 + (months % 4 == 0 ? 0 : 1))
        while d <= end {
            ticks.append(d)
            d = cal.date(byAdding: .month, value: every, to: d) ?? end.addingTimeInterval(1)
        }
        return ticks
    }
}

struct Sparkline: View {
    let points: [TrendPoint]
    var body: some View {
        Canvas { ctx, size in
            let line = smoothed(points, windowDays: 21)
            guard line.count > 1, let lo = line.map(\.value).min(), let hi = line.map(\.value).max(),
                  let start = line.first?.date, let end = line.last?.date else { return }
            let span = max(end.timeIntervalSince(start), 1)
            // A flat metric stays a flat line in the middle.
            let range = max(hi - lo, 1.5)
            let mid = (hi + lo) / 2
            var path = Path()
            for (i, p) in line.enumerated() {
                let c = CGPoint(x: 2 + (size.width - 4) * CGFloat(p.date.timeIntervalSince(start) / span),
                                y: size.height / 2 - (size.height - 6) * CGFloat((p.value - mid) / range))
                i == 0 ? path.move(to: c) : path.addLine(to: c)
            }
            ctx.stroke(path, with: .color(.crayon), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 72, height: 26)
        .crayon(1.4, scale: 12)
        .accessibilityHidden(true)
    }
}

// MARK: - Range picker

struct RangePicker: View {
    @Binding var range: TrendRange

    var body: some View {
        HStack(spacing: 4) {
            ForEach(TrendRange.allCases) { r in
                Button {
                    range = r
                } label: {
                    Text(r.title)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(range == r ? Color.onCrayon : Color.ink2)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(range == r ? Color.crayon : .clear, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(range == r ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.raised, in: .capsule)
        .overlay(Capsule().strokeBorder(Color.rule, lineWidth: 1))
        .sensoryFeedback(.selection, trigger: range)
        .animation(.snappy(duration: 0.25), value: range)
    }
}
