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

    // MARK: - Constants

    private static let gracePeriodDays = 7
    private static let graceStartKeyPrefix = "coachDowngradeGraceStart_"

    // MARK: - Init

    private init() {}

    // MARK: - Evaluation

    /// Call on app launch, after tier changes, and after folder list updates.
    /// - Parameter coachTier: Pass `authManager.currentCoachTier` (not StoreKitManager)
    ///   so Firestore-granted tiers like Academy are respected.
    func evaluate(coachID: String, coachTier: CoachSubscriptionTier) async {
        let limit = coachTier.athleteLimit

        // Academy = unlimited, never over limit
        guard limit != Int.max else {
            clearGrace(coachID: coachID)
            state = .none
            return
        }

        let count = await SubscriptionGate.fullConnectedAthleteCount(coachID: coachID)
        currentLimit = limit
        connectedCount = count

        guard count > limit else {
            // Under or at limit — clear any grace period
            clearGrace(coachID: coachID)
            state = .none
            downgradeLog.debug("Coach \(coachID) within limit (\(count)/\(limit))")
            return
        }

        // Over limit — start or continue grace period
        let graceStart = graceStartDate(for: coachID) ?? startGrace(coachID: coachID)
        let elapsed = Calendar.current.dateComponents([.day], from: graceStart, to: Date()).day ?? 0
        let remaining = max(0, Self.gracePeriodDays - elapsed)

        if remaining > 0 {
            state = .gracePeriod(daysRemaining: remaining)
            downgradeLog.info("Coach \(coachID) over limit (\(count)/\(limit)), grace period: \(remaining) days remaining")
        } else {
            state = .selectionRequired
            downgradeLog.warning("Coach \(coachID) over limit (\(count)/\(limit)), grace period expired — selection required")
        }
    }

    /// Called after the coach completes athlete selection (revocation succeeded).
    func markResolved(coachID: String) {
        clearGrace(coachID: coachID)
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
