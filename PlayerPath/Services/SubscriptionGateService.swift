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

/// A reference to an athlete connected via an accepted coach→athlete invitation.
/// Carries both identifier axes because the same real athlete can be recorded
/// under two namespaces — the stable Athlete UUID and the account UID — and
/// reconciliation against folders needs both to avoid double-counting.
struct CoachAthleteRef {
    let athleteUUID: String?
    let athleteUserID: String?
    /// Person-group key carried from the invitation doc so a dual-sport person
    /// collapses to ONE coach slot: both sport profiles share one personGroupID,
    /// making it the highest-priority dedup axis. Equals `athleteUUID` for solo
    /// athletes, so promoting it is behavior-preserving for the common case.
    let personGroupID: String?

    /// Canonical per-athlete key: prefer the person-group key (collapses a
    /// dual-sport person's profiles), then the stable Athlete UUID, then account UID.
    var canonicalKey: String? { personGroupID ?? athleteUUID ?? athleteUserID }
}

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

    /// Accepted-invitation refs that are NOT already represented by a folder,
    /// deduplicated by canonical key.
    ///
    /// Reconciliation must distinguish two superficially identical situations that
    /// share an account UID:
    /// 1. The SAME athlete recorded under two namespaces (a folder keyed by Athlete
    ///    UUID + a legacy invitation that only carries the account UID) — must merge.
    /// 2. TWO athlete profiles under one parent account, the second connected by an
    ///    invitation whose folders haven't synced yet — must NOT merge (N slots).
    ///
    /// The Athlete UUID is the discriminator: when both sides have one, only a UUID
    /// match counts as "already known". The account-UID axis is used only when a
    /// UUID isn't available to compare (legacy folder or UUID-less invitation), where
    /// legacy data is inherently single-profile so account reconciliation is safe.
    static func unmatchedInvitationRefs(folders: [SharedFolder], invitationRefs: [CoachAthleteRef]) -> [CoachAthleteRef] {
        var folderPersonGroupIDs = Set<String>()       // personGroupIDs present on folders
        var folderUUIDs = Set<String>()                // athleteUUIDs present on folders
        var folderAccountIDs = Set<String>()           // all folder owner account UIDs
        var legacyFolderAccountIDs = Set<String>()      // owner UIDs of folders that have no UUID
        for folder in folders {
            if let group = folder.personGroupID, !group.isEmpty {
                folderPersonGroupIDs.insert(group)
            }
            if let uuid = folder.athleteUUID, !uuid.isEmpty {
                folderUUIDs.insert(uuid)
            } else {
                legacyFolderAccountIDs.insert(folder.ownerAthleteID)
            }
            folderAccountIDs.insert(folder.ownerAthleteID)
        }
        var seen = Set<String>()
        var result: [CoachAthleteRef] = []
        for ref in invitationRefs {
            if isRepresentedByFolder(ref,
                                     folderPersonGroupIDs: folderPersonGroupIDs,
                                     folderUUIDs: folderUUIDs,
                                     folderAccountIDs: folderAccountIDs,
                                     legacyFolderAccountIDs: legacyFolderAccountIDs) {
                continue
            }
            guard let key = ref.canonicalKey, seen.insert(key).inserted else { continue }
            result.append(ref)
        }
        return result
    }

    /// Whether an accepted invitation already corresponds to an existing folder.
    /// See `unmatchedInvitationRefs` for the reconciliation rationale.
    private static func isRepresentedByFolder(_ ref: CoachAthleteRef,
                                              folderPersonGroupIDs: Set<String>,
                                              folderUUIDs: Set<String>,
                                              folderAccountIDs: Set<String>,
                                              legacyFolderAccountIDs: Set<String>) -> Bool {
        // Highest-priority axis: the person-group key. A dual-sport person's
        // profiles all carry one personGroupID, so an invitation for either sport
        // is "already known" if any folder in the group exists. Fall through to the
        // UUID/account axes when no folder is backfilled with this group yet.
        if let group = ref.personGroupID, !group.isEmpty,
           folderPersonGroupIDs.contains(group) {
            return true
        }
        if let uuid = ref.athleteUUID, !uuid.isEmpty {
            if folderUUIDs.contains(uuid) { return true }
            // No UUID-matching folder: only a legacy (UUID-less) folder for the same
            // account is this same athlete. A folder with a DIFFERENT UUID is a
            // separate profile on the same parent account.
            if let account = ref.athleteUserID, legacyFolderAccountIDs.contains(account) { return true }
            return false
        }
        // UUID-less invitation: reconcile on the account axis against any folder.
        if let account = ref.athleteUserID, folderAccountIDs.contains(account) { return true }
        return false
    }

    /// Deduplicated set of connected-athlete keys: folder owners reconciled with
    /// accepted coach→athlete invitations. The single source of truth for the
    /// athlete-count used by limit checks and the coach UI.
    static func connectedAthleteKeys(folders: [SharedFolder], invitationRefs: [CoachAthleteRef]) -> Set<String> {
        // One slot per real person: prefer the person-group key (collapses a
        // dual-sport person's two folders), then the Athlete UUID, then account UID.
        var keys = Set(folders.map { $0.personGroupID ?? $0.athleteUUID ?? $0.ownerAthleteID })
        for ref in unmatchedInvitationRefs(folders: folders, invitationRefs: invitationRefs) {
            if let key = ref.canonicalKey { keys.insert(key) }
        }
        return keys
    }

    /// Full connected athlete count merging folder owners + accepted coach-to-athlete invitations.
    /// This is the single source of truth for athlete limit checks.
    /// Returns `isConfirmed: false` on network failure (uses local folder count as fallback).
    @MainActor
    static func fullConnectedAthleteCountResult(coachID: String) async -> AthleteCountResult {
        let folders = SharedFolderManager.shared.coachFolders
        var invitationRefs: [CoachAthleteRef] = []
        var confirmed = true
        do {
            invitationRefs = try await FirestoreManager.shared.fetchAcceptedCoachToAthleteRefs(coachID: coachID)
        } catch {
            confirmed = false
            ErrorHandlerService.shared.handle(error, context: "SubscriptionGate.fullConnectedAthleteCount", showAlert: false)
        }
        let count = connectedAthleteKeys(folders: folders, invitationRefs: invitationRefs).count
        return AthleteCountResult(count: count, isConfirmed: confirmed)
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
