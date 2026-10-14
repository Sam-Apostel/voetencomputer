//
//  Preferences.swift
//  ScaleSync
//

import Foundation

/// Weight formatting follows the device's measurement system — no manual
/// metric/imperial toggle.
enum Units {
    static var usesImperial: Bool {
        Locale.current.measurementSystem != .metric
    }

    static func kgToDisplay(_ kg: Double) -> Double {
        usesImperial ? kg * 2.20462 : kg
    }

    static var weightUnit: String {
        usesImperial ? "lb" : "kg"
    }

    static func weightString(_ kg: Double) -> String {
        kgToDisplay(kg).formatted(.number.precision(.fractionLength(1))) + " " + weightUnit
    }
}

/// Custom names for the scale's user slots (1–8), stored as a JSON dictionary
/// in UserDefaults under a single key so views can observe it via @AppStorage.
enum UserProfiles {
    static let defaultsKey = "userNames"

    static func decode(_ json: String) -> [Int: String] {
        guard let data = json.data(using: .utf8),
              let raw = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return raw.reduce(into: [:]) { dict, entry in
            if let slot = Int(entry.key) { dict[slot] = entry.value }
        }
    }

    static func encode(_ names: [Int: String]) -> String {
        let raw = names.reduce(into: [String: String]()) { dict, entry in
            let trimmed = entry.value.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { dict[String(entry.key)] = trimmed }
        }
        guard let data = try? JSONEncoder().encode(raw) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Display name for a slot. Slot 0 is the "no profile matched" bucket.
    static func displayName(slot: Int, json: String? = nil) -> String {
        if slot == 0 { return "All users" }
        let names = decode(json ?? UserDefaults.standard.string(forKey: defaultsKey) ?? "{}")
        return names[slot] ?? "User \(slot)"
    }
}
