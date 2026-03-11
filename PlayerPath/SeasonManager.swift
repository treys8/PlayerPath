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

        // Infer sport from athlete's most recent season; fall back to .baseball
        let sport = athlete.seasons?
            .sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
            .first?.sport ?? .baseball

        // Create and activate new season
        let newSeason = Season(name: seasonName, startDate: now, sport: sport)
        newSeason.activate()
        newSeason.athlete = athlete

        athlete.seasons = athlete.seasons ?? []
        athlete.seasons?.append(newSeason)

        modelContext.insert(newSeason)

        do {
            try modelContext.save()
        } catch {
            log.error("Error creating default season: \(error.localizedDescription)")
            return nil
        }

        return newSeason
    }

    /// Links a game to the athlete's active season.
    /// - Note: Caller is responsible for calling `modelContext.save()` after this function.
    static func linkGameToActiveSeason(_ game: Game, for athlete: Athlete, in modelContext: ModelContext) {
        // Silently skips games already assigned to a season
        guard game.season == nil else { return }

        guard let activeSeason = ensureActiveSeason(for: athlete, in: modelContext) else {
            log.error("Failed to ensure active season for game linking")
            return
        }
        game.season = activeSeason  // SwiftData handles inverse relationship automatically
    }

    /// Links a practice to the athlete's active season.
    /// - Note: Caller is responsible for calling `modelContext.save()` after this function.
    static func linkPracticeToActiveSeason(_ practice: Practice, for athlete: Athlete, in modelContext: ModelContext) {
        // Silently skips practices already assigned to a season
        guard practice.season == nil else { return }

        guard let activeSeason = ensureActiveSeason(for: athlete, in: modelContext) else {
            log.error("Failed to ensure active season for practice linking")
            return
        }
        practice.season = activeSeason  // SwiftData handles inverse relationship automatically
    }

    /// Links a video clip to the athlete's active season.
    /// - Note: Caller is responsible for calling `modelContext.save()` after this function.
    static func linkVideoToActiveSeason(_ videoClip: VideoClip, for athlete: Athlete, in modelContext: ModelContext) {
        // Silently skips clips already assigned to a season
        guard videoClip.season == nil else { return }

        guard let activeSeason = ensureActiveSeason(for: athlete, in: modelContext) else {
            log.error("Failed to ensure active season for video linking")
            return
        }
        videoClip.season = activeSeason  // SwiftData handles inverse relationship automatically
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
        summary += "• Games Played: \(season.totalGames)\n"
        summary += "• Practices: \((season.practices ?? []).count)\n"
        summary += "• Videos Recorded: \(season.totalVideos)\n"
        summary += "• Highlights: \(season.highlights.count)\n\n"

        // Baseball stats if available
        if let stats = season.seasonStatistics, stats.atBats > 0 {
            summary += "⚾️ Batting Statistics\n"
            summary += "• Batting Average: \(String(format: ".%03d", Int(stats.battingAverage * 1000)))\n"
            summary += "• At Bats: \(stats.atBats)\n"
            summary += "• Hits: \(stats.hits)\n"
            summary += "• Home Runs: \(stats.homeRuns)\n"
            summary += "• RBIs: \(stats.rbis)\n"
            summary += "• Walks: \(stats.walks)\n"
            summary += "• Strikeouts: \(stats.strikeouts)\n"
        }

        return summary
    }

    /// Checks if an athlete should be prompted to create or end a season
    /// - Parameter athlete: The athlete to check
    /// - Returns: A recommendation for season management
    static func checkSeasonStatus(for athlete: Athlete) -> SeasonRecommendation {
        // No seasons at all - recommend creating one
        if (athlete.seasons ?? []).isEmpty {
            return .createFirst
        }

        // No active season - recommend creating or reactivating
        guard let activeSeason = athlete.activeSeason else {
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
