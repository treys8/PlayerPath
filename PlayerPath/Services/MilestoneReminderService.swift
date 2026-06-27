//
//  MilestoneReminderService.swift
//  PlayerPath
//
//  Behavioral nudge #3: after a game is finished (live End or manual Mark
//  Complete) and stats recalc, diff the season's `MilestoneEngine.milestones(for:)`
//  against a persisted "already seen" set and fire a local celebration nudge for
//  the milestones that game earned. Fully local — a
//  `Milestone` is a derived struct, never persisted, so there is no schema/sync
//  surface. The seen-set (UserDefaults) is the dedup ledger Feature 5's Badge
//  wall can later reuse.
//
//  Two guards keep this from flooding on a fresh install / reinstall:
//   1. A launch baseline seed records every existing milestone as "seen".
//   2. A completion fires only the milestones owned by the just-completed game
//      (matched on `gameID`), so logging a back-dated game still celebrates its
//      own achievements without dumping a whole un-baselined season's history,
//      and bulk-backfilling old games fires one game's worth at a time.
//
//  "Seen" semantics — IMPORTANT: a milestone counts as seen the moment it is
//  surfaced IN-APP (the Journal `PPMilestoneMarker` shows it as soon as stats
//  recalc), NOT when the celebration push is confirmed delivered. So
//  `processGameEnd` writes the seen-set BEFORE calling `fireNudge` and discards
//  the schedule result on purpose: the push is a best-effort celebration on top
//  of an in-app surface the user already has. A milestone earned while
//  notifications are denied is therefore still "seen" and will not re-fire a
//  push if permission is later granted. This is deliberate — unlike
//  ClipTaggingReminderService, there is no delivery-confirmation rollback here,
//  because the user never misses the milestone itself (only the optional push).
//

import Foundation
import SwiftData
@preconcurrency import UserNotifications

@MainActor
final class MilestoneReminderService {

    static let shared = MilestoneReminderService()
    private init() {}

    /// Notification id prefix. The per-season suffix keeps two different seasons
    /// ending close together from overwriting each other; the same season
    /// re-ending still replaces its own pending nudge.
    static let idPrefix = "milestone-nudge"

    /// UserDefaults key holding the array of milestone ids already surfaced.
    /// `nil` (absent) means "never seeded" → seed silently. Feature 5 reuses this.
    static let seenKey = "notif_milestoneSeenIDs"

    /// Short delay so the nudge isn't jarringly instant; if the athlete is still
    /// in-app the foreground `willPresent` suppression hides it (they already see
    /// the milestone in the Journal), and it lands on the Lock Screen if they
    /// leave.
    private static let fireDelay: TimeInterval = 5

    /// One-time baseline: record every existing milestone as seen so the first
    /// post-install game end only fires for genuinely new achievements. Idempotent
    /// — no-ops once the key exists. Pure synchronous reads (safe at launch).
    func seedBaselineIfNeeded(for user: User) {
        guard UserDefaults.standard.stringArray(forKey: Self.seenKey) == nil else { return }
        guard !user.isDeleted, user.modelContext != nil else { return }

        var ids: [String] = []
        for athlete in user.athletes ?? [] where !athlete.isDeleted {
            for season in athlete.seasons ?? [] where !season.isDeleted {
                ids.append(contentsOf: MilestoneEngine.milestones(for: season).map(\.id))
            }
        }
        UserDefaults.standard.set(ids, forKey: Self.seenKey)
    }

    /// Diff the just-completed game's season against the seen-set and fire a
    /// nudge for the milestones that game earned (unseen + matched on `gameID`).
    /// Pass the game synchronously — the `milestones(for:)` read runs before the
    /// first `await`, then only plain values cross the suspension.
    func processGameEnd(game: Game?) async {
        let enabled = UserDefaults.standard.object(forKey: NotificationPrefKeys.milestoneReminder) as? Bool ?? true
        guard enabled else { return }
        guard let game, !game.isDeleted, game.modelContext != nil,
              let season = game.season, !season.isDeleted else { return }

        // Snapshot model identity synchronously (before any await) so the tap can
        // route to the milestone's own profile, not whichever athlete happens to
        // be selected — matters for dual-sport / multi-athlete accounts.
        let gameID = game.id
        let seasonID = season.id.uuidString
        let athleteID = season.athlete?.id.uuidString

        // Pure read — no await yet.
        let current = MilestoneEngine.milestones(for: season)
        guard !current.isEmpty else { return }
        let currentIDs = current.map(\.id)

        let seenRaw = UserDefaults.standard.stringArray(forKey: Self.seenKey)
        // Not yet baselined (e.g. seed hasn't run): record and fire nothing.
        guard let seen = seenRaw else {
            UserDefaults.standard.set(currentIDs, forKey: Self.seenKey)
            return
        }
        let seenSet = Set(seen)

        // Fire only the milestones this game itself earned (unseen + owned by
        // this game). Back-dated logging still celebrates, and completing many
        // old games can't flood — each fires only its own achievements.
        let fresh = current.filter { !seenSet.contains($0.id) && $0.gameID == gameID }

        // Record everything seen now so nothing re-fires on the next completion.
        UserDefaults.standard.set(Array(seenSet.union(currentIDs)), forKey: Self.seenKey)

        guard !fresh.isEmpty else { return }

        // Snapshot to plain strings — no model access past here.
        let titles = fresh.map(\.title)
        await fireNudge(titles: titles, seasonID: seasonID, athleteID: athleteID)
    }

    /// Cancel every pending milestone nudge. Used when the toggle is switched off.
    func cancel() async {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
        if !ids.isEmpty {
            PushNotificationService.shared.cancelNotifications(withIdentifiers: ids)
        }
    }

    // MARK: - Private

    private func fireNudge(titles: [String], seasonID: String, athleteID: String?) async {
        let multiple = titles.count > 1
        let title = multiple ? "New milestones! 🎉" : "New milestone! 🎉"
        let body = multiple
            ? "You earned \(titles.count) new milestones. Tap to see them."
            : (titles.first ?? "You earned a new milestone.")

        var userInfo: [String: Any] = ["type": "milestone"]
        if let athleteID { userInfo["athleteID"] = athleteID }

        _ = await PushNotificationService.shared.scheduleLocalNotification(
            identifier: "\(Self.idPrefix)-\(seasonID)",
            title: title,
            body: body,
            categoryIdentifier: nil,
            userInfo: userInfo,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: Self.fireDelay, repeats: false)
        )
    }
}
