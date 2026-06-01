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
        let calendar = Calendar.current
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)

        // Determine season name based on current month
        let seasonName: String
        if month >= 2 && month <= 6 {
            seasonName = "Spring \(year)"
        } else if month >= 7 && month <= 10 {
            seasonName = "Fall \(year)"
        } else if month == 1 {
            seasonName = "Winter \(year)"
        } else {
            seasonName = "Winter \(year + 1)"
        }

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

    /// Heals a standalone profile's primary `sport` to match its active season.
    ///
    /// `Season.activate()` is normally the sole writer that keeps `athlete.sport`
    /// aligned with the active season. Paths that mark a season active WITHOUT it
    /// — notably Firestore sync-down (`SyncCoordinator+Seasons`), which writes
    /// `isActive`/`sport` straight from the cloud doc — can leave `athlete.sport`
    /// pointing at a different sport than the active season. That desync makes the
    /// dashboard's sport filter hide the active season (0-count + "create your
    /// first season" banner) while the unfiltered Seasons screen still shows it,
    /// and leaves the tab chrome on the wrong sport.
    ///
    /// Scoped to standalone profiles (`personGroupID == nil`). Dual-sport spinoff
    /// profiles deliberately pin their sport and hold only their own sport's
    /// seasons (see MainTabView), so they are never realigned here.
    ///
    /// Idempotent: no-ops when already aligned or when there's no active season.
    /// Marks `needsSync` so the corrected value heals the cloud row on next push.
    static func reconcileAthleteSportToActiveSeason(for athlete: Athlete, in modelContext: ModelContext) {
        guard athlete.personGroupID == nil,
              let activeSeasonSport = athlete.activeSeason?.sport,
              let mapped = Sport(rawValue: activeSeasonSport.rawValue.lowercased()),
              athlete.sport != mapped else { return }

        athlete.sport = mapped
        athlete.needsSync = true
        ErrorHandlerService.shared.saveContext(modelContext, caller: "SeasonManager.reconcileAthleteSportToActiveSeason")
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

    /// Generates a season summary report (useful for archive view)
    /// - Parameter season: The season to summarize
    /// - Returns: A formatted summary string
    static func generateSeasonSummary(for season: Season) -> String {
        var summary = "\(season.displayName)\n\n"

        // Date range
        if let start = season.startDate, let end = season.endDate {
            summary += "Duration: \(start.formatted(date: .abbreviated, time: .omitted)) - \(end.formatted(date: .abbreviated, time: .omitted))\n\n"
        }

        // Stats
        summary += "📊 Season Overview\n"
        summary += "• Games Played: \(season.completedGames)\n"
        summary += "• Practices: \((season.practices ?? []).count)\n"
        summary += "• Videos Recorded: \(season.totalVideos)\n"
        summary += "• Highlights: \(season.highlights.count)\n\n"

        // Baseball stats if available
        if let stats = season.seasonStatistics, stats.atBats > 0 {
            summary += "⚾️ Batting Statistics\n"
            let avgDisplay = stats.battingAverage >= 1.0 ? "1.000" : String(format: ".%03d", Int(stats.battingAverage * 1000))
            summary += "• Batting Average: \(avgDisplay)\n"
            summary += "• At Bats: \(stats.atBats)\n"
            summary += "• Hits: \(stats.hits)\n"
            summary += "• Home Runs: \(stats.homeRuns)\n"
            summary += "• RBIs: \(stats.rbis)\n"
            summary += "• Walks: \(stats.walks)\n"
            summary += "• Strikeouts: \(stats.strikeouts)\n"
        }

        return summary
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
