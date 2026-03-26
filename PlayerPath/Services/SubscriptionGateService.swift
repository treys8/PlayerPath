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
    /// Uses the full async count (folders + accepted invitations) for accuracy.
    @MainActor
    static func isCoachOverLimit(coachID: String, authManager: ComprehensiveAuthManager) async -> Bool {
        let limit = authManager.coachAthleteLimit
        guard limit != Int.max else { return false }
        return await fullConnectedAthleteCount(coachID: coachID) > limit
    }

    /// How many athlete slots remain for the current coach tier.
    @MainActor
    static func coachAthleteSlotsRemaining(coachID: String, authManager: ComprehensiveAuthManager) async -> Int {
        let limit = authManager.coachAthleteLimit
        guard limit != Int.max else { return Int.max }
        let count = await fullConnectedAthleteCount(coachID: coachID)
        return max(0, limit - count)
    }

    /// Result of a connected athlete count query. `isConfirmed` is true when the
    /// Firestore fetch succeeded, false when falling back to local data only.
    struct AthleteCountResult {
        let count: Int
        let isConfirmed: Bool
    }

    /// Full connected athlete count merging folder owners + accepted coach-to-athlete invitations.
    /// This is the single source of truth for athlete limit checks.
    /// Returns `isConfirmed: false` on network failure (uses local folder count as fallback).
    @MainActor
    static func fullConnectedAthleteCountResult(coachID: String) async -> AthleteCountResult {
        var athleteIDs = Set(SharedFolderManager.shared.coachFolders.map(\.ownerAthleteID))
        var confirmed = true
        do {
            let acceptedIDs = try await FirestoreManager.shared.fetchAcceptedCoachToAthleteAthleteIDs(coachID: coachID)
            athleteIDs.formUnion(acceptedIDs)
        } catch {
            confirmed = false
            ErrorHandlerService.shared.handle(error, context: "SubscriptionGate.fullConnectedAthleteCount", showAlert: false)
        }
        return AthleteCountResult(count: athleteIDs.count, isConfirmed: confirmed)
    }

    /// Full connected athlete count (convenience accessor when confirmation status isn't needed).
    @MainActor
    static func fullConnectedAthleteCount(coachID: String) async -> Int {
        await fullConnectedAthleteCountResult(coachID: coachID).count
    }

    /// Whether the coach is at or over their athlete limit (async, includes all sources).
    @MainActor
    static func isAtAthleteLimit(coachID: String, authManager: ComprehensiveAuthManager, includingPending: Bool = false) async -> Bool {
        let limit = authManager.coachAthleteLimit
        guard limit != Int.max else { return false }
        var count = await fullConnectedAthleteCount(coachID: coachID)
        if includingPending {
            do {
                let pendingCount = try await FirestoreManager.shared.countPendingCoachToAthleteInvitations(coachID: coachID)
                count += pendingCount
            } catch {
                // Best-effort: if pending count fails, use connected count only
                ErrorHandlerService.shared.handle(error, context: "SubscriptionGate.isAtAthleteLimit", showAlert: false)
            }
        }
        return count >= limit
    }

    /// Whether the athlete can create shared folders (requires Pro).
    static func canAthleteShareFolders(authManager: ComprehensiveAuthManager) -> Bool {
        authManager.currentTier >= .pro
    }
}
