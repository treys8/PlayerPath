//
//  AthleteDowngradeManager.swift
//  PlayerPath
//
//  Detects when an athlete has shared folders but lost Pro tier.
//  Does NOT auto-revoke coach access — re-subscribing restores
//  everything automatically since folders and access persist.
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
    func evaluate(tier: SubscriptionTier) {
        let hasFolders = !SharedFolderManager.shared.athleteFolders.isEmpty

        if tier < .pro && hasFolders {
            if state != .lapsed {
                downgradeLog.info("Athlete has shared folders but tier is \(tier.rawValue) — marking lapsed")
            }
            state = .lapsed
        } else {
            if state != .none {
                downgradeLog.info("Athlete downgrade resolved (tier: \(tier.rawValue), folders: \(hasFolders))")
            }
            state = .none
        }
    }
}
