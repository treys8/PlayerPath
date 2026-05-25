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
        // Per-athlete UUID when present (new data), account UID fallback (legacy) so one slot per real athlete.
        var athleteIDs = Set(SharedFolderManager.shared.coachFolders.map { $0.athleteUUID ?? $0.ownerAthleteID })
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

    /// Strict version for write paths (accept invitation, start session, send invite).
    /// Returns `.block(reason:)` when the write should be refused, `.allow` when
    /// it should proceed. Treats an unconfirmed server count as "block + retry"
    /// rather than silently letting the write through on local-only data — the
    /// stricter posture prevents an offline coach at the limit from sneaking
    /// extras through that the server CF would later reject.
    enum WriteGateDecision: Equatable {
        case allow
        case block(reason: BlockReason)
    }

    enum BlockReason: Equatable {
        case atOrOverLimit(current: Int, limit: Int)
        case unconfirmed
    }

    @MainActor
    static func writeGateDecision(coachID: String,
                                  authManager: ComprehensiveAuthManager,
                                  includingPending: Bool = false) async -> WriteGateDecision {
        let limit = authManager.coachAthleteLimit
        guard limit != Int.max else { return .allow }

        let result = await fullConnectedAthleteCountResult(coachID: coachID)
        if !result.isConfirmed { return .block(reason: .unconfirmed) }

        var count = result.count
        if includingPending {
            do {
                count += try await FirestoreManager.shared.countPendingCoachToAthleteInvitations(coachID: coachID)
            } catch {
                ErrorHandlerService.shared.handle(error, context: "SubscriptionGate.writeGateDecision", showAlert: false)
                return .block(reason: .unconfirmed)
            }
        }
        if count >= limit {
            return .block(reason: .atOrOverLimit(current: count, limit: limit))
        }
        return .allow
    }

    /// User-facing message for a block decision.
    static func message(for reason: BlockReason) -> String {
        switch reason {
        case .atOrOverLimit:
            return "You've reached your athlete limit. Upgrade your plan to invite more athletes."
        case .unconfirmed:
            return "Couldn't verify your limit. Check your connection and try again."
        }
    }
}
