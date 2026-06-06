//
//  SeasonManager.swift
//  PlayerPath
//
//  Created by Assistant on 11/13/25.
//

import Foundation
import SwiftData
import os

private let log = Logger(subsystem: "com.playerpath.app", category: "SeasonManager")

/// Utility for managing seasons and ensuring proper season linkage
@MainActor
struct SeasonManager {

    /// Ensures an athlete has an active season, creating a default one if needed.
    /// - Parameters:
    ///   - athlete: The athlete to check
    ///   - modelContext: The SwiftData model context
    /// - Returns: The active season (existing or newly created), or nil if creation failed to persist.
    @discardableResult
    static func ensureActiveSeason(for athlete: Athlete, in modelContext: ModelContext) -> Season? {
        // If athlete already has an active season, return it
        if let activeSeason = athlete.activeSeason {
            return activeSeason
        }

        // Create a default season based on current date
        let now = Date()
        let seasonName = defaultSeasonName(for: now)

        // Infer sport: most recent season's sport, else the athlete's primary
        // hint (so spinoff profiles with no seasons honor their declared sport),
        // else .baseball.
        let mostRecentSport = athlete.seasons?
            .sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
            .first?.sport
        let hintSport = Season.SportType(rawValue: (athlete.sport ?? .baseball).rawValue.capitalized)
        let sport = mostRecentSport ?? hintSport ?? .baseball

        // Create and activate new season
        // Set the athlete relationship BEFORE activate() so the deactivation
        // loop inside activate() can see athlete.seasons and deactivate them.
        let newSeason = Season(name: seasonName, startDate: now, sport: sport)
        newSeason.athlete = athlete
        athlete.seasons = athlete.seasons ?? []
        athlete.seasons?.append(newSeason)
        newSeason.activate()

        modelContext.insert(newSeason)

        do {
            try modelContext.save()
        } catch {
            log.error("Error creating default season: \(error.localizedDescription)")
            return nil
        }

        return newSeason
    }

    /// Default season name derived from the calendar month
    /// (Spring/Fall/Winter + year).
    static func defaultSeasonName(for date: Date) -> String {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        if month >= 2 && month <= 6 { return "Spring \(year)" }
        if month >= 7 && month <= 10 { return "Fall \(year)" }
        if month == 1 { return "Winter \(year)" }
        return "Winter \(year + 1)"
    }

    /// Heals the active-season ↔ pinned-sport desync for one athlete.
    ///
    /// The pinned sport (`athlete.sport`, surfaced as `athlete.sportType`) is the
    /// authoritative sport for a profile. `Season.activate()` is the only writer
    /// that keeps the pin aligned with the active season, but Firestore sync-down
    /// (`SyncCoordinator+Seasons.downloadRemoteSeasons`) writes `Season.isActive`/
    /// `sport` straight from the cloud doc, bypassing `activate()` — so a remote can
    /// leave a season active in a *different* sport than the pin, or leave several
    /// seasons active at once. This collapses the athlete back to at most one active
    /// season in the pinned sport WITHOUT touching `athlete.sport` (we heal toward
    /// the pin; we never repin to follow a stray season).
    ///
    /// If a pinned-sport season exists (active or archived) it becomes the sole
    /// active one. If none exists, the stray active season(s) are simply deactivated
    /// and the athlete is left with no active season — the dashboard then nudges them
    /// to create one in their real sport. We deliberately do NOT auto-create a season
    /// here: creating inside the sync-down path races other devices into duplicate
    /// seasons, and would surprise users who intentionally abandoned a sport.
    ///
    /// Safe for dual-sport spinoff profiles (`personGroupID != nil`) without the
    /// `personGroupID == nil` scope the reverted df2fc7b reconcile needed: that one
    /// rewrote `athlete.sport` from the active season (season → pin), which would
    /// corrupt a spinoff's fixed sport. This heals the opposite direction (pin →
    /// season) and never writes `athlete.sport`, so each profile is only ever
    /// realigned toward its own pinned sport.
    ///
    /// Idempotent: a no-op when the athlete already has a single pinned-sport active
    /// season. Mutate-only — the caller is responsible for `modelContext.save()`.
    /// - Returns: `true` if it changed anything.
    @discardableResult
    static func reconcileActiveSeasonToPinnedSport(for athlete: Athlete, in modelContext: ModelContext) -> Bool {
        let pinned = athlete.sportType
        let seasons = athlete.seasons ?? []
        let activeSeasons = seasons.filter { $0.isActive }
        let pinnedActive = activeSeasons.filter { ($0.sport ?? .baseball) == pinned }
        let strayActive  = activeSeasons.filter { ($0.sport ?? .baseball) != pinned }

        // Healthy: at most one active season, and any active one is the pinned sport.
        guard !strayActive.isEmpty || pinnedActive.count > 1 else { return false }

        // The pinned-sport season to keep active: the most-recent already-active
        // one, else the most-recent archived one to revive. Never created here.
        let newer: (Season, Season) -> Bool = {
            ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast)
        }
        let keep = pinnedActive.max(by: newer)
            ?? seasons.filter { ($0.sport ?? .baseball) == pinned }.max(by: newer)

        if let keep {
            // activate() deactivates every OTHER active season (strays + duplicate
            // pinned) and flips `keep` active. Its athlete.sport realignment is a
            // guaranteed no-op because `keep` already matches the pin, so the pinned
            // sport is preserved.
            keep.activate()
        } else {
            // No pinned-sport season exists at all — deactivate the stray active
            // season(s) without repinning. archive() sets isActive=false + dirties
            // for upload but never touches athlete.sport.
            for stray in strayActive { stray.archive() }
        }
        log.info("Reconciled drifted active season to pinned sport: \(pinned.rawValue)")
        return true
    }

    /// Links a practice to the athlete's active season.
    /// - Note: Caller is responsible for calling `modelContext.save()` after this function.
    static func linkPracticeToActiveSeason(_ practice: Practice, for athlete: Athlete, in modelContext: ModelContext) {
        guard practice.season == nil else { return }
        guard practice.athlete?.id == athlete.id else {
            log.error("Practice does not belong to athlete — skipping season link")
            return
        }

        guard let activeSeason = ensureActiveSeason(for: athlete, in: modelContext) else {
            log.error("Failed to ensure active season for practice linking")
            return
        }
        practice.season = activeSeason
    }

    /// Checks if an athlete should be prompted to create or end a season.
    /// - Parameters:
    ///   - athlete: The athlete to check.
    ///   - sport: When non-nil, evaluates only seasons matching this sport, so
    ///     a golf athlete with no golf season but an active baseball season
    ///     gets a "create first" / "no active season" recommendation instead
    ///     of a misleading `.ok`. Pass nil to preserve legacy sport-agnostic
    ///     behavior.
    /// - Returns: A recommendation for season management.
    static func checkSeasonStatus(for athlete: Athlete, sport: Season.SportType? = nil) -> SeasonRecommendation {
        let seasons = (athlete.seasons ?? []).filter { season in
            guard let sport else { return true }
            return (season.sport ?? .baseball) == sport
        }

        // No seasons at all - recommend creating one
        if seasons.isEmpty {
            return .createFirst
        }

        // No active season - recommend creating or reactivating
        guard let activeSeason = seasons.first(where: { $0.isActive }) else {
            return .noActiveSeason
        }

        // Active season is very old (6+ months) - recommend ending
        if let startDate = activeSeason.startDate,
           let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: Date()) {
            if startDate < sixMonthsAgo {
                return .considerEnding(activeSeason)
            }
        }

        return .ok
    }

    enum SeasonRecommendation {
        case createFirst
        case noActiveSeason
        case considerEnding(Season)
        case ok

        var message: String? {
            switch self {
            case .createFirst:
                return "Create your first season to start tracking games and videos"
            case .noActiveSeason:
                return "No active season. Create a new season or reactivate an old one"
            case .considerEnding(let season):
                return "\(season.displayName) has been active for 6+ months. Consider ending it and starting a new season"
            case .ok:
                return nil
            }
        }
    }
}
