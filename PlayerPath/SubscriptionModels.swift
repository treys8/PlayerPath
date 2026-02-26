//
//  SubscriptionModels.swift
//  PlayerPath
//
//  Subscription tier definitions and product ID registry.
//

import Foundation

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
        case .plus: return 1
        case .pro:  return 5
        }
    }

    /// Cloud storage limit in GB
    var storageLimitGB: Int {
        switch self {
        case .free: return 1
        case .plus: return 5
        case .pro:  return 15
        }
    }

    // MARK: - Feature Flags

    var hasAdvancedStats: Bool    { self >= .plus }
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

    static let coachingProductIDs: Set<String> = [
        TierSubscriptionProduct.coachingMonthly.rawValue,
        TierSubscriptionProduct.coachingAnnual.rawValue
    ]
}

// MARK: - Tier Subscription Products

/// All 6 StoreKit product identifiers. Must match App Store Connect configuration.
enum TierSubscriptionProduct: String, CaseIterable {
    case plusMonthly     = "com.playerpath.plus.monthly"
    case plusAnnual      = "com.playerpath.plus.annual"
    case proMonthly      = "com.playerpath.pro.monthly"
    case proAnnual       = "com.playerpath.pro.annual"
    case coachingMonthly = "com.playerpath.coaching.monthly"
    case coachingAnnual  = "com.playerpath.coaching.annual"

    var displayName: String {
        switch self {
        case .plusMonthly:     return "Plus Monthly"
        case .plusAnnual:      return "Plus Annual"
        case .proMonthly:      return "Pro Monthly"
        case .proAnnual:       return "Pro Annual"
        case .coachingMonthly: return "Coaching Monthly"
        case .coachingAnnual:  return "Coaching Annual"
        }
    }

    var isAnnual: Bool {
        switch self {
        case .plusAnnual, .proAnnual, .coachingAnnual: return true
        default: return false
        }
    }
}
