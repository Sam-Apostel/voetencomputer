//
//  HouseholdView.swift
//  ScaleSync
//
//  People on the scale, the scales themselves, and Apple Health. Shaking the
//  phone reveals the advanced rows (scale clock, VitaDock import, Bluetooth
//  log, and in debug builds the sample-data tools).
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct HouseholdView: View {
    @EnvironmentObject var scaleManager: ScaleManager
    @EnvironmentObject var health: HealthSync
    @Environment(\.modelContext) private var context

    @AppStorage("myUserSlot") private var myUserSlot = 0
    @AppStorage("heightCm") private var heightCm = 0.0
    @AppStorage("scaleEpoch") private var scaleEpochRaw = ScaleTimeEpoch.year2010.rawValue
    @AppStorage(UserProfiles.defaultsKey) private var userNamesJSON = "{}"
    @AppStorage(Household.showEveryoneKey) private var showEveryone = false
    /// Toggled by shaking the phone (see ScaleSyncApp).
    @AppStorage("showAdvancedSettings") private var showAdvanced = false

    @Query(sort: \ScaleMeasurement.date, order: .reverse)
    private var measurements: [ScaleMeasurement]

    @State private var showImporter = false
    @State private var importMessage: String?
    @State private var healthMessage: String?
    @State private var resyncing = false
    @State private var confirmForget = false
    @State private var confirmForgetDIY = false
    @State private var showTeach = false

    struct Person: Identifiable {
        let slot: Int
        let name: String
        let last: Double?
        var id: Int { slot }
    }

    /// Named profiles, profiles with history, guests, and this phone's own
    /// profile; this phone first, then the scale's order, guests last.
    private var people: [Person] {
        let names = UserProfiles.decode(userNamesJSON)
        let withHistory = Set(measurements.lazy.filter { $0.userId > 0 }.map(\.userId))
        let slots = Set(names.keys).union(withHistory).union(myUserSlot > 0 ? [myUserSlot] : [])
            .filter { $0 > 0 }
            .sorted { ($0 == myUserSlot ? 0 : $0) < ($1 == myUserSlot ? 0 : $1) }
        return slots.map { slot in
            Person(slot: slot,
                   name: UserProfiles.displayName(slot: slot, json: userNamesJSON),
                   last: measurements.first { $0.userId == slot && $0.weightKg > 0 }?.weightKg)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    peopleSection
                    scalesSection
                    healthSection
                    Text("Re-sync writes your readings to Apple Health again and replaces what's there. Shake the phone for the scale clock, VitaDock import and the Bluetooth log.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.ink2)
                        .padding(.top, Space.m)
                    if showAdvanced {
                        advancedSection
                    }
                }
                .padding(.horizontal, Space.margin)
                .padding(.bottom, Space.rest)
            }
            .background(Color.ground)
            .toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(for: Int.self) { slot in
                PersonView(slot: slot)
            }
            .navigationDestination(for: String.self) { _ in DebugLogView() }
            .sheet(isPresented: $showTeach) {
                RecognitionHelpSheet(slot: max(myUserSlot, 1), name: nil)
            }
            .confirmationDialog("Forget the Medisana scale?", isPresented: $confirmForget, titleVisibility: .visible) {
                Button("Forget", role: .destructive) { scaleManager.forgetScale() }
            } message: {
                Text("Readings stay. Step on the scale to pair it again.")
            }
            .confirmationDialog("Forget the DIY scale?", isPresented: $confirmForgetDIY, titleVisibility: .visible) {
                Button("Forget", role: .destructive) { scaleManager.forgetDIYScale() }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.commaSeparatedText, .plainText, .data]) { result in
                switch result {
                case .success(let url):
                    do {
                        let r = try VitaDockCSVImporter.importCSV(at: url, container: context.container)
                        importMessage = "Imported \(r.imported), skipped \(r.skipped)."
                        health.pushUnsynced(container: context.container)
                    } catch {
                        importMessage = "Import failed: \(error.localizedDescription)"
                    }
                case .failure(let error):
                    importMessage = "Import failed: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        let heaviest = max(people.compactMap(\.last).max() ?? 1, 1)
        let feet = people.prefix(3).map {
            (size: CGFloat(0.45 + 0.55 * min(1, ($0.last ?? heaviest) / heaviest)),
             dotted: Household.isGuest($0.slot))
        }
        let title = Text("Household").font(.screenTitle).tracking(-0.6).lineLimit(1).fixedSize()
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom) {
                title
                Spacer(minLength: Space.s)
                if !people.isEmpty { BathMat(people: feet) }
            }
            // Narrow phones: the mat shrinks before the title wraps.
            HStack(alignment: .bottom) {
                title
                Spacer(minLength: Space.s)
                if !people.isEmpty { BathMat(people: feet, width: 120) }
            }
        }
        .padding(.top, Space.l)
    }

    // MARK: People

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("People on this scale")
            Hairline()
            if people.isEmpty {
                Text("Nobody yet. Whoever steps on first shows up here.")
                    .font(.body).foregroundStyle(.ink2)
                    .frame(minHeight: 56)
            }
            ForEach(people) { person in
                NavigationLink(value: person.slot) {
                    row(leading: AnyView(FeetGlyph(dotted: Household.isGuest(person.slot))
                                          .frame(width: feetWidth(person))),
                        title: person.name, detail: detail(for: person), chevron: true)
                }
                .buttonStyle(PressStyle())
                if person.slot == myUserSlot {
                    heightRow
                }
            }
            HStack {
                Text("Show everyone's numbers").font(.body)
                Spacer()
                Toggle("Show everyone's numbers", isOn: $showEveryone).labelsHidden()
            }
            .frame(minHeight: 56)
            .overlay(alignment: .top) { Hairline() }
            Hairline()
        }
    }

    private func feetWidth(_ person: Person) -> CGFloat {
        let heaviest = max(people.compactMap(\.last).max() ?? 1, 1)
        return CGFloat(20 + 16 * min(1, (person.last ?? heaviest) / heaviest))
    }

    private func detail(for person: Person) -> String {
        if Household.isGuest(person.slot) {
            let count = measurements.filter { $0.userId == person.slot }.count
            return "Guest · \(count) reading\(count == 1 ? "" : "s"), not in Health"
        }
        return person.slot == myUserSlot ? "This phone · P\(person.slot)" : "P\(person.slot)"
    }

    private var heightRow: some View {
        HStack {
            Text("Height").font(.body)
            Spacer()
            TextField("e.g. 180",
                      value: Binding<Double?>(
                        get: { heightCm > 0 ? heightCm : nil },
                        set: { heightCm = $0 ?? 0 }),
                      format: .number.grouping(.never))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(.crayon)
                .frame(width: 70)
            Text("cm").font(.system(.body, design: .rounded, weight: .semibold)).foregroundStyle(.crayon)
        }
        .padding(.leading, 50)
        .frame(minHeight: 48)
        .overlay(alignment: .top) { Hairline(leading: 50) }
        .onChange(of: heightCm) {
            // Height affects BMI — re-push so Health gets the new values.
            health.resyncAll(container: context.container)
        }
    }

    // MARK: Scales

    private var scalesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Scales")
            Hairline()
            if scaleManager.isPaired {
                Button { confirmForget = true } label: {
                    row(leading: AnyView(ScaleGlyph().frame(width: 32)),
                        title: "Medisana scale", detail: seen(.medisana), chevron: false)
                }
                .buttonStyle(PressStyle())
                .accessibilityHint("Offers to forget this scale")
            }
            if scaleManager.isDIYPaired {
                Button { confirmForgetDIY = true } label: {
                    row(leading: AnyView(BoardGlyph().frame(width: 32)),
                        title: scaleManager.diyName ?? "DIY scale",
                        detail: ["DIY ESP32", scaleManager.diyBattery.map { "battery \($0)%" }, seen(.diy)]
                            .compactMap { $0 }.joined(separator: " · "),
                        chevron: false)
                }
                .buttonStyle(PressStyle())
                .accessibilityHint("Offers to forget this scale")
            }
            Button { scaleManager.addScale() } label: {
                row(leading: nil,
                    title: scaleManager.status == .scanning ? "Listening for a scale…" : "Add a scale",
                    detail: "A BS 410, 444 or 650, or a DIY scale on the Weight Scale Service",
                    chevron: false, tint: true)
            }
            .buttonStyle(PressStyle())
            if myUserSlot > 0 && scaleManager.isPaired {
                Button { showTeach = true } label: {
                    row(leading: nil, title: "Scale forgot you? Teach it again", detail: nil, chevron: true, quiet: true)
                }
                .buttonStyle(PressStyle())
            }
            Hairline()
        }
    }

    private func seen(_ kind: ScaleKind) -> String {
        guard let date = scaleManager.lastSeen[kind] else { return "Paired" }
        let cal = Calendar.current
        let when = cal.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : Say.dayReference(date, relativeTo: .now)
        return "Paired · last seen \(when)"
    }

    // MARK: Health

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Apple Health")
            Hairline()
            HStack(spacing: Space.l) {
                if health.authorized {
                    CrayonTick().frame(width: 26)
                    Text("Connected").font(.body)
                    Spacer()
                    Button(resyncing ? "Re-syncing…" : "Re-sync all") { resync() }
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(.crayon)
                        .disabled(resyncing)
                } else {
                    Text("Not allowed yet").font(.body)
                    Spacer()
                    Button("Allow") { Task { await health.requestAuthorization() } }
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(.onCrayon)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 36)
                        .background(Color.crayon, in: .capsule)
                }
            }
            .frame(minHeight: 56)
            if let healthMessage {
                Text(healthMessage).font(.footnote.weight(.medium)).foregroundStyle(.ink2)
                    .padding(.bottom, Space.s)
            }
            Hairline()
        }
    }

    private func resync() {
        resyncing = true
        healthMessage = nil
        health.resyncAll(container: context.container) { result in
            resyncing = false
            switch result {
            case .saved(let count):
                healthMessage = "Wrote \(count) reading\(count == 1 ? "" : "s") to Apple Health."
            case .nothingToDo:
                healthMessage = "Nothing to write yet: there are no readings for your profile."
            case .failed(let reason):
                healthMessage = "Couldn't write to Apple Health: \(reason)"
            case .unavailable:
                healthMessage = "Apple Health isn't available on this device."
            }
        }
    }

    // MARK: Rows

    private func row(leading: AnyView?, title: String, detail: String?, chevron: Bool,
                     tint: Bool = false, quiet: Bool = false) -> some View {
        HStack(spacing: 14) {
            if let leading {
                leading.frame(width: 36)
            } else {
                Color.clear.frame(width: 36, height: 1)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.body, design: .rounded, weight: quiet ? .regular : .semibold))
                    .foregroundStyle(tint ? Color.crayon : quiet ? Color.ink2 : Color.ink)
                if let detail {
                    Text(detail).font(.footnote.weight(.medium)).foregroundStyle(.ink2)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
            if chevron {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.ink3)
            }
        }
        .frame(minHeight: 62)
        .overlay(alignment: .top) { Hairline(leading: 50) }
        .contentShape(.rect)
    }

    // MARK: Advanced (revealed by shaking)

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Advanced")
            Hairline()
            ForEach(ScaleTimeEpoch.allCases) { epoch in
                Button { scaleEpochRaw = epoch.rawValue } label: {
                    HStack(spacing: 14) {
                        ScaleGlyph().frame(width: 30).opacity(scaleEpochRaw == epoch.rawValue ? 1 : 0.45)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(epoch == .year2010 ? "BS 410 · 444 · 650" : "Other models")
                                .font(.system(.body, design: .rounded, weight: .semibold))
                            Text(epoch == .year2010 ? "scale clock counts from 2010" : "scale clock counts from 1970")
                                .font(.footnote.weight(.medium)).foregroundStyle(.ink2)
                        }
                        Spacer()
                        if scaleEpochRaw == epoch.rawValue {
                            CrayonTick().frame(width: 22)
                        }
                    }
                    .foregroundStyle(.ink)
                    .frame(minHeight: 62)
                    .overlay(alignment: .top) { Hairline(leading: 50) }
                    .contentShape(.rect)
                }
                .buttonStyle(PressStyle())
            }
            advancedButton("Import VitaDock CSV export…") { showImporter = true }
            if let importMessage {
                Text(importMessage).font(.footnote.weight(.medium)).foregroundStyle(.ink2).padding(.bottom, Space.s)
            }
            NavigationLink(value: "log") {
                row(leading: nil, title: "Bluetooth log", detail: nil, chevron: true, quiet: true)
            }
            .buttonStyle(PressStyle())
            #if DEBUG
            advancedButton("Insert sample data (debug)") { insertSampleData() }
            advancedButton("Delete sample data") { deleteSampleData() }
            advancedButton("Simulate a weigh-in (78,4 kg)") { scaleManager.simulateWeighIn(weightKg: 78.4) }
            advancedButton("Simulate unrecognised weigh-in (matches sample data)") {
                scaleManager.simulateUnrecognizedWeighIn(weightKg: 80.5)
            }
            advancedButton("Simulate unrecognised weigh-in (a child)") {
                scaleManager.simulateUnrecognizedWeighIn(weightKg: 23.8)
            }
            #endif
            Hairline()
            Text("Shake your phone to hide this section again.")
                .font(.footnote.weight(.medium)).foregroundStyle(.ink2).padding(.top, Space.m)
        }
    }

    private func advancedButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            row(leading: nil, title: title, detail: nil, chevron: false, tint: true)
        }
        .buttonStyle(PressStyle())
    }

    // MARK: - Debug

    #if DEBUG
    private func insertSampleData() {
        DemoData.insert(into: context)
        importMessage = "Inserted sample readings for P1 and P2."
    }

    /// Undo `insertSampleData` — including anything it pushed to Apple Health.
    private func deleteSampleData() {
        let descriptor = FetchDescriptor<ScaleMeasurement>(
            predicate: #Predicate { $0.source == "debug" })
        guard let rows = try? context.fetch(descriptor), !rows.isEmpty else {
            importMessage = "No sample data found."
            return
        }
        health.removeSamples(keys: rows.map(\.key))
        for row in rows { context.delete(row) }
        try? context.save()
        importMessage = "Deleted \(rows.count) sample readings (and removed them from Health)."
    }
    #endif
}

/// One person: their name, which scale profile they are, whether this phone
/// is theirs. Guests can be removed with their readings.
struct PersonView: View {
    let slot: Int

    @EnvironmentObject var health: HealthSync
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("myUserSlot") private var myUserSlot = 0
    @AppStorage(UserProfiles.defaultsKey) private var userNamesJSON = "{}"
    @State private var name = ""
    @State private var confirmRemove = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FeetGlyph(dotted: Household.isGuest(slot)).frame(width: 64).padding(.top, Space.l)
                TextField(Household.isGuest(slot) ? "Guest" : "P\(slot)", text: $name)
                    .font(.screenTitle)
                    .padding(.top, Space.l)
                    .padding(.bottom, 4)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.crayon).frame(height: 2) }
                Text(Household.isGuest(slot)
                     ? "A guest. The scale doesn't know them; the app recognises them by weight. Their readings never go to Apple Health."
                     : "Profile P\(slot) on the scale. Names are only used inside this app; the scale itself only knows P1–P8.")
                    .font(.body).foregroundStyle(.ink2).padding(.top, Space.m)

                VStack(spacing: 0) {
                    if !Household.isGuest(slot) {
                        HStack {
                            Text("This is my phone").font(.body)
                            Spacer()
                            if myUserSlot == slot {
                                CrayonTick().frame(width: 24)
                            } else {
                                Button("Make it mine") {
                                    myUserSlot = slot
                                    health.pushUnsynced(container: context.container)
                                }
                                .font(.system(.body, design: .rounded, weight: .semibold))
                                .foregroundStyle(.crayon)
                            }
                        }
                        .frame(minHeight: 56)
                        .overlay(alignment: .top) { Hairline() }
                        Text("Only this phone's person goes to its Apple Health. Everyone else's numbers stay on their own phone.")
                            .font(.footnote.weight(.medium)).foregroundStyle(.ink2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, Space.m)
                    } else {
                        Button("Remove \(name.isEmpty ? "this guest" : name) and their readings") { confirmRemove = true }
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .foregroundStyle(.ink)
                            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                            .overlay(alignment: .top) { Hairline() }
                    }
                    Hairline()
                }
                .padding(.top, Space.xl)
            }
            .padding(.horizontal, Space.margin)
        }
        .background(Color.ground)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { name = UserProfiles.decode(userNamesJSON)[slot] ?? "" }
        .onChange(of: name) {
            var names = UserProfiles.decode(userNamesJSON)
            names[slot] = name
            userNamesJSON = UserProfiles.encode(names)
        }
        .confirmationDialog("Remove this guest?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { removeGuest() }
        } message: {
            Text("Their readings are deleted from this phone. None of them are in Apple Health.")
        }
    }

    private func removeGuest() {
        let s = slot
        if let rows = try? context.fetch(FetchDescriptor<ScaleMeasurement>(predicate: #Predicate { $0.userId == s })) {
            rows.forEach(context.delete)
        }
        try? context.save()
        var names = UserProfiles.decode(userNamesJSON)
        names[slot] = nil
        userNamesJSON = UserProfiles.encode(names)
        dismiss()
    }
}

struct DebugLogView: View {
    @EnvironmentObject var scaleManager: ScaleManager

    var body: some View {
        List(scaleManager.log.reversed()) { line in
            VStack(alignment: .leading, spacing: 2) {
                Text(line.text)
                    .font(.system(.caption, design: .monospaced))
                Text(line.date.formatted(date: .omitted, time: .standard))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Bluetooth log")
        .toolbar {
            ShareLink(item: scaleManager.log.map { "\($0.date.formatted(date: .omitted, time: .standard)) \($0.text)" }
                .joined(separator: "\n"))
        }
    }
}
