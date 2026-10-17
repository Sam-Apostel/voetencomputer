//
//  Theme.swift
//  ScaleSync
//
//  The redesign's tokens (design/DIRECTION.md › Tokens). Colours live in the
//  asset catalog by role, with light ("drawing paper") and dark ("blue paper
//  at night") values: .ground, .raised, .ink, .ink2, .ink3, .rule, .crayon,
//  .wash, .onCrayon. The crayon is the only colour; its one role is "the
//  drawn mark" (drawings, the Apple Health tick, selection).
//
//  Type is SF Pro Rounded everywhere, set once at the root with
//  .fontDesign(.rounded).
//

import SwiftUI

extension Font {
    /// 104pt heavy: the weight on Now. One per screen.
    static let hero = Font.system(size: 104, weight: .heavy, design: .rounded).monospacedDigit()
    /// 34pt bold: screen titles and Trends' sentence.
    static let screenTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
    /// 20pt medium: the sentence under the hero.
    static let say = Font.system(.title3, design: .rounded, weight: .medium)
}

enum Space {
    static let xs = 4.0, s = 8.0, m = 12.0, l = 16.0, xl = 24.0, xxl = 32.0, rest = 48.0
    /// The one side margin.
    static let margin = 20.0
}

// MARK: - Crayon

extension View {
    /// Hand-drawn wobble for drawings. Not for text.
    func crayon(_ amount: Double = 3.4, scale: Double = 24) -> some View {
        self
            .padding(amount)
            .distortionEffect(
                ShaderLibrary.crayon(.float(amount), .float(scale)),
                maxSampleOffset: CGSize(width: amount, height: amount))
            .padding(-amount)
    }
}

/// The three fills that carry meaning: solid = fat, hatched = muscle,
/// wash = bone, empty = everything else.
enum CrayonFill {
    case solid, hatched, wash, empty, dashed
}

/// 45° crayon hatching inside any rect.
struct Hatching: View {
    var color: Color = .crayon
    var lineWidth: CGFloat = 2.5
    var spacing: CGFloat = 7

    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            var x = -size.height
            while x < size.width + size.height {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
        }
    }
}

/// A rounded crayon cell in one of the meaning-carrying fills.
struct CrayonCell: View {
    let fill: CrayonFill
    var radius: CGFloat = 7
    var lineWidth: CGFloat = 2.5

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            switch fill {
            case .solid: shape.fill(Color.crayon)
            case .hatched: Hatching().clipShape(shape)
            case .wash: shape.fill(Color.wash)
            case .empty, .dashed: Color.clear
            }
            shape.strokeBorder(Color.crayon,
                               style: StrokeStyle(lineWidth: lineWidth,
                                                  dash: fill == .dashed ? [2, 7] : []))
        }
    }
}

// MARK: - Glass pill used in toolbars

struct PillLabel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 8) { content }
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .glassEffect(.regular.interactive(), in: .capsule)
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

/// The crayon capsule button (primary action).
struct CrayonButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded, weight: .bold))
            .foregroundStyle(.onCrayon)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Color.crayon, in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

/// Section label above a hairline group (sentence case, ink-2, semibold).
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Space.xxl - 4)
            .padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

struct Hairline: View {
    var leading: CGFloat = 0
    var body: some View {
        Rectangle().fill(Color.rule).frame(height: 0.5).padding(.leading, leading)
    }
}
