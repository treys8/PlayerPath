//
//  AthleteDowngradeManager.swift
//  PlayerPath
//
//  Detects when an athlete has shared folders but lost Pro tier.
//  Does NOT auto-revoke coach access — re-subscribing restores
//  everything automatically since folders and access persist.
//

import Foundation
import FirebaseAuth
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
        let previousState = state

        if tier < .pro && hasFolders {
            if state != .lapsed {
                downgradeLog.info("Athlete has shared folders but tier is \(tier.rawValue) — marking lapsed")
            }
            state = .lapsed

            // Notify coaches when athlete first transitions to lapsed state
            if previousState != .lapsed {
                Task {
                    await notifyCoachesOfLapsedStatus()
                }
            }
        } else {
            if state != .none {
                downgradeLog.info("Athlete downgrade resolved (tier: \(tier.rawValue), folders: \(hasFolders))")
            }
            state = .none
        }
    }

    /// Posts in-app notifications (and triggers FCM via Firestore) to all coaches
    /// with access to the athlete's shared folders that the athlete's subscription lapsed.
    private func notifyCoachesOfLapsedStatus() async {
        let folders = SharedFolderManager.shared.athleteFolders
        let athleteName = Auth.auth().currentUser?.displayName ?? "An athlete"
        let athleteUID = Auth.auth().currentUser?.uid ?? ""

        // Collect unique coach IDs across all folders to avoid duplicate notifications
        var notifiedCoachIDs = Set<String>()
        for folder in folders {
            for coachID in folder.sharedWithCoachIDs {
                guard !notifiedCoachIDs.contains(coachID) else { continue }
                notifiedCoachIDs.insert(coachID)
                await ActivityNotificationService.shared.postAccessLapsedNotification(
                    folderID: folder.id ?? "",
                    folderName: folder.name,
                    athleteName: athleteName,
                    athleteID: athleteUID,
                    coachUserID: coachID
                )
            }
        }
    }
}
