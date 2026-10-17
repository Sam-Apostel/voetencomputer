//
//  Components.swift
//  ScaleSync
//
//  Reusable visual components. MetricRing and BMIGauge are deliberately
//  dependency-free (plain value inputs, no environment objects) so they can be
//  reused verbatim in a future WidgetKit extension.
//

import SwiftUI

// MARK: - BodyCompositionDonut

/// Annular sector with flat radial edges and slightly rounded corners —
/// the sleep-widget segment look. `start`/`end` are fractions of the full
/// circle, measured clockwise from 12 o'clock.
struct DonutSegmentShape: Shape {
    let start: Double
    let end: Double
    let thickness: CGFloat
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerR = min(rect.width, rect.height) / 2
        let innerR = outerR - thickness
        let cr = min(cornerRadius, thickness / 3)

        func angle(_ fraction: Double) -> CGFloat {
            CGFloat(fraction * 2 * .pi - .pi / 2)
        }
        func point(_ radius: CGFloat, _ a: CGFloat) -> CGPoint {
            CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
        }

        let a0 = angle(start)
        let a1 = angle(end)
        // Angular span consumed by a corner, clamped for slivers.
        let dOut = min(cr / outerR, (a1 - a0) / 3)
        let dIn = min(cr / innerR, (a1 - a0) / 3)

        var path = Path()
        path.move(to: point(outerR, a0 + dOut))
        // Outer edge, clockwise on screen.
        path.addArc(center: center, radius: outerR,
                    startAngle: .radians(a0 + dOut),
                    endAngle: .radians(a1 - dOut),
                    clockwise: false)
        // End edge with rounded corners (quad curves through the sharp corner).
        path.addQuadCurve(to: point(outerR - cr, a1), control: point(outerR, a1))
        path.addLine(to: point(innerR + cr, a1))
        path.addQuadCurve(to: point(innerR, a1 - dIn), control: point(innerR, a1))
        // Inner edge, back counter-clockwise.
        path.addArc(center: center, radius: innerR,
                    startAngle: .radians(a1 - dIn),
                    endAngle: .radians(a0 + dIn),
                    clockwise: true)
        // Start edge with rounded corners.
        path.addQuadCurve(to: point(innerR + cr, a0), control: point(innerR, a0))
        path.addLine(to: point(outerR - cr, a0))
        path.addQuadCurve(to: point(outerR, a0 + dOut), control: point(outerR, a0))
        path.closeSubpath()
        return path
    }
}

/// Segmented donut for parts-of-a-whole data (fractions should sum to ≤ 1).
/// Flat-edged segments with slightly rounded corners, the percentage painted
/// on each segment (rotated so the text bottom faces the center), and an icon
/// with the segment's name placed radially outside it.
struct BodyCompositionDonut: View {
    struct Segment: Identifiable {
        let label: String
        let icon: String
        let fraction: Double
        let color: Color
        var id: String { label }
    }

    let segments: [Segment]

    private let thickness: CGFloat = 34
    private let gap = 0.014           // half-gap trimmed off each segment edge
    private let labelSpace: CGFloat = 46   // room around the ring for icon + name
    /// Below this fraction the percentage no longer fits on the segment and
    /// moves outside, under the icon.
    private let insideTextMinFraction = 0.09

    private func bounds(of segment: Segment) -> (start: Double, end: Double) {
        var start = 0.0
        for s in segments {
            if s.id == segment.id { break }
            start += s.fraction
        }
        return (start, start + segment.fraction)
    }

    private func percentText(_ segment: Segment) -> String {
        (segment.fraction * 100).formatted(.number.precision(.fractionLength(1))) + "%"
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let ringDiameter = side - labelSpace * 2
            let textRadius = ringDiameter / 2 - thickness / 2
            let iconRadius = ringDiameter / 2 + 28

            ZStack {
                ForEach(segments) { segment in
                    let (start, end) = bounds(of: segment)
                    // Slivers get proportionally smaller gaps so they stay
                    // visible but never fuse with their neighbors.
                    let inset = min(gap, (end - start) / 4)
                    DonutSegmentShape(start: start + inset, end: end - inset,
                                      thickness: thickness, cornerRadius: 6)
                        .fill(segment.color.gradient)
                        .frame(width: ringDiameter, height: ringDiameter)
                }

                ForEach(segments) { segment in
                    let (start, end) = bounds(of: segment)
                    let mid = (start + end) / 2
                    let midAngle = mid * 2 * .pi   // clockwise from 12 o'clock

                    // Percentage on the segment, bottom of the text facing
                    // the donut center.
                    if segment.fraction >= insideTextMinFraction {
                        Text(percentText(segment))
                            .font(.footnote.weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .fixedSize()
                            .rotationEffect(.degrees(mid * 360))
                            .offset(x: textRadius * sin(midAngle),
                                    y: -textRadius * cos(midAngle))
                    }

                    // Icon and name radially outside the segment. The name is
                    // what carries the meaning: no symbol says "fat" or "bone".
                    VStack(spacing: 1) {
                        Image(systemName: segment.icon)
                            .font(.footnote)
                        Text(segment.label)
                            .font(.caption2.weight(.semibold))
                        if segment.fraction < insideTextMinFraction {
                            Text(percentText(segment))
                                .font(.caption2.weight(.bold))
                                .monospacedDigit()
                        }
                    }
                    .foregroundStyle(segment.color)
                    .fixedSize()
                    .offset(x: iconRadius * sin(midAngle),
                            y: -iconRadius * cos(midAngle))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - BMIGauge

/// BMI shown as a marker on the WHO category bands instead of a bare number.
struct BMIGauge: View {
    let bmi: Double

    private struct Zone {
        let range: ClosedRange<Double>
        let color: Color
        let name: String
    }

    private static let zones: [Zone] = [
        Zone(range: 15...18.5, color: .blue, name: "Underweight"),
        Zone(range: 18.5...25, color: .green, name: "Healthy"),
        Zone(range: 25...30, color: .orange, name: "Overweight"),
        Zone(range: 30...40, color: .red, name: "Obese"),
    ]

    private static let span: ClosedRange<Double> = 15...40

    private var category: Zone {
        Self.zones.first { $0.range.contains(bmi) }
            ?? (bmi < Self.span.lowerBound ? Self.zones.first! : Self.zones.last!)
    }

    private func x(_ value: Double, in width: CGFloat) -> CGFloat {
        let clamped = min(max(value, Self.span.lowerBound), Self.span.upperBound)
        let fraction = (clamped - Self.span.lowerBound) / (Self.span.upperBound - Self.span.lowerBound)
        return CGFloat(fraction) * width
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("BMI", systemImage: "chart.bar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(bmi.formatted(.number.precision(.fractionLength(1))))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text(category.name)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(category.color.opacity(0.18), in: Capsule())
                    .foregroundStyle(category.color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    HStack(spacing: 2) {
                        ForEach(Self.zones, id: \.name) { zone in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(zone.color.opacity(0.5))
                                .frame(width: max(0, x(zone.range.upperBound, in: geo.size.width)
                                                     - x(zone.range.lowerBound, in: geo.size.width) - 2))
                        }
                    }
                    Capsule()
                        .fill(.primary)
                        .frame(width: 4, height: 24)
                        .overlay(Capsule().strokeBorder(.background, lineWidth: 1))
                        .offset(x: x(bmi, in: geo.size.width) - 2)
                }
            }
            .frame(height: 16)
            GeometryReader { geo in
                ForEach([18.5, 25.0, 30.0], id: \.self) { boundary in
                    Text(boundary.formatted(.number.precision(.fractionLength(boundary == 18.5 ? 1 : 0))))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                        .position(x: x(boundary, in: geo.size.width), y: 5)
                }
            }
            .frame(height: 10)
        }
    }
}

// MARK: - ScaleGlyph

/// Stylized top view of a body scale, used as imagery for the epoch selector
/// and the paired-scale row.
struct ScaleGlyph: View {
    enum Style {
        /// Square glass platform, 2×2 ITO electrodes (BS410 / BS444 / BS650 family).
        case glass2010
        /// Rounded platform with a classic round dial (older / unix-epoch models).
        case classic1970
    }

    var style: Style = .glass2010
    var size: CGFloat = 64
    var dimmed: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18)
                .fill(LinearGradient(colors: [Color(.systemGray3), Color(.systemGray5)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.18)
                        .strokeBorder(.quaternary, lineWidth: 1)
                )
            switch style {
            case .glass2010:
                // Corner electrodes
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: size * 0.06)
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: size * 0.26, height: size * 0.26)
                        .offset(x: (i % 2 == 0 ? -1 : 1) * size * 0.24,
                                y: (i < 2 ? -1 : 1) * size * 0.24)
                }
                // Display bar
                RoundedRectangle(cornerRadius: size * 0.05)
                    .fill(Color.black.opacity(0.75))
                    .frame(width: size * 0.4, height: size * 0.16)
                    .offset(y: -size * 0.24)
            case .classic1970:
                Circle()
                    .fill(Color(.systemBackground).opacity(0.9))
                    .overlay(Circle().strokeBorder(.quaternary, lineWidth: 1))
                    .frame(width: size * 0.5, height: size * 0.5)
                    .offset(y: -size * 0.12)
                Rectangle()
                    .fill(Color.red.opacity(0.7))
                    .frame(width: 1.5, height: size * 0.18)
                    .offset(y: -size * 0.12)
            }
        }
        .frame(width: size, height: size)
        .opacity(dimmed ? 0.4 : 1)
    }
}
