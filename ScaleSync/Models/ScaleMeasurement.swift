//
//  ScaleMeasurement.swift
//  ScaleSync
//

import Foundation
import SwiftData

@Model
final class ScaleMeasurement {
    /// Stable identity: rounded timestamp + user slot. Used for deduplication
    /// (the scale re-sends stored measurements on every connection) and as the
    /// HealthKit sync identifier.
    @Attribute(.unique) var key: String

    var date: Date
    var userId: Int          // 0 = unknown/unassigned slot
    var weightKg: Double
    var fatPercent: Double?
    var waterPercent: Double?
    var musclePercent: Double?
    var boneKg: Double?
    var kcal: Int?
    var source: String       // "scale" or "csv"
    var healthSynced: Bool

    init(date: Date,
         userId: Int,
         weightKg: Double,
         fatPercent: Double? = nil,
         waterPercent: Double? = nil,
         musclePercent: Double? = nil,
         boneKg: Double? = nil,
         kcal: Int? = nil,
         source: String = "scale",
         healthSynced: Bool = false) {
        self.key = Self.makeKey(date: date, userId: userId)
        self.date = date
        self.userId = userId
        self.weightKg = weightKg
        self.fatPercent = fatPercent
        self.waterPercent = waterPercent
        self.musclePercent = musclePercent
        self.boneKg = boneKg
        self.kcal = kcal
        self.source = source
        self.healthSynced = healthSynced
    }

    static func makeKey(date: Date, userId: Int) -> String {
        // Round to the minute so weight/composition packets and repeated
        // transmissions of the same weigh-in collapse onto one key.
        let minute = Int(date.timeIntervalSince1970 / 60)
        return "\(minute)-u\(userId)"
    }

    /// Lean body mass derived from body fat percentage.
    var leanBodyMassKg: Double? {
        guard let fat = fatPercent else { return nil }
        return weightKg * (1.0 - fat / 100.0)
    }

    func bmi(heightCm: Double) -> Double? {
        guard heightCm > 0 else { return nil }
        let m = heightCm / 100.0
        return weightKg / (m * m)
    }
}
