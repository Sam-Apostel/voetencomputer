//
//  BodyView.swift
//  ScaleSync
//
//  One reading's body composition: the whole weight as a crayon column split
//  into fat, muscle, bone and the rest, then every number, marked where it
//  goes to Apple Health.
//

import SwiftUI

struct BodyView: View {
    let measurement: ScaleMeasurement
    @AppStorage("heightCm") private var heightCm = 0.0

    private var title: String {
        let cal = Calendar.current
        if cal.isDateInToday(measurement.date) { return "Today's body" }
        if cal.isDateInYesterday(measurement.date) { return "Yesterday's body" }
        return "\(measurement.date.formatted(.dateTime.weekday(.wide)))'s body"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.screenTitle).tracking(-0.6)
                Text(meta)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.ink2)
                    .monospacedDigit()
                    .padding(.top, Space.xs)

                if let c = Composition(measurement) {
                    CompositionColumn(composition: c)
                        .padding(.top, Space.xxl - 4)
                }

                VStack(spacing: 0) {
                    if let fat = measurement.fatPercent {
                        row("Body fat", value: percent(fat), inHealth: true)
                    }
                    if let lean = measurement.leanBodyMassKg {
                        row("Lean mass", value: Units.weightString(lean), inHealth: true)
                    }
                    if let bmi = measurement.bmi(heightCm: heightCm) {
                        VStack(alignment: .leading, spacing: 10) {
                            row("BMI", detail: BMIBand.band(for: bmi),
                                value: bmi.formatted(.number.precision(.fractionLength(1))), inHealth: true, rule: false)
                            BMIBand(bmi: bmi)
                                .padding(.bottom, Space.xs)
                        }
                        .overlay(alignment: .top) { Hairline() }
                    } else {
                        row("BMI", detail: "add your height in Household", value: "–", inHealth: false)
                    }
                    if let water = measurement.waterPercent {
                        row("Water", detail: "overlaps muscle, so it's not in the column", value: percent(water), inHealth: false)
                    }
                    if let kcal = measurement.kcal, kcal > 0 {
                        row("Daily energy", detail: "what the scale estimates you burn",
                            value: "\(kcal.formatted()) kcal", inHealth: false)
                    }
                    Hairline()
                }
                .padding(.top, Space.xxl)

                Text("Body fat, lean mass and BMI go to Apple Health. The rest has no place there, so it stays here.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.ink2)
                    .padding(.top, Space.m)
            }
            .padding(.horizontal, Space.margin)
            .padding(.bottom, Space.rest)
        }
        .background(Color.ground)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var meta: String {
        var parts = [measurement.date.formatted(date: .omitted, time: .shortened)]
        if measurement.userId > 0 && !Household.isGuest(measurement.userId) { parts.append("P\(measurement.userId)") }
        if measurement.source == "csv" { parts.append("from VitaDock") }
        return parts.joined(separator: " · ")
    }

    private func row(_ title: String, detail: String? = nil, value: String, inHealth: Bool, rule: Bool = true) -> some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                if let detail {
                    Text(detail).font(.footnote.weight(.medium)).foregroundStyle(.ink2)
                }
            }
            Spacer(minLength: Space.s)
            Text(value)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .monospacedDigit()
            if inHealth {
                HStack(spacing: 3) {
                    CrayonTick(lineWidth: 2.2).frame(width: 16, height: 16)
                    Text("Health")
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.crayon)
                .accessibilityLabel("goes to Apple Health")
            }
        }
        .frame(minHeight: 56)
        .overlay(alignment: .top) { if rule { Hairline() } }
        .accessibilityElement(children: .combine)
    }
}
