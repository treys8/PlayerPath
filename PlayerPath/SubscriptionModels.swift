//
//  SubscriptionModels.swift
//  PlayerPath
//
//  Subscription tier definitions and product ID registry.
//

import SwiftUI

// MARK: - Subscription Tier

/// The user's current subscription level.
/// Comparable so feature gates can write `tier >= .plus`.
enum SubscriptionTier: String, Comparable, CaseIterable {
    case free = "free"
    case plus = "plus"
    case pro  = "pro"

    // MARK: Comparable ordering: free < plus < pro

    private var rank: Int {
        switch self {
        case .free: return 0
        case .plus: return 1
        case .pro:  return 2
        }
    }

    static func < (lhs: SubscriptionTier, rhs: SubscriptionTier) -> Bool {
        lhs.rank < rhs.rank
    }

    // MARK: - Display

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .plus: return "Plus"
        case .pro:  return "Pro"
        }
    }

    // MARK: - Limits

    /// Maximum number of athletes this tier allows
    var athleteLimit: Int {
        switch self {
        case .free: return 1
        case .plus: return 3
        case .pro:  return 5
        }
    }

    /// Cloud storage limit in GB
    var storageLimitGB: Int {
        switch self {
        case .free: return 2
        case .plus: return 25
        case .pro:  return 100
        }
    }

    // MARK: - Feature Flags

    var hasAutoHighlights: Bool   { self >= .plus }
    var hasStatsExport: Bool      { self >= .plus }
    var hasSeasonComparison: Bool { self >= .plus }

    // MARK: - Product ID Sets

    static let plusProductIDs: Set<String> = [
        TierSubscriptionProduct.plusMonthly.rawValue,
        TierSubscriptionProduct.plusAnnual.rawValue
    ]

    static let proProductIDs: Set<String> = [
        TierSubscriptionProduct.proMonthly.rawValue,
        TierSubscriptionProduct.proAnnual.rawValue
    ]

}

// MARK: - Coach Subscription Tier

/// The coach's current subscription level.
/// Comparable so feature gates can write `coachTier >= .instructor`.
enum CoachSubscriptionTier: String, Comparable, CaseIterable {
    case free          = "coach_free"
    case instructor    = "coach_instructor"
    case proInstructor = "coach_pro_instructor"
    case academy       = "coach_academy"

    private var rank: Int {
        switch self {
        case .free:          return 0
        case .instructor:    return 1
        case .proInstructor: return 2
        case .academy:       return 3
        }
    }

    static func < (lhs: CoachSubscriptionTier, rhs: CoachSubscriptionTier) -> Bool {
        lhs.rank < rhs.rank
    }

    var displayName: String {
        switch self {
        case .free:          return "Free"
        case .instructor:    return "Instructor"
        case .proInstructor: return "Pro Instructor"
        case .academy:       return "Academy"
        }
    }

    /// Maximum number of athletes this tier allows (Int.max = unlimited for Academy)
    var athleteLimit: Int {
        switch self {
        case .free:          return 2
        case .instructor:    return 10
        case .proInstructor: return 30
        case .academy:       return Int.max
        }
    }

    /// Canonical display color for this tier.
    /// Free = neutral, Instructor = brand primary, Pro Instructor = premium, Academy = enterprise.
    var color: Color {
        switch self {
        case .free:          return .secondary
        case .instructor:    return .brandNavy
        case .proInstructor: return .brandGold
        case .academy:       return .purple
        }
    }

    static let instructorProductIDs: Set<String> = [
        CoachSubscriptionProduct.instructorMonthly.rawValue,
        CoachSubscriptionProduct.instructorAnnual.rawValue
    ]

    static let proInstructorProductIDs: Set<String> = [
        CoachSubscriptionProduct.proInstructorMonthly.rawValue,
        CoachSubscriptionProduct.proInstructorAnnual.rawValue
    ]
}

// MARK: - Coach Subscription Products

/// All 4 coach StoreKit product identifiers. Must match App Store Connect configuration.
/// Academy is manually granted via Firestore — no StoreKit product exists for it.
enum CoachSubscriptionProduct: String, CaseIterable {
    case instructorMonthly    = "com.playerpath.coach.instructor.monthly"
    case instructorAnnual     = "com.playerpath.coach.instructor.annual"
    case proInstructorMonthly = "com.playerpath.coach.proinstructor.monthly"
    case proInstructorAnnual  = "com.playerpath.coach.proinstructor.annual"

    var displayName: String {
        switch self {
        case .instructorMonthly:    return "Instructor Monthly"
        case .instructorAnnual:     return "Instructor Annual"
        case .proInstructorMonthly: return "Pro Instructor Monthly"
        case .proInstructorAnnual:  return "Pro Instructor Annual"
        }
    }

    var isAnnual: Bool {
        switch self {
        case .instructorAnnual, .proInstructorAnnual: return true
        default: return false
        }
    }
}

// MARK: - Tier Subscription Products

/// All 4 StoreKit product identifiers. Must match App Store Connect configuration.
enum TierSubscriptionProduct: String, CaseIterable {
    case plusMonthly = "com.playerpath.plus.monthly"
    case plusAnnual  = "com.playerpath.plus.annual"
    case proMonthly  = "com.playerpath.pro.monthly"
    case proAnnual   = "com.playerpath.pro.annual"

    var displayName: String {
        switch self {
        case .plusMonthly: return "Plus Monthly"
        case .plusAnnual:  return "Plus Annual"
        case .proMonthly:  return "Pro Monthly"
        case .proAnnual:   return "Pro Annual"
        }
    }

    var isAnnual: Bool {
        switch self {
        case .plusAnnual, .proAnnual: return true
        default: return false
        }
    }
}
