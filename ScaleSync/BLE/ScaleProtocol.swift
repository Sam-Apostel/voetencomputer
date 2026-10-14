//
//  ScaleProtocol.swift
//  ScaleSync
//
//  Pure parsing logic for the Medisana BS4xx/BS6xx (Transtek) BLE protocol.
//  Protocol reference: https://github.com/oliexdev/openScale/wiki/Medisana-BS444
//  Confirmed on BS430/BS440/BS444/BS550; BS650 uses the same family protocol.
//

import Foundation

enum ScaleGATT {
    /// Custom weight service (16-bit alias 0x78B2)
    static let service = "78B2"
    /// Weight measurement (indication)
    static let weightChar = "8A21"
    /// Body composition "feature" measurement (indication)
    static let featureChar = "8A22"
    /// Person / user profile (indication)
    static let personChar = "8A82"
    /// Command characteristic (write) — used to push current time to the scale
    static let commandChar = "8A81"
}

/// Seconds between 1970-01-01 and 2010-01-01 (UTC). Several Medisana models
/// count time from 2010 instead of the unix epoch.
let medisanaEpoch2010: TimeInterval = 1_262_304_000

enum ScaleTimeEpoch: String, CaseIterable, Identifiable {
    case year2010
    case unix
    var id: String { rawValue }
    var label: String { self == .year2010 ? "2010 (BS410/444/650 default)" : "1970 (unix)" }
    var offset: TimeInterval { self == .year2010 ? medisanaEpoch2010 : 0 }
}

struct WeightPacket: Equatable {
    let weightKg: Double
    let date: Date
    let userId: Int?      // nil when scale reported 0xFF (no user matched)
}

struct CompositionPacket: Equatable {
    let date: Date
    let userId: Int?
    let kcal: Int
    let fatPercent: Double
    let waterPercent: Double
    let musclePercent: Double
    let boneKg: Double
}

enum ScaleProtocol {

    // MARK: - Helpers

    private static func le16(_ b: [UInt8], _ i: Int) -> UInt16 {
        UInt16(b[i]) | (UInt16(b[i + 1]) << 8)
    }

    private static func le32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | (UInt32(b[i + 1]) << 8) | (UInt32(b[i + 2]) << 16) | (UInt32(b[i + 3]) << 24)
    }

    /// Masked 12-bit little-endian value divided by 10 (fat/water/muscle/bone fields).
    private static func masked12(_ b: [UInt8], _ i: Int) -> Double {
        Double(le16(b, i) & 0x0FFF) / 10.0
    }

    /// The scale reports timestamps relative to either 2010-01-01 or the unix
    /// epoch depending on model/firmware. Try the preferred epoch first and
    /// fall back to whichever yields a plausible date.
    static func decodeDate(raw: UInt32, preferred: ScaleTimeEpoch, now: Date = Date()) -> Date {
        let candidates = [
            Date(timeIntervalSince1970: TimeInterval(raw) + preferred.offset),
            Date(timeIntervalSince1970: TimeInterval(raw) + (preferred == .year2010 ? 0 : medisanaEpoch2010)),
        ]
        let earliest = Date(timeIntervalSince1970: medisanaEpoch2010) // 2010-01-01
        let latest = now.addingTimeInterval(48 * 3600)
        for c in candidates where c >= earliest && c <= latest {
            return c
        }
        // Neither candidate is plausible (scale clock unset) — stamp with "now"
        // so the reading is not lost.
        return now
    }

    private static func userId(fromByte byte: UInt8) -> Int? {
        byte == 0xFF ? nil : Int(byte)
    }

    // MARK: - Packet parsers

    /// 0x8A21 — weight packet.
    /// Layout: [0] flags, [1-2] weight LE /100 kg, [5-8] timestamp LE, [13] user id.
    static func parseWeight(_ data: Data, epoch: ScaleTimeEpoch, now: Date = Date()) -> WeightPacket? {
        let b = [UInt8](data)
        guard b.count >= 14 else { return nil }
        let weightKg = Double(le16(b, 1)) / 100.0
        guard weightKg > 2, weightKg < 400 else { return nil } // discard nonsense frames
        let date = decodeDate(raw: le32(b, 5), preferred: epoch, now: now)
        return WeightPacket(weightKg: weightKg, date: date, userId: userId(fromByte: b[13]))
    }

    /// 0x8A22 — body composition packet.
    /// Layout: [0] flags, [1-4] timestamp LE, [5] user, [6-7] kcal LE,
    /// [8-9] fat, [10-11] water, [12-13] muscle, [14-15] bone (all 12-bit LE /10).
    static func parseComposition(_ data: Data, epoch: ScaleTimeEpoch, now: Date = Date()) -> CompositionPacket? {
        let b = [UInt8](data)
        guard b.count >= 16 else { return nil }
        let date = decodeDate(raw: le32(b, 1), preferred: epoch, now: now)
        let packet = CompositionPacket(
            date: date,
            userId: userId(fromByte: b[5]),
            kcal: Int(le16(b, 6) & 0x3FFF),
            fatPercent: masked12(b, 8),
            waterPercent: masked12(b, 10),
            musclePercent: masked12(b, 12),
            boneKg: masked12(b, 14)
        )
        // Sanity: percentages must be humanly possible, otherwise drop the frame.
        guard packet.fatPercent < 75, packet.waterPercent < 90, packet.musclePercent < 90 else { return nil }
        // An all-zero frame means the scale never ran the analysis — usually
        // because it matched no user profile. Storing zeros would render an
        // empty donut and push a bogus lean-body-mass (= full body weight) to
        // Apple Health, so treat it as "no composition" instead.
        guard packet.fatPercent > 0 || packet.waterPercent > 0 || packet.musclePercent > 0 else { return nil }
        return packet
    }

    /// Command payload that pushes the current time to the scale and triggers
    /// transmission of all stored measurements: 0x02 + UInt32 LE seconds.
    static func timeSyncCommand(epoch: ScaleTimeEpoch, now: Date = Date()) -> Data {
        var seconds = UInt32(max(0, now.timeIntervalSince1970 - epoch.offset))
        var data = Data([0x02])
        withUnsafeBytes(of: &seconds) { data.append(contentsOf: $0) } // little endian on all Apple platforms
        return data
    }

    /// Two measurements taken within this window are considered the same
    /// weigh-in when merging weight + composition packets.
    static let mergeWindow: TimeInterval = 60
}
