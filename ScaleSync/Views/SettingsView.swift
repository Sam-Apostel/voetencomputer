//
//  SettingsView.swift
//  ScaleSync
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var scaleManager: ScaleManager
    @EnvironmentObject var health: HealthSync
    @Environment(\.modelContext) private var context

    @AppStorage("myUserSlot") private var myUserSlot = 0
    @AppStorage("heightCm") private var heightCm = 0.0
    @AppStorage("scaleEpoch") private var scaleEpochRaw = ScaleTimeEpoch.year2010.rawValue
    @AppStorage(UserProfiles.defaultsKey) private var userNamesJSON = "{}"

    @State private var showImporter = false
    @State private var importMessage: String?
    @State private var confirmForget = false
    @FocusState private var heightFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Apple Health") {
                    Button(health.authorized ? "Health access granted" : "Grant Health access") {
                        health.requestAuthorization()
                    }
                    .disabled(health.authorized)
                    Button("Re-sync all measurements to Health") {
                        health.resyncAll(container: context.container)
                    }
                }

                Section {
                    Picker("My profile", selection: $myUserSlot) {
                        Text("All users").tag(0)
                        ForEach(1...8, id: \.self) { slot in
                            Text(UserProfiles.displayName(slot: slot, json: userNamesJSON)).tag(slot)
                        }
                    }
                    NavigationLink("Profile names") {
                        ProfileNamesView(userNamesJSON: $userNamesJSON)
                    }
                    HStack {
                        Text("Height (cm)")
                        Spacer()
                        // Optional binding so an unset height (0) shows the
                        // placeholder instead of a literal "0" that ends up
                        // glued onto whatever the user types.
                        TextField("e.g. 180",
                                  value: Binding<Double?>(
                                    get: { heightCm > 0 ? heightCm : nil },
                                    set: { heightCm = $0 ?? 0 }
                                  ),
                                  format: .number.grouping(.never))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                            .focused($heightFocused)
                    }
                } header: {
                    Text("Me")
                } footer: {
                    Text(myUserSlot == 0
                         ? "Pick your profile so only your own measurements are written to Apple Health."
                         : "Only measurements from “\(UserProfiles.displayName(slot: myUserSlot, json: userNamesJSON))” are written to Apple Health. Weights display in \(Units.usesImperial ? "pounds" : "kilograms"), following your device's region settings.")
                }
                .onChange(of: heightCm) {
                    // Height affects BMI — re-push so Health gets BMI samples.
                    health.resyncAll(container: context.container)
                }

                Section("Scale") {
                    pairedScaleRow
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Scale clock epoch")
                        HStack(spacing: 12) {
                            epochCard(.year2010,
                                      style: .glass2010,
                                      title: "BS410 · 444 · 650",
                                      subtitle: "clock counts from 2010")
                            epochCard(.unix,
                                      style: .classic1970,
                                      title: "Other models",
                                      subtitle: "clock counts from 1970")
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("History") {
                    Button("Import VitaDock CSV export…") { showImporter = true }
                    if let msg = importMessage {
                        Text(msg).font(.footnote).foregroundStyle(.secondary)
                    }
                    NavigationLink("Bluetooth debug log") { DebugLogView() }
                    #if DEBUG
                    Button("Insert sample data (debug)") { insertSampleData() }
                    Button("Delete sample data", role: .destructive) { deleteSampleData() }
                    #endif
                }
            }
            .navigationTitle("Settings")
            .scrollDismissesKeyboard(.interactively)
            // Note: a ToolbarItem(placement: .keyboard) "Done" button does not
            // render inside a TabView (long-standing SwiftUI issue), so the
            // decimal pad is dismissed by tapping anywhere else or scrolling.
            // The gesture mask keeps the tap recognizer fully disabled while
            // the field is not focused — otherwise it swallows taps meant for
            // the Form's pickers and buttons.
            .simultaneousGesture(
                TapGesture().onEnded { heightFocused = false },
                including: heightFocused ? .all : .subviews
            )
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

    // MARK: - Scale section pieces

    private var pairedScaleRow: some View {
        let paired = scaleManager.scaleName != nil
        return HStack(spacing: 14) {
            ScaleGlyph(style: scaleEpochRaw == ScaleTimeEpoch.year2010.rawValue ? .glass2010 : .classic1970,
                       size: 56, dimmed: !paired)
                .overlay(alignment: .topTrailing) {
                    if confirmForget {
                        Button {
                            withAnimation { confirmForget = false }
                            scaleManager.forgetScale()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .red)
                        }
                        .buttonStyle(.plain)
                        .offset(x: 9, y: -9)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(scaleManager.scaleName ?? "No scale paired")
                    .foregroundStyle(paired ? .primary : .secondary)
                Text(paired
                     ? (confirmForget ? "Tap ✕ to forget this scale" : "Tap to forget")
                     : "Step on your scale to pair")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard paired else { return }
            withAnimation(.snappy) { confirmForget.toggle() }
        }
    }

    private func epochCard(_ epoch: ScaleTimeEpoch, style: ScaleGlyph.Style,
                           title: String, subtitle: String) -> some View {
        let selected = scaleEpochRaw == epoch.rawValue
        return Button {
            scaleEpochRaw = epoch.rawValue
        } label: {
            VStack(spacing: 6) {
                ScaleGlyph(style: style, size: 64)
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selected ? Color.accentColor : Color(.systemGray4),
                                  lineWidth: selected ? 2 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Debug

    #if DEBUG
    private func insertSampleData() {
        let cal = Calendar.current
        for day in 0..<30 {
            guard let date = cal.date(byAdding: .day, value: -day, to: .now) else { continue }
            let drift = Double(day)
            let m = ScaleMeasurement(
                date: date, userId: 1,
                weightKg: 80.0 + drift * 0.05 + sin(drift) * 0.4,
                fatPercent: 20.0 + sin(drift * 0.7) * 0.8,
                waterPercent: 55.0 + cos(drift * 0.5) * 0.6,
                musclePercent: 40.0 + sin(drift * 0.3) * 0.5,
                boneKg: 3.2, kcal: 2200,
                source: "debug")
            context.insert(m)
        }
        try? context.save()
        importMessage = "Inserted 30 sample measurements."
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
        importMessage = "Deleted \(rows.count) sample measurements (and removed them from Health)."
    }
    #endif
}

/// Editor for the scale's eight user-slot names.
struct ProfileNamesView: View {
    @Binding var userNamesJSON: String
    @State private var names: [Int: String] = [:]

    var body: some View {
        Form {
            Section {
                ForEach(1...8, id: \.self) { slot in
                    TextField("User \(slot)", text: Binding(
                        get: { names[slot] ?? "" },
                        set: { names[slot] = $0 }
                    ))
                }
            } footer: {
                Text("Names are only used inside this app. The scale itself only knows slot numbers.")
            }
        }
        .navigationTitle("Profile names")
        .onAppear { names = UserProfiles.decode(userNamesJSON) }
        .onDisappear { userNamesJSON = UserProfiles.encode(names) }
        .onChange(of: names) { userNamesJSON = UserProfiles.encode(names) }
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
        .navigationTitle("BLE log")
        .toolbar {
            ShareLink(item: scaleManager.log.map { "\($0.date.formatted(date: .omitted, time: .standard)) \($0.text)" }
                .joined(separator: "\n"))
        }
    }
}
