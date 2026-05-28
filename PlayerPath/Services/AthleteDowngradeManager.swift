//
//  AthleteDowngradeManager.swift
//  PlayerPath
//
//  Tracks whether the athlete has shared folders while below Pro tier, for the
//  UI to surface a re-subscribe prompt. The actual revocation, coach
//  notification, and seamless restore-on-renewal are handled SERVER-SIDE by the
//  `syncCoachAccessOnAthleteTierChange` Cloud Function (it fires even when the
//  app isn't foregrounded), so this manager intentionally has no side effects.
//

import Foundation
import os

private let downgradeLog = Logger(subsystem: "com.playerpath.app", category: "AthleteDowngrade")

@MainActor
@Observable
final class AthleteDowngradeManager {

    static let shared = AthleteDowngradeManager()

    // MARK: - State

    enum State: Equatable {
        case none
        case lapsed
    }

    private(set) var state: State = .none

    // MARK: - Init

    private init() {}

    // MARK: - Evaluation

    /// Call on app launch, after tier changes, and after folder list updates.
    /// Reflects local lapsed state only — coach-access changes are server-driven.
    func evaluate(tier: SubscriptionTier) {
        let hasFolders = !SharedFolderManager.shared.athleteFolders.isEmpty
        let newState: State = (tier < .pro && hasFolders) ? .lapsed : .none

        if newState != state {
            downgradeLog.info("Athlete lapsed state → \(newState == .lapsed ? "lapsed" : "none") (tier: \(tier.rawValue), folders: \(hasFolders))")
            state = newState
        }
    }
}
