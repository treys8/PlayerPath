//
//  CoachDowngradeManager.swift
//  PlayerPath
//
//  Detects when a coach has downgraded to a tier with fewer athlete
//  slots than they currently use. Manages a 7-day grace period, then
//  forces athlete selection.
//

import Foundation
import os

private let downgradeLog = Logger(subsystem: "com.playerpath.app", category: "CoachDowngrade")

@MainActor
@Observable
final class CoachDowngradeManager {

    static let shared = CoachDowngradeManager()

    // MARK: - State

    enum State: Equatable {
        case none
        case gracePeriod(daysRemaining: Int)
        case selectionRequired
    }

    private(set) var state: State = .none

    /// The athlete limit for the coach's current tier (cached for the selection view).
    private(set) var currentLimit: Int = 0

    /// The number of connected athletes (cached for display).
    private(set) var connectedCount: Int = 0

    /// Set by `markResolved` so feedback-block UIs unblock the instant a coach
    /// sheds, before the next profile refresh clears the server `downgradeUnresolved`
    /// flag. Reset by `evaluate` whenever a fresh count confirms the coach is STILL
    /// over limit, so a partial shed re-asserts the block.
    private(set) var locallyResolved = false

    // MARK: - Constants

    private static let gracePeriodDays = 7
    private static let graceStartKeyPrefix = "coachDowngradeGraceStart_"

    // MARK: - Init

    private init() {}

    // MARK: - Evaluation

    /// Call on app launch, after tier changes, and after folder list updates.
    /// - Parameter coachTier: Pass `authManager.currentCoachTier` (not StoreKitManager)
    ///   so Firestore-granted tiers like Academy are respected.
    /// - Parameters serverGraceStartedAt/serverUnresolved: the CF-managed backstop
    ///   fields from the loaded `UserProfile` (auditCoachDowngrades). The server clock
    ///   is authoritative and survives reinstalls, unlike the local UserDefaults
    ///   fallback — pass `authManager.userProfile?.coachDowngradeGraceStartedAt` and
    ///   `authManager.userProfile?.downgradeUnresolved`.
    func evaluate(coachID: String,
                  coachTier: CoachSubscriptionTier,
                  serverGraceStartedAt: Date? = nil,
                  serverUnresolved: Bool = false) async {
        let limit = coachTier.athleteLimit

        // Don't evaluate until StoreKit entitlements have resolved AND Firestore profile loaded.
        // Without this, Academy tier coaches (Firestore-granted) may see a flash of the
        // downgrade banner while StoreKit resolves their Free tier before profile loads.
        guard StoreKitManager.shared.hasResolvedEntitlements else {
            downgradeLog.debug("Skipping downgrade evaluation — entitlements not yet resolved")
            return
        }

        // Academy = unlimited, never over limit
        guard limit != Int.max else {
            clearGrace(coachID: coachID)
            state = .none
            return
        }

        let result = await SubscriptionGate.fullConnectedAthleteCountResult(coachID: coachID)
        currentLimit = limit
        connectedCount = result.count

        guard result.count > limit else {
            // Under or at limit — only clear grace period if count is confirmed.
            // If count is unconfirmed (network failure), preserve existing grace state
            // to prevent a sync failure from accidentally resetting the countdown.
            if result.isConfirmed {
                clearGrace(coachID: coachID)
                state = .none
            }
            downgradeLog.debug("Coach \(coachID) within limit (\(result.count)/\(limit), confirmed: \(result.isConfirmed))")
            return
        }

        // Still over limit on a fresh count — void any prior local resolution so
        // a partial shed re-asserts the feedback block.
        locallyResolved = false

        // Over limit. The server (auditCoachDowngrades) is authoritative once it has
        // flagged the coach — that gate survives reinstalls and matches what
        // firestore.rules enforces, so honor it before the local clock.
        if serverUnresolved {
            state = .selectionRequired
            downgradeLog.warning("Coach \(coachID) over limit (\(result.count)/\(limit)) — server marked downgrade unresolved, selection required")
            return
        }

        // Otherwise start or continue the grace period, preferring the server grace
        // start (survives reinstall) and falling back to the local clock until the
        // daily audit stamps the server one.
        let graceStart = serverGraceStartedAt ?? graceStartDate(for: coachID) ?? startGrace(coachID: coachID)
        let elapsed = Calendar.current.dateComponents([.day], from: graceStart, to: Date()).day ?? 0
        let remaining = max(0, Self.gracePeriodDays - elapsed)

        if remaining > 0 {
            state = .gracePeriod(daysRemaining: remaining)
            downgradeLog.info("Coach \(coachID) over limit (\(result.count)/\(limit)), grace period: \(remaining) days remaining")
        } else {
            state = .selectionRequired
            downgradeLog.warning("Coach \(coachID) over limit (\(result.count)/\(limit)), grace period expired — selection required")
        }
    }

    /// Authoritative "feedback delivery is blocked" check for any coach surface that
    /// performs a feedback write (publish / coach note / comment / annotation / drill
    /// card). The server `downgradeUnresolved` flag is what firestore.rules enforces,
    /// so any UI that can hit one of those writes must consult this to avoid a raw
    /// permission-denied. The `locallyResolved` override unblocks instantly after a
    /// shed, before the next profile refresh clears the server flag.
    /// Pass `authManager.userProfile?.downgradeUnresolved`.
    func feedbackBlocked(downgradeUnresolved: Bool?) -> Bool {
        (downgradeUnresolved == true) && !locallyResolved
    }

    /// Called after the coach completes athlete selection (revocation succeeded).
    func markResolved(coachID: String) {
        clearGrace(coachID: coachID)
        locallyResolved = true
        state = .none
        downgradeLog.info("Coach \(coachID) downgrade resolved")
    }

    // MARK: - Grace Period Persistence (UserDefaults)

    private func graceKey(for coachID: String) -> String {
        "\(Self.graceStartKeyPrefix)\(coachID)"
    }

    private func graceStartDate(for coachID: String) -> Date? {
        UserDefaults.standard.object(forKey: graceKey(for: coachID)) as? Date
    }

    @discardableResult
    private func startGrace(coachID: String) -> Date {
        let now = Date()
        UserDefaults.standard.set(now, forKey: graceKey(for: coachID))
        downgradeLog.info("Started grace period for coach \(coachID)")
        return now
    }

    private func clearGrace(coachID: String) {
        UserDefaults.standard.removeObject(forKey: graceKey(for: coachID))
    }
}
