//
//  ManualStatsBackfill.swift
//  PlayerPath
//
//  One-time backfill that protects pre-V20 manual stat entries from being
//  wiped by the next video sync.
//
//  Before V20, GameStatistics counters could be written from ManualStatisticsEntryView
//  or QuickStatisticsEntryView without any marker. StatisticsService.recalculateGameStatistics
//  wiped those counters on every video sync event. V20 adds `hasManualEntry` as a
//  sticky flag, but existing GameStatistics need to be retroactively flagged or
//  those users lose their stats on their next sync.
//
//  Heuristic: if a GameStatistics has non-zero counters AND the associated game
//  has no VideoClip with a playResult, the counters must have come from manual
//  entry. Set hasManualEntry=true so the guard in recalculate spares them.
//

import Foundation
import SwiftData
import os

private let backfillLog = Logger(subsystem: "com.playerpath.app", category: "ManualStatsBackfill")

@MainActor
enum ManualStatsBackfill {
    private static let didRunKey = "didBackfillManualEntryFlags_v20"

    /// Runs once per install. No-op on subsequent launches.
    static func runIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: didRunKey) else { return }

        let descriptor = FetchDescriptor<GameStatistics>()
        guard let allStats = try? context.fetch(descriptor) else {
            // Don't flip the flag — let a future launch retry.
            backfillLog.warning("Fetch failed; backfill deferred")
            return
        }

        var flagged = 0
        for stats in allStats where !stats.hasManualEntry {
            guard let game = stats.game else { continue }

            let hasAnyCounter = stats.atBats > 0
                || stats.walks > 0
                || stats.hitByPitches > 0
                || stats.totalPitches > 0
            guard hasAnyCounter else { continue }

            let hasTaggedVideos = (game.videoClips ?? []).contains { $0.playResult != nil }
            guard !hasTaggedVideos else { continue }

            stats.hasManualEntry = true
            game.needsSync = true
            flagged += 1
        }

        if flagged > 0 {
            backfillLog.info("Flagged \(flagged) games as manual-entry")
            try? context.save()
        }

        UserDefaults.standard.set(true, forKey: didRunKey)
    }
}
