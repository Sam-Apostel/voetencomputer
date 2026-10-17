//
//  FirstRunView.swift
//  ScaleSync
//
//  Nothing stored yet: the scale with two dotted feet on it, one sentence,
//  the two things that must be true, and what the app is listening for.
//

import SwiftUI

struct FirstRunView: View {
    @EnvironmentObject var scaleManager: ScaleManager
    @EnvironmentObject var health: HealthSync
    @State private var showHow = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScaleWithFeet()
                .frame(maxWidth: 300, maxHeight: 330)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, Space.s)

            Text("Step on the scale.").font(.screenTitle).tracking(-0.6)
            Text("Barefoot, phone nearby. It pairs by itself and brings every reading it has kept.")
                .font(.body)
                .foregroundStyle(.ink2)
                .padding(.top, 10)

            VStack(spacing: 0) {
                HStack(spacing: Space.m) {
                    ScaleGlyph().frame(width: 28)
                    Text("Scale in Bluetooth mode").font(.body)
                    Spacer()
                    Button("How?") { showHow = true }
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.crayon)
                        .frame(minHeight: 44)
                }
                .frame(minHeight: 56)
                .overlay(alignment: .top) { Hairline() }
                HStack(spacing: Space.m) {
                    CrayonTick().frame(width: 28).opacity(health.authorized ? 1 : 0.35)
                    Text("Apple Health").font(.body)
                    Spacer()
                    if health.authorized {
                        Text("Allowed").font(.subheadline.weight(.semibold)).foregroundStyle(.crayon)
                    } else {
                        Button("Allow") { Task { await health.requestAuthorization() } }
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(.onCrayon)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 36)
                            .background(Color.crayon, in: .capsule)
                            .frame(minHeight: 44)
                    }
                }
                .frame(minHeight: 56)
                .overlay(alignment: .top) { Hairline() }
                .overlay(alignment: .bottom) { Hairline() }
            }
            .padding(.top, Space.xl)

            HStack(spacing: 10) {
                Circle().fill(Color.crayon).frame(width: 10, height: 10)
                    .background(Circle().fill(Color.wash).frame(width: 20, height: 20))
                Text(listening)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.ink2)
            }
            .padding(.top, Space.xl)
            .padding(.bottom, Space.xl)
        }
        .padding(.horizontal, Space.margin)
        .sheet(isPresented: $showHow) { howSheet }
    }

    private var listening: String {
        switch scaleManager.status {
        case .bluetoothOff: return "Bluetooth is off. Turn it on in Control Center."
        case .connecting, .syncing: return "Found it. Bringing the readings over…"
        default: return "Listening for a BS 410, 444 or 650, or a DIY scale"
        }
    }

    private var howSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    Text("The BS 650 talks either to Medisana's cloud over Wi-Fi or to a phone over Bluetooth. This app needs Bluetooth.")
                    Text("The connection mode is chosen during the scale's own setup; see its manual. If the VitaDock app is installed, close it fully: it can grab the scale first.")
                    Text("Then step on barefoot with this phone nearby. Every reading the scale has kept comes over.")
                }
                .font(.body)
                .padding(.horizontal, Space.margin)
                .padding(.vertical, Space.l)
            }
            .background(Color.raised)
            .navigationTitle("Bluetooth mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { showHow = false } }
            }
        }
        .presentationDetents([.medium])
    }
}
