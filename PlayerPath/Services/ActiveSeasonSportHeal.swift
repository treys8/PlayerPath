//
//  ActiveSeasonSportHeal.swift
//  PlayerPath
//
//  Launch-time heal for the active-season ↔ pinned-sport desync.
//
//  Firestore sync-down writes Season.isActive/sport straight from the cloud doc,
//  bypassing Season.activate() (the only writer that keeps athlete.sport aligned
//  with the active season). That could leave a profile with an active season in a
//  different sport than its pinned athlete.sport — surfacing as the dashboard
//  showing one sport while the rest of the app shows the pinned one.
//
//  This realigns every athlete on launch via SeasonManager.reconcileActiveSeasonToPinnedSport.
//  It is fully idempotent — a no-op (no writes, no save) for a healthy profile — so
//  it runs on EVERY launch rather than behind a run-once flag. Running every launch
//  also catches drift that arrives after a one-shot flag would already be set; the
//  durable close for the vector itself lives in
//  SyncCoordinator+Seasons.downloadRemoteSeasons.
//

import Foundation
import SwiftData
import os

private let healLog = Logger(subsystem: "com.playerpath.app", category: "ActiveSeasonSportHeal")

@MainActor
enum ActiveSeasonSportHeal {
    /// Realigns every athlete's active season to its pinned sport. Idempotent and
    /// safe to call on every launch — it only writes (and saves) when it actually
    /// heals drift, so a failed save simply retries on the next launch.
    static func run(context: ModelContext) {
        let descriptor = FetchDescriptor<Athlete>()
        guard let athletes = try? context.fetch(descriptor) else {
            healLog.warning("Fetch failed; heal skipped this launch")
            return
        }

        var healed = 0
        for athlete in athletes
        where SeasonManager.reconcileActiveSeasonToPinnedSport(for: athlete, in: context) {
            healed += 1
        }

        guard healed > 0 else { return }
        healLog.info("Healed \(healed) athlete(s) with a drifted active-season sport")
        do {
            try context.save()
        } catch {
            healLog.error("Save failed after healing \(healed) athlete(s): \(error.localizedDescription)")
        }
    }
}
