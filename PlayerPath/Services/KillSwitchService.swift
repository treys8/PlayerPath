//
//  KillSwitchService.swift
//  PlayerPath
//
//  Remote kill switches. Reads Firestore `appConfig/killSwitches` (parsed by
//  KillSwitchPolicy) and answers "is this feature switched off?" for the gated
//  call sites. Gates read a cached answer synchronously; `refresh()` updates it
//  on sign-in and on every foreground. Kill-only — see `KillSwitch`.
//
//  Runbook: docs/quick-reference/KILL_SWITCHES.md
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import UserNotifications
import os

private let killLog = Logger(subsystem: "com.playerpath.app", category: "KillSwitch")

@MainActor
final class KillSwitchService {
    static let shared = KillSwitchService()

    private static let docID = "killSwitches"
    /// Last successfully fetched state, so a kill still holds on an offline launch.
    private static let cacheKey = "killSwitches.active.v1"

    /// Switched-off features (raw value) → message ("" = default copy).
    private var kills: [String: String]
    private var isRefreshing = false

    private init() {
        kills = UserDefaults.standard.dictionary(forKey: Self.cacheKey) as? [String: String] ?? [:]
    }

    func isKilled(_ feature: KillSwitch) -> Bool {
        #if DEBUG
        if Self.debugForced.contains(feature) { return true }
        #endif
        return kills[feature.rawValue] != nil
    }

    /// The doc's `message` when set, otherwise copy that says the pause is
    /// temporary and nothing was lost.
    func message(for feature: KillSwitch) -> String {
        if let custom = kills[feature.rawValue], !custom.isEmpty { return custom }
        switch feature {
        case .bulkVideoImport, .bulkPhotoImport:
            return "Importing from Photos is paused while we fix an issue. Nothing you've already saved is affected."
        case .reelGeneration:
            return "Building new reels is paused while we fix an issue. Your clips are safe — try again later."
        case .engagementNudges:
            return ""
        }
    }

    /// Fetch the doc and replace the cached state. A missing doc means nothing is
    /// off; a failed fetch keeps the cache. Safe to call often — overlapping
    /// calls collapse into the one in flight.
    func refresh() async {
        guard !isRefreshing else { return }
        // appConfig reads require auth (firestore.rules), so signed-out is a no-op.
        guard Auth.auth().currentUser != nil else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let snapshot = try await Firestore.firestore()
                .collection(FC.appConfig).document(Self.docID).getDocument()
            let fresh = KillSwitchPolicy.activeKills(in: snapshot.data() ?? [:], appVersion: Bundle.main.appVersion)
            if fresh != kills {
                killLog.notice("Kill switches changed → off: [\(fresh.keys.sorted().joined(separator: ", "), privacy: .public)]")
            }
            kills = fresh
            UserDefaults.standard.set(fresh, forKey: Self.cacheKey)
        } catch {
            killLog.warning("Kill switch fetch failed, keeping cached state: \(error.localizedDescription, privacy: .public)")
        }

        // Every refresh while killed, not only on the flip: the foreground nudge
        // scheduling in MainTabView runs in unawaited Tasks and can land after
        // this refresh, so sweeping each time limits a stray to one foreground.
        if isKilled(.engagementNudges) {
            await sweepNudges()
        }

        #if DEBUG
        // Proves a refresh ran, and is how the manual checks read pending
        // notifications (LLDB can't evaluate `await`).
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
        killLog.debug("Refreshed. off: [\(self.kills.keys.sorted().joined(separator: ", "), privacy: .public)] pending: [\(pending.sorted().joined(separator: ", "), privacy: .public)]")
        #endif
    }

    private func sweepNudges() async {
        WeekendPrepScheduler.cancel()
        InactivityReminderService.shared.cancel()
        await WeeklySummaryScheduler.cancelAll()
        await ClipTaggingReminderService.shared.cancelAll()
        await MilestoneReminderService.shared.cancel()
        killLog.info("Swept pending engagement nudges")
    }

    #if DEBUG
    /// Simulator testing without touching prod: add the launch argument
    /// `-KillSwitchForce bulkVideoImport,reelGeneration` in Edit Scheme → Run → Arguments.
    /// Launch arguments land in the volatile argument domain, so nothing persists.
    private static let debugForced: Set<KillSwitch> = {
        guard let raw = UserDefaults.standard.string(forKey: "KillSwitchForce") else { return [] }
        return Set(raw.split(separator: ",").compactMap {
            KillSwitch(rawValue: $0.trimmingCharacters(in: .whitespaces))
        })
    }()
    #endif
}
