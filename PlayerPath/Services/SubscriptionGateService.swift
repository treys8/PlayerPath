//
//  SubscriptionGateService.swift
//  PlayerPath
//
//  Centralized subscription gate checks for coaches.
//  Provides the UX layer on top of Firestore rules — shows paywalls
//  instead of letting permission errors bubble up.
//
//  Free coaches have basic access (upload, annotate, drill cards)
//  for up to their tier's athlete limit. Paid tiers increase the limit.
//

import SwiftUI

/// Stateless helper for subscription gate checks.
/// Uses the auth manager and shared folder data to determine limits.
enum SubscriptionGate {

    /// Whether the coach has more connected athletes than their tier allows.
    static func isCoachOverLimit(authManager: ComprehensiveAuthManager) -> Bool {
        let limit = authManager.coachAthleteLimit
        guard limit != Int.max else { return false }
        return connectedAthleteCount() > limit
    }

    /// How many athlete slots remain for the current coach tier.
    static func coachAthleteSlotsRemaining(authManager: ComprehensiveAuthManager) -> Int {
        let limit = authManager.coachAthleteLimit
        guard limit != Int.max else { return Int.max }
        return max(0, limit - connectedAthleteCount())
    }

    /// Number of athletes currently connected to this coach.
    static func connectedAthleteCount() -> Int {
        Set(SharedFolderManager.shared.coachFolders.map(\.ownerAthleteID)).count
    }

    /// Whether the coach can accept a new invitation.
    static func canAcceptInvitation(authManager: ComprehensiveAuthManager) -> Bool {
        coachAthleteSlotsRemaining(authManager: authManager) > 0
    }

    /// Whether the athlete can create shared folders (requires Pro).
    static func canAthleteShareFolders(authManager: ComprehensiveAuthManager) -> Bool {
        authManager.currentTier >= .pro
    }
}
