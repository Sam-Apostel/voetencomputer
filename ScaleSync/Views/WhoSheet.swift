//
//  WhoSheet.swift
//  ScaleSync
//
//  "Who was that?": a weigh-in neither the scale nor the weight matching
//  could place. Each person is a pair of feet drawn to size; a visitor can be
//  kept as a guest, who never goes to Apple Health.
//

import SwiftUI
import SwiftData

struct WhoSheet: View {
    let measurement: ScaleMeasurement

    @EnvironmentObject var health: HealthSync
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("myUserSlot") private var myUserSlot = 0
    @AppStorage(UserProfiles.defaultsKey) private var userNamesJSON = "{}"

    @Query(sort: \ScaleMeasurement.date, order: .reverse)
    private var measurements: [ScaleMeasurement]

    private enum Choice: Hashable { case slot(Int), guest }
    @State private var choice: Choice = .guest
    @State private var guestName = ""
    @State private var confirmDelete = false
    @FocusState private var nameFocused: Bool

    /// Profiles worth offering: named ones, ones with history, guests, and
    /// always this phone's own profile (listed first).
    private var people: [(slot: Int, last: Double?)] {
        let named = Set(UserProfiles.decode(userNamesJSON).keys)
        let withHistory = Set(measurements.lazy.filter { $0.userId > 0 }.map(\.userId))
        let slots = named.union(withHistory).union(myUserSlot > 0 ? [myUserSlot] : [])
            .filter { $0 > 0 }
            .sorted { ($0 == myUserSlot ? 0 : $0) < ($1 == myUserSlot ? 0 : $1) }
        return slots.map { slot in
            (slot, measurements.first { $0.userId == slot && $0.weightKg > 0 }?.weightKg)
        }
    }

    private var heaviest: Double {
        max(people.compactMap(\.last).max() ?? measurement.weightKg, measurement.weightKg, 1)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .bottom) {
                        Text("Who was that?").font(.screenTitle).tracking(-0.6)
                        Spacer()
                        FeetGlyph(dotted: true).frame(width: feetSize(measurement.weightKg) + 8)
                    }
                    Text("Someone weighed \(Units.weightString(measurement.weightKg).replacingOccurrences(of: " ", with: "\u{00A0}")) \(Say.dayReference(measurement.date, relativeTo: .now)) at \(measurement.date.formatted(date: .omitted, time: .shortened)). The scale didn't know them, and nobody here is within \(Int(ProfileMatcher.toleranceKg))\u{00A0}kg.")
                        .font(.body)
                        .foregroundStyle(.ink2)
                        .padding(.top, Space.s)

                    VStack(spacing: 0) {
                        ForEach(people, id: \.slot) { person in
                            choiceRow(.slot(person.slot)) {
                                FeetGlyph(dotted: Household.isGuest(person.slot))
                                    .frame(width: feetSize(person.last ?? heaviest))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(UserProfiles.displayName(slot: person.slot, json: userNamesJSON))
                                        .font(.system(.body, design: .rounded, weight: .semibold))
                                    if let last = person.last {
                                        Text("last \(Units.weightString(last))")
                                            .font(.subheadline.weight(.medium)).foregroundStyle(.ink2)
                                            .monospacedDigit()
                                    }
                                }
                            }
                        }
                        choiceRow(.guest) {
                            FeetGlyph(dotted: true).frame(width: feetSize(measurement.weightKg))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("A guest called").font(.subheadline.weight(.medium)).foregroundStyle(.ink2)
                                TextField("Name", text: $guestName)
                                    .font(.system(.body, design: .rounded, weight: .semibold))
                                    .focused($nameFocused)
                                    .submitLabel(.done)
                                    .padding(.bottom, 2)
                                    .overlay(alignment: .bottom) {
                                        Rectangle().fill(Color.crayon).frame(height: 2)
                                    }
                            }
                        }
                        Hairline()
                    }
                    .padding(.top, Space.xl)

                    VStack(spacing: 6) {
                        Button(primaryTitle) { save() }
                            .buttonStyle(CrayonButtonStyle())
                            .disabled(choice == .guest && guestName.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button("Not one of us") { confirmDelete = true }
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .foregroundStyle(.ink)
                            .frame(minHeight: 44)
                        Text("Guests never go to Apple Health.")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.ink2)
                    }
                    .padding(.top, Space.xl)
                }
                .padding(.horizontal, Space.margin)
                .padding(.vertical, Space.l)
            }
            .background(Color.raised)
            .confirmationDialog("Delete this weigh-in?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete \(Units.weightString(measurement.weightKg))", role: .destructive) {
                    context.delete(measurement)
                    try? context.save()
                    dismiss()
                }
            } message: {
                Text("It was nobody in this household. It hasn't gone to Apple Health.")
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.raised)
        .sensoryFeedback(.selection, trigger: choice)
    }

    private var primaryTitle: String {
        switch choice {
        case .slot(let slot): return "This was \(UserProfiles.displayName(slot: slot, json: userNamesJSON))"
        case .guest:
            let name = guestName.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? "Keep as a guest" : "Keep as \(name) (guest)"
        }
    }

    /// Feet drawn to size: the heaviest person gets 44pt, a child about half.
    private func feetSize(_ kg: Double) -> CGFloat {
        CGFloat(22 + 22 * min(1, kg / heaviest))
    }

    private func choiceRow<Content: View>(_ value: Choice, @ViewBuilder content: () -> Content) -> some View {
        Button {
            choice = value
            if value == .guest { nameFocused = true }
        } label: {
            HStack(spacing: Space.l) {
                content()
                Spacer(minLength: 0)
                Circle()
                    .strokeBorder(choice == value ? Color.crayon : Color.rule, lineWidth: 2.5)
                    .overlay(Circle().fill(choice == value ? Color.crayon : .clear).padding(7))
                    .frame(width: 26, height: 26)
            }
            .foregroundStyle(.ink)
            .frame(minHeight: 72)
            .overlay(alignment: .top) { Hairline() }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(choice == value ? .isSelected : [])
    }

    private func save() {
        let slot: Int
        switch choice {
        case .slot(let s): slot = s
        case .guest:
            slot = Household.addGuest(named: guestName.trimmingCharacters(in: .whitespaces), json: &userNamesJSON)
        }
        assign(to: slot)
        dismiss()
    }

    /// Move a weigh-in to a profile. The key encodes the profile, so it changes
    /// too; if that profile already has this weigh-in, the duplicate goes.
    private func assign(to slot: Int) {
        let newKey = ScaleMeasurement.makeKey(date: measurement.date, userId: slot)
        let existing = try? context.fetch(FetchDescriptor<ScaleMeasurement>(
            predicate: #Predicate { $0.key == newKey })).first
        if existing != nil {
            context.delete(measurement)
        } else {
            measurement.userId = slot
            measurement.key = newKey
            measurement.healthSynced = false
        }
        try? context.save()
        health.pushUnsynced(container: context.container)
    }
}

/// Steps to make the scale recognise someone again, shown right after a
/// weigh-in it couldn't assign, or from Household › Teach it again.
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
                VStack(alignment: .leading, spacing: Space.l) {
                    ScaleGlyph(lineWidth: 3).frame(width: 64)
                    Text(name.map { "The scale only measured \($0)'s weight. That's saved, but body composition needs the scale to recognise who's standing on it." }
                         ?? "The scale only measured your weight. That's saved, but body composition needs the scale to recognise you.")
                        .font(.body)
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                            Text("\(index + 1)")
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(.crayon)
                                .frame(width: 28, height: 28)
                                .background(Circle().strokeBorder(Color.crayon, lineWidth: 2))
                            Text(step).font(.body)
                        }
                    }
                }
                .padding(.horizontal, Space.margin)
                .padding(.vertical, Space.l)
            }
            .background(Color.raised)
            .navigationTitle(name.map { "\($0) wasn't recognised" } ?? "Teach the scale again")
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
