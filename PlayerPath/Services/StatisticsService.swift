//
//  StatisticsService.swift
//  PlayerPath
//
//  Centralized service for calculating and managing athlete statistics
//

import Foundation
import SwiftData

@MainActor
final class StatisticsService {
    static let shared = StatisticsService()

    private init() {}

    // MARK: - Recalculate from Play Results

    /// Recalculates all statistics for an athlete from scratch by querying all play results
    /// Use this to ensure statistics are accurate after deletions or manual edits
    func recalculateAthleteStatistics(for athlete: Athlete, context: ModelContext) throws {
        print("StatisticsService: Recalculating statistics for athlete \(athlete.name)")

        // Ensure athlete has statistics model
        if athlete.statistics == nil {
            let stats = AthleteStatistics()
            stats.athlete = athlete
            athlete.statistics = stats
            context.insert(stats)
        }

        guard let stats = athlete.statistics else { return }

        // Reset all counts
        stats.atBats = 0
        stats.hits = 0
        stats.singles = 0
        stats.doubles = 0
        stats.triples = 0
        stats.homeRuns = 0
        stats.runs = 0
        stats.rbis = 0
        stats.walks = 0
        stats.strikeouts = 0
        stats.groundOuts = 0
        stats.flyOuts = 0
        stats.totalGames = 0

        // Get all completed games for this athlete
        let games = athlete.games ?? []
        let completedGames = games.filter { $0.isComplete }

        stats.totalGames = completedGames.count

        // Aggregate stats from all completed games
        for game in completedGames {
            if let gameStats = game.gameStats {
                stats.atBats += gameStats.atBats
                stats.hits += gameStats.hits
                stats.singles += gameStats.singles
                stats.doubles += gameStats.doubles
                stats.triples += gameStats.triples
                stats.homeRuns += gameStats.homeRuns
                stats.runs += gameStats.runs
                stats.rbis += gameStats.rbis
                stats.strikeouts += gameStats.strikeouts
                stats.walks += gameStats.walks
            }
        }

        // Add practice/standalone video play results (not associated with games)
        let videos = athlete.videoClips ?? []
        let practiceVideos = videos.filter { $0.game == nil } // Only non-game videos

        for video in practiceVideos {
            if let playResult = video.playResult {
                addPlayResultToStats(playResult.type, stats: stats)
            }
        }

        stats.updatedAt = Date()
        try context.save()

        print("StatisticsService: ✅ Recalculated - BA: \(stats.battingAverage.formatted(.number.precision(.fractionLength(3)))), OBP: \(stats.onBasePercentage.formatted(.number.precision(.fractionLength(3)))), OPS: \(stats.ops.formatted(.number.precision(.fractionLength(3))))")
    }

    /// Recalculates statistics for a specific season
    func recalculateSeasonStatistics(for season: Season, athlete: Athlete, context: ModelContext) throws {
        print("StatisticsService: Recalculating statistics for season \(season.displayName)")

        // Ensure season has statistics model
        if season.seasonStatistics == nil {
            let stats = AthleteStatistics()
            stats.season = season
            stats.athlete = athlete
            season.seasonStatistics = stats
            context.insert(stats)
        }

        guard let stats = season.seasonStatistics else { return }

        // Reset all counts
        stats.atBats = 0
        stats.hits = 0
        stats.singles = 0
        stats.doubles = 0
        stats.triples = 0
        stats.homeRuns = 0
        stats.runs = 0
        stats.rbis = 0
        stats.walks = 0
        stats.strikeouts = 0
        stats.groundOuts = 0
        stats.flyOuts = 0
        stats.totalGames = 0

        // Get all completed games for this season
        let games = season.games ?? []
        let completedGames = games.filter { $0.isComplete }

        stats.totalGames = completedGames.count

        // Aggregate stats from all completed games in this season
        for game in completedGames {
            if let gameStats = game.gameStats {
                stats.atBats += gameStats.atBats
                stats.hits += gameStats.hits
                stats.singles += gameStats.singles
                stats.doubles += gameStats.doubles
                stats.triples += gameStats.triples
                stats.homeRuns += gameStats.homeRuns
                stats.runs += gameStats.runs
                stats.rbis += gameStats.rbis
                stats.strikeouts += gameStats.strikeouts
                stats.walks += gameStats.walks
            }
        }

        // Add practice videos from this season
        let videos = season.videoClips ?? []
        let practiceVideos = videos.filter { $0.game == nil }

        for video in practiceVideos {
            if let playResult = video.playResult {
                addPlayResultToStats(playResult.type, stats: stats)
            }
        }

        stats.updatedAt = Date()
        try context.save()

        print("StatisticsService: ✅ Season stats - BA: \(stats.battingAverage.formatted(.number.precision(.fractionLength(3))))")
    }

    /// Recalculates game statistics from scratch based on video play results
    func recalculateGameStatistics(for game: Game, context: ModelContext) throws {
        print("StatisticsService: Recalculating statistics for game vs \(game.opponent)")

        // Ensure game has statistics model
        if game.gameStats == nil {
            let stats = GameStatistics()
            stats.game = game
            game.gameStats = stats
            context.insert(stats)
        }

        guard let stats = game.gameStats else { return }

        // Reset all counts
        stats.atBats = 0
        stats.hits = 0
        stats.singles = 0
        stats.doubles = 0
        stats.triples = 0
        stats.homeRuns = 0
        stats.runs = 0
        stats.rbis = 0
        stats.strikeouts = 0
        stats.walks = 0

        // Get all videos for this game and sum up play results
        let videos = game.videoClips ?? []

        for video in videos {
            if let playResult = video.playResult {
                let type = playResult.type

                if type.countsAsAtBat {
                    stats.atBats += 1
                }

                switch type {
                case .single:
                    stats.hits += 1
                    stats.singles += 1
                case .double:
                    stats.hits += 1
                    stats.doubles += 1
                case .triple:
                    stats.hits += 1
                    stats.triples += 1
                case .homeRun:
                    stats.hits += 1
                    stats.homeRuns += 1
                case .walk:
                    stats.walks += 1
                case .strikeout:
                    stats.strikeouts += 1
                case .groundOut, .flyOut:
                    break // Not tracked separately in GameStatistics
                }
            }
        }

        try context.save()

        print("StatisticsService: ✅ Game stats - Hits: \(stats.hits), AB: \(stats.atBats), BA: \(stats.battingAverage.formatted(.number.precision(.fractionLength(3))))")
    }

    // MARK: - Helper Methods

    private func addPlayResultToStats(_ type: PlayResultType, stats: AthleteStatistics) {
        if type.countsAsAtBat {
            stats.atBats += 1
        }

        switch type {
        case .single:
            stats.hits += 1
            stats.singles += 1
        case .double:
            stats.hits += 1
            stats.doubles += 1
        case .triple:
            stats.hits += 1
            stats.triples += 1
        case .homeRun:
            stats.hits += 1
            stats.homeRuns += 1
        case .walk:
            stats.walks += 1
        case .strikeout:
            stats.strikeouts += 1
        case .groundOut:
            stats.groundOuts += 1
        case .flyOut:
            stats.flyOuts += 1
        }
    }

    // MARK: - Statistics Formatting

    /// Format batting average with 3 decimal places (.XXX)
    func formatBattingAverage(_ value: Double) -> String {
        return value.formatted(.number.precision(.fractionLength(3)))
    }

    /// Format percentage with 3 decimal places (.XXX)
    func formatPercentage(_ value: Double) -> String {
        return value.formatted(.number.precision(.fractionLength(3)))
    }

    /// Format OPS with 3 decimal places (X.XXX)
    func formatOPS(_ value: Double) -> String {
        return value.formatted(.number.precision(.fractionLength(3)))
    }

    // MARK: - Statistics Summary

    /// Generate a text summary of athlete statistics
    func generateStatisticsSummary(for athlete: Athlete) -> String {
        guard let stats = athlete.statistics else {
            return "No statistics available"
        }

        return """
        Games: \(stats.totalGames)
        Batting Average: \(formatBattingAverage(stats.battingAverage))
        OBP: \(formatPercentage(stats.onBasePercentage))
        SLG: \(formatPercentage(stats.sluggingPercentage))
        OPS: \(formatOPS(stats.ops))
        Hits: \(stats.hits)/\(stats.atBats) (\(stats.singles)-\(stats.doubles)-\(stats.triples)-\(stats.homeRuns))
        Walks: \(stats.walks), Strikeouts: \(stats.strikeouts)
        """
    }
}
