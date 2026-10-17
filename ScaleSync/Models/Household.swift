//
//  Household.swift
//  ScaleSync
//
//  Who stands on the scale. Slots 1–8 are the scale's own profiles (P1–P8).
//  Guests (a visiting nephew) get slots from 101 up: the scale never knows
//  them, they never go to Apple Health, and they keep their readings apart
//  from everyone else's. Names for both live in UserProfiles' JSON.
//

import Foundation

enum Household {
    static let firstGuestSlot = 101

    static func isGuest(_ slot: Int) -> Bool { slot >= firstGuestSlot }

    /// Whether this phone shows other people's numbers (Household switch).
    /// Off by default: everyone's numbers belong on their own phone.
    static let showEveryoneKey = "showEveryonesNumbers"

    static func nextGuestSlot(json: String) -> Int {
        let used = UserProfiles.decode(json).keys.filter(isGuest)
        return (used.max() ?? firstGuestSlot - 1) + 1
    }

    /// Add a guest with this name and return the slot.
    static func addGuest(named name: String, json: inout String) -> Int {
        let slot = nextGuestSlot(json: json)
        var names = UserProfiles.decode(json)
        names[slot] = name
        json = UserProfiles.encode(names)
        return slot
    }
}

/// Phrases the app says instead of showing arrows and colours
/// (DIRECTION.md decision 6: weight change is never coloured).
enum Say {

    /// "Half a kilo lighter than Thursday." / "Same as yesterday."
    static func change(from previous: ScaleMeasurement, to current: ScaleMeasurement,
                       now: Date = .now) -> String {
        let delta = current.weightKg - previous.weightKg
        let when = dayReference(previous.date, relativeTo: current.date)
        if abs(delta) < 0.05 { return "Same as \(when)." }
        let direction = delta < 0 ? "lighter" : "heavier"
        return "\(amount(abs(delta)).capitalizedFirst) \(direction) than \(when)."
    }

    /// "half a kilo", "a kilo", "0,3 kg", "1,4 kg", or pounds.
    static func amount(_ kg: Double) -> String {
        if Units.usesImperial {
            return Units.weightString(kg)
        }
        let rounded = (kg * 10).rounded() / 10
        switch rounded {
        case 0.5: return "half a kilo"
        case 1.0: return "a kilo"
        default: return Units.weightString(rounded)
        }
    }

    /// "earlier today", "yesterday", "Thursday", "12 October".
    static func dayReference(_ date: Date, relativeTo reference: Date) -> String {
        let cal = Calendar.current
        if cal.isDate(date, inSameDayAs: reference) { return "earlier today" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: reference)).day ?? 99
        if days == 1 { return "yesterday" }
        if days < 7 { return date.formatted(.dateTime.weekday(.wide)) }
        return date.formatted(.dateTime.day().month(.wide))
    }

    /// "the end of July", "mid-July", "the start of July".
    static func pointInMonth(_ date: Date) -> String {
        let day = Calendar.current.component(.day, from: date)
        let month = date.formatted(.dateTime.month(.wide))
        switch day {
        case ...10: return "the start of \(month)"
        case ...20: return "mid-\(month)"
        default: return "the end of \(month)"
        }
    }

    /// The number and the unit apart, so the unit can be set small.
    static func weightParts(_ kg: Double) -> (number: String, unit: String) {
        (Units.kgToDisplay(kg).formatted(.number.precision(.fractionLength(1))), Units.weightUnit)
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
