//
//  NowView.swift
//  ScaleSync
//
//  The receipt you glance at after stepping off: did it land, and how does it
//  compare. Feet, the weight, one sentence, the Apple Health tick, the
//  composition bar, and a line about the rest of the household.
//
//  The signature, "Footprints" (DIRECTION.md › The signature): when a new
//  reading arrives the feet press in, the digits hunt like the scale's own
//  LCD, the number locks and the tick draws itself.
//

import SwiftUI
import SwiftData

struct NowView: View {
    @EnvironmentObject var scaleManager: ScaleManager
    @EnvironmentObject var health: HealthSync
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("myUserSlot") private var myUserSlot = 0
    @AppStorage(UserProfiles.defaultsKey) private var userNamesJSON = "{}"
    @AppStorage(Household.showEveryoneKey) private var showEveryone = false
    @AppStorage(RecognitionHelp.timestampKey) private var recognitionHelpAt = 0.0
    @AppStorage(RecognitionHelp.slotKey) private var recognitionHelpSlot = 0
    @AppStorage("celebratedKey") private var celebratedKey = ""
    @AppStorage("whoAskedKey") private var whoAskedKey = ""

    @Query(sort: \ScaleMeasurement.date, order: .reverse)
    private var measurements: [ScaleMeasurement]

    @State private var beat: Beat = .settled
    @State private var whoFor: ScaleMeasurement?
    @State private var footHaptic = 0
    @State private var lockHaptic = 0
    @State private var successHaptic = 0
    @State private var openBody = false

    /// The moments of the signature.
    enum Beat: Equatable {
        case settled
        case pressing(left: Bool, right: Bool)
        case hunting(String)
        case locked(tick: Double)
    }

    // MARK: Data

    private func isMine(_ m: ScaleMeasurement) -> Bool {
        myUserSlot == 0 ? !Household.isGuest(m.userId) : m.userId == myUserSlot
    }

    private var mine: [ScaleMeasurement] { measurements.filter { isMine($0) && $0.weightKg > 0 } }
    private var latest: ScaleMeasurement? { mine.first }
    private var previous: ScaleMeasurement? { mine.dropFirst().first }

    /// Composition exists only when the scale recognised the person, so it
    /// can lag behind the latest weight. Show the most recent one there is.
    private var latestComposition: ScaleMeasurement? {
        measurements.first { isMine($0) && $0.fatPercent != nil && $0.weightKg > 0 }
    }

    /// The newest weigh-in from the last week that neither the scale nor the
    /// weight matching could assign to anyone.
    private var unassigned: ScaleMeasurement? {
        guard myUserSlot > 0 else { return nil }
        let cutoff = Date.now.addingTimeInterval(-7 * 24 * 3600)
        return measurements.first {
            $0.userId == 0 && $0.source == "scale" && $0.weightKg > 0 && $0.date > cutoff
        }
    }

    /// Everyone else who stepped on in the last day, newest first, once each.
    private var othersToday: [ScaleMeasurement] {
        guard myUserSlot > 0 else { return [] }
        let cutoff = Date.now.addingTimeInterval(-24 * 3600)
        var seen = Set<Int>()
        return measurements.filter { m in
            m.userId > 0 && m.userId != myUserSlot && m.weightKg > 0 && m.date > cutoff
                && seen.insert(m.userId).inserted
        }
    }

    private var showRecognitionHelp: Binding<Bool> {
        Binding(
            get: {
                recognitionHelpAt > 0
                    && Date.now.timeIntervalSince1970 - recognitionHelpAt < RecognitionHelp.window
            },
            set: { if !$0 { recognitionHelpAt = 0 } }
        )
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Group {
                if measurements.isEmpty {
                    FirstRunView()
                } else if let latest {
                    receipt(latest)
                } else {
                    nothingForYou
                }
            }
            .background(Color.ground)
            .toolbar { toolbar }
            .navigationDestination(for: ScaleMeasurement.self) { m in
                BodyView(measurement: m)
            }
            .navigationDestination(isPresented: $openBody) {
                if let comp = latestComposition { BodyView(measurement: comp) }
            }
            .sheet(item: $whoFor) { m in
                WhoSheet(measurement: m)
            }
            .sheet(isPresented: showRecognitionHelp) {
                RecognitionHelpSheet(
                    slot: recognitionHelpSlot,
                    name: recognitionHelpSlot == myUserSlot
                        ? nil
                        : UserProfiles.displayName(slot: recognitionHelpSlot, json: userNamesJSON))
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: footHaptic)
        .sensoryFeedback(.selection, trigger: lockHaptic)
        .sensoryFeedback(.success, trigger: successHaptic)
        .onAppear {
            celebrateIfNew()
            #if DEBUG
            if DemoData.has("-body") { openBody = true }
            #endif
        }
        .onChange(of: latest?.key) { celebrateIfNew() }
        .onChange(of: unassigned?.key, initial: true) { _, key in
            // Ask once per unrecognised weigh-in; the inline row asks again.
            if let key, key != whoAskedKey, let m = unassigned {
                whoAskedKey = key
                whoFor = m
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if myUserSlot > 0 {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: 8) {
                    Text(String(UserProfiles.displayName(slot: myUserSlot, json: userNamesJSON).prefix(1)))
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(.onCrayon)
                        .frame(width: 30, height: 30)
                        .background(Color.crayon, in: .circle)
                    Text(UserProfiles.displayName(slot: myUserSlot, json: userNamesJSON))
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .fixedSize()
                }
                .padding(.trailing, 8)
                .fixedSize()
                .accessibilityElement(children: .combine)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                scaleManager.syncNow()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: scaleManager.status == .bluetoothOff
                          ? "antenna.radiowaves.left.and.right.slash" : "arrow.triangle.2.circlepath")
                        .foregroundStyle(.crayon)
                        .symbolEffect(.rotate, isActive: scaleManager.status.isBusy)
                    Text(statusText)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                }
                .padding(.horizontal, 4)
            }
            .accessibilityHint("Looks for the scale now")
        }
    }

    /// "Synced 07:12": the newest reading's time once nothing is happening.
    private var statusText: String {
        switch scaleManager.status {
        case .idle, .done:
            let last = [scaleManager.lastSeen.values.max(), latest?.date].compactMap { $0 }.max()
            return last.map { "Synced \($0.formatted(date: .omitted, time: .shortened))" } ?? scaleManager.status.label
        default:
            return scaleManager.status.label
        }
    }

    // MARK: The receipt

    private func receipt(_ m: ScaleMeasurement) -> some View {
        GeometryReader { geo in
            let compact = geo.size.height < 640
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !compact {
                        Text(m.date.formatted(.dateTime.weekday(.wide).hour().minute()))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.ink2)
                            .padding(.top, Space.xs)
                    }
                    feet
                        .frame(height: compact ? 120 : 196)
                        .padding(.leading, compact ? 104 : 86)
                        .padding(.top, compact ? Space.s : Space.xxl)
                        .padding(.bottom, compact ? Space.m : Space.l)
                    hero(m)
                    if let previous {
                        Text(Say.change(from: previous, to: m))
                            .font(.say)
                            .padding(.top, Space.m)
                            .opacity(beat == .settled || isLocked ? 1 : 0)
                    }
                    healthMark(m)
                        .padding(.top, Space.s)
                    if let comp = latestComposition, let c = Composition(comp) {
                        compositionLink(comp, c, latest: m)
                            .padding(.top, Space.xl + 4)
                            .opacity(beat == .settled || isLocked ? 1 : 0)
                    }
                    if let u = unassigned {
                        unassignedRow(u).padding(.top, Space.xl)
                    }
                    if !compact {
                        household.padding(.top, Space.xl)
                    }
                }
                .padding(.horizontal, Space.margin)
                .padding(.bottom, Space.xl)
                .frame(minHeight: geo.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var isLocked: Bool {
        if case .locked = beat { return true }
        return false
    }

    @ViewBuilder private var feet: some View {
        switch beat {
        case .pressing(let left, let right):
            FeetPair(leftFilled: left, rightFilled: right, rightPressing: !right)
        default:
            // Listening: while the scale is talking, the feet wait as dots.
            FeetPair(dotted: scaleManager.status.isBusy)
        }
    }

    private func hero(_ m: ScaleMeasurement) -> some View {
        let parts = Say.weightParts(m.weightKg)
        return HStack(alignment: .lastTextBaseline, spacing: 6) {
            switch beat {
            case .hunting(let digits):
                SevenSegment(text: digits, height: 84)
                    .padding(.bottom, 4)
            case .pressing:
                Text("––,–").font(.hero).tracking(-4).foregroundStyle(.ink3)
            default:
                Text(parts.number)
                    .font(.hero)
                    .tracking(-4)
                    .contentTransition(.numericText())
            }
            Text(parts.unit)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.ink2)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(height: 94, alignment: .bottomLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Units.weightString(m.weightKg))
    }

    @ViewBuilder private func healthMark(_ m: ScaleMeasurement) -> some View {
        let tick: Double = {
            switch beat {
            case .locked(let t): return t
            case .settled: return 1
            default: return 0
            }
        }()
        if m.healthSynced {
            HStack(spacing: 6) {
                CrayonTick(progress: tick).frame(width: 22, height: 22)
                Text("In Apple Health")
            }
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(.crayon)
            .opacity(tick > 0 ? 1 : 0)
        } else if !health.authorized {
            Text("Not in Apple Health: allow it in Household.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.ink2)
        } else {
            Text("On its way to Apple Health")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.ink2)
        }
    }

    private func compositionLink(_ comp: ScaleMeasurement, _ c: Composition, latest: ScaleMeasurement) -> some View {
        NavigationLink(value: comp) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(comp.key == latest.key
                         ? "Body composition"
                         : "Composition from \(Say.dayReference(comp.date, relativeTo: .now)), \(comp.date.formatted(date: .omitted, time: .shortened))")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.ink2)
                    Spacer()
                    HStack(spacing: 2) {
                        Text("Body")
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.ink)
                }
                CompositionBar(composition: c)
                CompositionLegend(composition: c)
                    .foregroundStyle(.ink)
            }
            .contentShape(.rect)
        }
        .buttonStyle(PressStyle())
    }

    private func unassignedRow(_ u: ScaleMeasurement) -> some View {
        Button {
            whoFor = u
        } label: {
            HStack(spacing: Space.m) {
                FeetGlyph(dotted: true).frame(width: 30)
                Text("Someone weighed \(Units.weightString(u.weightKg)) \(Say.dayReference(u.date, relativeTo: .now)). Who was that?")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.ink3)
            }
            .padding(.vertical, Space.m)
            .overlay(alignment: .top) { Hairline() }
            .overlay(alignment: .bottom) { Hairline() }
        }
        .buttonStyle(PressStyle())
    }

    @ViewBuilder private var household: some View {
        let others = othersToday
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: Space.s) {
                ForEach(others) { m in
                    let name = UserProfiles.displayName(slot: m.userId, json: userNamesJSON)
                    let time = m.date.formatted(date: .omitted, time: .shortened)
                    HStack(alignment: .top, spacing: 10) {
                        FeetGlyph(dotted: Household.isGuest(m.userId)).frame(width: 26)
                        Text(showEveryone
                             ? "\(name) stepped on at \(time): \(Units.weightString(m.weightKg))."
                             : "\(name) stepped on at \(time). Numbers stay on \(name)'s phone.")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.ink2)
                    }
                }
            }
        }
    }

    private var nothingForYou: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            FeetPair(dotted: true).frame(height: 160).padding(.leading, 86)
            Text("Nothing for \(UserProfiles.displayName(slot: myUserSlot, json: userNamesJSON)) yet.")
                .font(.screenTitle)
                .padding(.top, Space.xl)
            Text("\(measurements.count) reading\(measurements.count == 1 ? "" : "s") are stored, none of them yours. Stay on the scale until it shows your P-number, or pick who this phone belongs to in Household.")
                .font(.body)
                .foregroundStyle(.ink2)
            Spacer()
        }
        .padding(.horizontal, Space.margin)
        .padding(.top, Space.xl)
    }

    // MARK: Footprints

    private func celebrateIfNew() {
        guard let m = latest, m.key != celebratedKey else { return }
        celebratedKey = m.key
        // Only fresh readings get the moment; opening the app on an old one doesn't.
        guard m.date > Date.now.addingTimeInterval(-30 * 60) else { return }
        Task { await footprints(final: Say.weightParts(m.weightKg).number) }
    }

    private func footprints(final: String) async {
        if reduceMotion {
            beat = .settled
            withAnimation(.easeInOut(duration: 0.2)) { beat = .locked(tick: 1) }
            successHaptic += 1
            try? await Task.sleep(for: .milliseconds(200))
            beat = .settled
            return
        }
        var slow = 1
        #if DEBUG
        if DemoData.has("-footprints") { slow = 10 }
        #endif
        func wait(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms * slow)) }
        beat = .pressing(left: false, right: false)
        await wait(80)
        withAnimation(.smooth(duration: 0.26)) { beat = .pressing(left: true, right: false) }
        footHaptic += 1
        await wait(80)
        withAnimation(.smooth(duration: 0.26)) { beat = .pressing(left: true, right: true) }
        footHaptic += 1
        await wait(40)
        for digits in Self.hunt(toward: final) {
            beat = .hunting(digits)
            await wait(150)
        }
        withAnimation(.snappy) { beat = .locked(tick: 0) }
        lockHaptic += 1
        await wait(50)
        withAnimation(.easeOut(duration: 0.22)) { beat = .locked(tick: 1) }
        successHaptic += 1
        await wait(260)
        beat = .settled
    }

    /// Three near misses before the real number, like the scale's display.
    static func hunt(toward final: String) -> [String] {
        let value = Double(final.replacingOccurrences(of: ",", with: ".")) ?? 0
        let separator = final.contains(",") ? "," : "."
        return [-0.6, 0.5, -0.2].map {
            String(format: "%.1f", value + $0).replacingOccurrences(of: ".", with: separator)
        }
    }
}
