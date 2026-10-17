//
//  ProfileMatcher.swift
//  ScaleSync
//
//  The scale assigns each weigh-in to a user profile by comparing it with that
//  profile's previous weight. When that fails it reports "no user", and the
//  weigh-in would otherwise belong to nobody. This repeats the comparison with
//  the history the app has stored, so the weight still lands in the right place.
//

import Foundation

enum ProfileMatcher {

    /// How far a weigh-in may be from a profile's last weight and still count
    /// as that person. Day-to-day fluctuation stays well inside this.
    static let toleranceKg = 3.0

    /// The profile whose most recent weight is within tolerance — but only if
    /// exactly one profile qualifies. Two people of similar weight, or no
    /// history at all, return nil so the user can decide instead.
    static func match(weightKg: Double, lastWeights: [Int: Double]) -> Int? {
        let candidates = lastWeights.filter { abs($0.value - weightKg) <= toleranceKg }
        return candidates.count == 1 ? candidates.first?.key : nil
    }
}
