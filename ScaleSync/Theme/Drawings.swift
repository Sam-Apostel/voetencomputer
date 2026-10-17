//
//  Drawings.swift
//  ScaleSync
//
//  The crayon vocabulary, kept small on purpose (DIRECTION.md › The richness
//  source): feet, the scale seen from above, the DIY board, the tick, and the
//  scale's seven-segment digits. Everything is drawn in .crayon and gets its
//  wobble from .crayon() at the call site.
//

import SwiftUI

// MARK: - Feet

/// A left footprint's sole in a 100 × 236 box, big toe on the inside (right).
struct SoleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 100, sy = rect.height / 236
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        path.move(to: p(50, 226))
        path.addCurve(to: p(24, 184), control1: p(30, 226), control2: p(22, 206))
        path.addCurve(to: p(20, 110), control1: p(26, 164), control2: p(18, 138))
        path.addCurve(to: p(44, 66), control1: p(21, 88), control2: p(28, 70))
        path.addCurve(to: p(85, 84), control1: p(61, 62), control2: p(80, 66))
        path.addCurve(to: p(73, 130), control1: p(89, 100), control2: p(79, 116))
        path.addCurve(to: p(73, 180), control1: p(67, 145), control2: p(73, 160))
        path.addCurve(to: p(50, 226), control1: p(73, 210), control2: p(65, 226))
        path.closeSubpath()
        return path
    }
}

/// The five toes of a left foot in the same 100 × 236 box.
struct ToesShape: Shape {
    static let toes: [(x: CGFloat, y: CGFloat, r: CGFloat)] =
        [(74, 46, 12), (54, 36, 8), (39, 39, 7), (27, 48, 6), (19, 60, 5)]

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 100, sy = rect.height / 236
        var path = Path()
        for t in Self.toes {
            path.addEllipse(in: CGRect(x: rect.minX + (t.x - t.r) * sx, y: rect.minY + (t.y - t.r) * sy,
                                       width: 2 * t.r * sx, height: 2 * t.r * sy))
        }
        return path
    }
}

/// One footprint. `filled` paints the sole with the wash; `dotted` draws it
/// as the dotted outline of feet that haven't arrived yet.
struct Footprint: View {
    var lineWidth: CGFloat = 4.5
    var filled = true
    var dotted = false

    var body: some View {
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round,
                                dash: dotted ? [0.1, lineWidth * 2] : [])
        ZStack {
            if filled && !dotted { SoleShape().fill(Color.wash) }
            SoleShape().stroke(Color.crayon, style: style)
            // A second, thinner pass slightly off the first: crayon weight varies.
            if !dotted {
                SoleShape()
                    .stroke(Color.crayon.opacity(0.45), style: StrokeStyle(lineWidth: lineWidth * 0.5, lineCap: .round))
                    .offset(x: lineWidth * 0.45, y: -lineWidth * 0.35)
            }
            ToesShape().stroke(Color.crayon, style: style)
        }
        .aspectRatio(100 / 236, contentMode: .fit)
    }
}

/// A pair of feet, slightly toed out, the right one a little ahead.
struct FeetPair: View {
    var lineWidth: CGFloat = 4.5
    var leftFilled = true
    var rightFilled = true
    var dotted = false
    /// The right foot lifts slightly while it presses in (signature frame 2).
    var rightPressing = false

    var body: some View {
        GeometryReader { geo in
            let footW = geo.size.width * 0.4
            HStack(alignment: .top, spacing: geo.size.width * 0.14) {
                Footprint(lineWidth: lineWidth, filled: leftFilled, dotted: dotted)
                    .frame(width: footW)
                    .rotationEffect(.degrees(-7))
                    .padding(.top, geo.size.height * 0.07)
                Footprint(lineWidth: lineWidth, filled: rightFilled, dotted: dotted)
                    .frame(width: footW)
                    .scaleEffect(x: -1, y: 1)
                    .rotationEffect(.degrees(5))
                    .scaleEffect(rightPressing ? 1.04 : 1, anchor: .bottom)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .aspectRatio(250 / 282, contentMode: .fit)
        .crayon()
        .accessibilityHidden(true)
    }
}

/// A small pair for rows and the bath mat. Size it with .frame.
struct FeetGlyph: View {
    var dotted = false
    var body: some View {
        HStack(spacing: 0) {
            Footprint(lineWidth: 2.2, filled: true, dotted: dotted)
                .rotationEffect(.degrees(-6))
            Spacer(minLength: 0)
            Footprint(lineWidth: 2.2, filled: true, dotted: dotted)
                .scaleEffect(x: -1, y: 1)
                .rotationEffect(.degrees(4))
                .offset(y: -2)
        }
        .padding(.horizontal, 2)
        .aspectRatio(1, contentMode: .fit)
        .crayon(1.4, scale: 10)
        .accessibilityHidden(true)
    }
}

// MARK: - The scale, the board

/// The bathroom scale from above: a rounded platform with its little display.
struct ScaleGlyph: View {
    var lineWidth: CGFloat = 2.2
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: s * 0.22, style: .continuous)
                    .strokeBorder(Color.crayon, lineWidth: lineWidth)
                RoundedRectangle(cornerRadius: s * 0.05)
                    .fill(Color.crayon)
                    .frame(width: s * 0.34, height: s * 0.16)
                    .padding(.top, s * 0.16)
                HStack(spacing: s * 0.3) {
                    Capsule().fill(Color.crayon).frame(width: lineWidth, height: s * 0.2)
                    Capsule().fill(Color.crayon).frame(width: lineWidth, height: s * 0.2)
                }
                .padding(.top, s * 0.55)
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
        .crayon(1.2, scale: 10)
        .accessibilityHidden(true)
    }
}

/// The DIY scale: a bare board, a chip and two wires.
struct BoardGlyph: View {
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 36
            func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                CGRect(x: x * s, y: y * s, width: w * s, height: h * s)
            }
            let stroke = StrokeStyle(lineWidth: 2.2 * s, lineCap: .round, lineJoin: .round)
            ctx.stroke(Path(roundedRect: r(3, 9, 30, 20), cornerRadius: 3 * s), with: .color(.crayon), style: stroke)
            ctx.fill(Path(roundedRect: r(20, 14, 8, 9), cornerRadius: 1.5 * s), with: .color(.crayon))
            var wires = Path()
            wires.move(to: CGPoint(x: 8 * s, y: 9 * s)); wires.addLine(to: CGPoint(x: 8 * s, y: 4 * s))
            wires.move(to: CGPoint(x: 13 * s, y: 9 * s))
            wires.addQuadCurve(to: CGPoint(x: 15 * s, y: 4.5 * s), control: CGPoint(x: 13 * s, y: 4.5 * s))
            wires.move(to: CGPoint(x: 8 * s, y: 23 * s)); wires.addLine(to: CGPoint(x: 15 * s, y: 23 * s))
            ctx.stroke(wires, with: .color(.crayon), style: stroke)
        }
        .aspectRatio(1, contentMode: .fit)
        .crayon(1.2, scale: 10)
        .accessibilityHidden(true)
    }
}

/// The large first-run drawing: the scale with two dotted feet waiting on it.
struct ScaleWithFeet: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: w * 0.11, style: .continuous)
                    .fill(Color.wash)
                RoundedRectangle(cornerRadius: w * 0.11, style: .continuous)
                    .strokeBorder(Color.crayon, lineWidth: 4.5)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.crayon)
                    .frame(width: w * 0.21, height: h * 0.08)
                    .padding(.top, h * 0.07)
                HStack(spacing: w * 0.1) {
                    Footprint(lineWidth: 4, filled: false, dotted: true).rotationEffect(.degrees(-7))
                    Footprint(lineWidth: 4, filled: false, dotted: true)
                        .scaleEffect(x: -1, y: 1).rotationEffect(.degrees(5))
                }
                .frame(height: h * 0.58)
                .padding(.top, h * 0.24)
            }
        }
        .aspectRatio(300 / 330, contentMode: .fit)
        .crayon()
        .accessibilityHidden(true)
    }
}

/// The household's feet on a bath mat, lined up by size (Household header).
struct BathMat: View {
    /// Relative foot sizes, largest first; `dotted` for guests.
    let people: [(size: CGFloat, dotted: Bool)]
    var width: CGFloat = 176
    private var k: CGFloat { width / 176 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.wash)
                .padding(.horizontal, 8)
            RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.crayon, lineWidth: 2.6)
                .padding(.horizontal, 8)
            HStack(spacing: 0) {
                fringe
                Spacer()
                fringe
            }
            HStack(alignment: .center, spacing: 16 * k) {
                ForEach(Array(people.enumerated()), id: \.offset) { _, person in
                    FeetGlyph(dotted: person.dotted).frame(width: 52 * k * person.size)
                }
            }
            .padding(.horizontal, 16 * k)
        }
        .frame(width: width, height: 116 * k)
        .crayon(2, scale: 18)
        .accessibilityHidden(true)
    }

    private var fringe: some View {
        VStack(spacing: 12 * k) {
            ForEach(0..<5, id: \.self) { _ in Capsule().fill(Color.crayon).frame(width: 2.2, height: 6 * k) }
        }
    }
}

// MARK: - Tick

/// The drawn tick, only ever for "in Apple Health". `progress` draws it in.
struct CrayonTick: View {
    var progress: CGFloat = 1
    var lineWidth: CGFloat = 3

    var body: some View {
        TickShape()
            .trim(from: 0, to: progress)
            .stroke(Color.crayon, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
    }
}

struct TickShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        var path = Path()
        path.move(to: CGPoint(x: 4.5 * s, y: 12.8 * s))
        path.addQuadCurve(to: CGPoint(x: 8.8 * s, y: 17.2 * s), control: CGPoint(x: 6.9 * s, y: 14.6 * s))
        path.addQuadCurve(to: CGPoint(x: 19.6 * s, y: 5.6 * s), control: CGPoint(x: 13 * s, y: 9.5 * s))
        return path
    }
}

// MARK: - Seven-segment digits

/// The scale's own LCD digits, drawn in crayon, for the hunting moment in the
/// signature. Unlit segments stay faintly visible in the wash.
struct SevenSegment: View {
    let text: String
    var height: CGFloat = 90

    private static let lit: [Character: String] = [
        "0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc",
        "5": "afgcd", "6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg",
    ]

    var body: some View {
        Canvas { ctx, _ in
            let h = height, w = h * 0.5, t = h * 0.09, g = t * 0.35
            var x: CGFloat = 0
            for ch in text {
                if ch == "," || ch == "." {
                    let dot = Path(roundedRect: CGRect(x: x, y: h - t, width: t, height: t), cornerRadius: 2)
                    ctx.fill(dot, with: .color(.crayon))
                    if ch == "," {
                        var tail = Path()
                        tail.move(to: CGPoint(x: x + t * 0.75, y: h - t * 0.3))
                        tail.addLine(to: CGPoint(x: x + t * 0.3, y: h + t * 1.2))
                        ctx.stroke(tail, with: .color(.crayon), style: StrokeStyle(lineWidth: t * 0.8, lineCap: .round))
                    }
                    x += t * 2.2
                    continue
                }
                let on = Self.lit[ch] ?? ""
                for (key, pts) in Self.segments(x: x, w: w, h: h, t: t, g: g) {
                    var p = Path(); p.addLines(pts); p.closeSubpath()
                    ctx.fill(p, with: .color(on.contains(key) ? .crayon : .wash))
                }
                x += w + t * 1.2
            }
        }
        // Room under the baseline for the comma's tail.
        .frame(width: width, height: height * 1.18, alignment: .top)
        .padding(.bottom, -height * 0.18)
        .transformEffect(CGAffineTransform(a: 1, b: 0, c: -0.07, d: 1, tx: height * 0.07, ty: 0))
        .accessibilityLabel(text)
    }

    private var width: CGFloat {
        let h = height, w = h * 0.5, t = h * 0.09
        return text.reduce(0) { $0 + (($1 == "," || $1 == ".") ? t * 2.2 : w + t * 1.2) }
    }

    private static func segments(x L: CGFloat, w: CGFloat, h: CGFloat, t: CGFloat, g: CGFloat) -> [(Character, [CGPoint])] {
        let R = L + w, M = h / 2, B = h
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        return [
            ("a", [pt(L + t, g), pt(R - t, g), pt(R - t * 1.6, t + g), pt(L + t * 1.6, t + g)]),
            ("d", [pt(L + t * 1.6, B - t - g), pt(R - t * 1.6, B - t - g), pt(R - t, B - g), pt(L + t, B - g)]),
            ("g", [pt(L + t, M), pt(L + t * 1.6, M - t / 2), pt(R - t * 1.6, M - t / 2), pt(R - t, M), pt(R - t * 1.6, M + t / 2), pt(L + t * 1.6, M + t / 2)]),
            ("f", [pt(L, t + g), pt(L + t, t * 1.6 + g), pt(L + t, M - t * 0.6), pt(L, M - t * 0.1)]),
            ("e", [pt(L, M + t * 0.1), pt(L + t, M + t * 0.6), pt(L + t, B - t * 1.6 - g), pt(L, B - t - g)]),
            ("b", [pt(R, t + g), pt(R, M - t * 0.1), pt(R - t, M - t * 0.6), pt(R - t, t * 1.6 + g)]),
            ("c", [pt(R, M + t * 0.1), pt(R, B - t - g), pt(R - t, B - t * 1.6 - g), pt(R - t, M + t * 0.6)]),
        ]
    }
}
