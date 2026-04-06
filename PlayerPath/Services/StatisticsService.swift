//
//  StatisticsService.swift
//  PlayerPath
//
//  Centralized service for calculating and managing athlete statistics
//

import Foundation
import SwiftData
import os

private let statsLog = Logger(subsystem: "com.playerpath.app", category: "Statistics")

@MainActor
final class StatisticsService {
    static let shared = StatisticsService()

    private init() {}

    // MARK: - Recalculate from Play Results

    /// Recalculates all statistics for an athlete from scratch by querying all play results
    /// Use this to ensure statistics are accurate after deletions or manual edits
    func recalculateAthleteStatistics(for athlete: Athlete, context: ModelContext, skipSave: Bool = false) throws {
        statsLog.debug("Recalculating statistics for athlete \(athlete.name)")

        // Ensure athlete has a dedicated career statistics model.
        // Repair: if athlete.statistics was hijacked by a season stats object
        // (has season != nil), detach it and create a fresh career-only object.
        if let existing = athlete.statistics, existing.season != nil {
            existing.athlete = nil
            let careerStats = AthleteStatistics()
            careerStats.athlete = athlete
            athlete.statistics = careerStats
            context.insert(careerStats)
        } else if athlete.statistics == nil {
            let stats = AthleteStatistics()
            stats.athlete = athlete
            athlete.statistics = stats
            context.insert(stats)
        }

        guard let stats = athlete.statistics else { return }

        // Snapshot key fields before recalc to detect no-op saves
        let oldAtBats = stats.atBats
        let oldHits = stats.hits
        let oldTotalGames = stats.totalGames
        let oldStrikeouts = stats.strikeouts
        let oldWalks = stats.walks
        let oldTotalPitches = stats.totalPitches

        stats.resetAllCounts()

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
                stats.groundOuts += gameStats.groundOuts
                stats.flyOuts += gameStats.flyOuts
                stats.hitByPitches += gameStats.hitByPitches
                stats.totalPitches += gameStats.totalPitches
                stats.balls += gameStats.balls
                stats.strikes += gameStats.strikes
                stats.wildPitches += gameStats.wildPitches
                stats.pitchingStrikeouts += gameStats.pitchingStrikeouts
                stats.pitchingWalks += gameStats.pitchingWalks
                stats.fastballPitchCount += gameStats.fastballPitchCount
                stats.fastballSpeedTotal += gameStats.fastballSpeedTotal
                stats.offspeedPitchCount += gameStats.offspeedPitchCount
                stats.offspeedSpeedTotal += gameStats.offspeedSpeedTotal
            }
        }

        // Add practice/standalone video play results (not associated with games)
        let videos = athlete.videoClips ?? []
        let practiceVideos = videos.filter { $0.game == nil } // Only non-game videos

        for video in practiceVideos {
            if let playResult = video.playResult {
                addPlayResultToStats(playResult.type, stats: stats, pitchType: video.pitchType, pitchSpeed: video.pitchSpeed)
            } else {
                // Clip has a pitch speed but no tagged play result — still contribute to velocity aggregates.
                stats.applyPitchVelocity(pitchType: video.pitchType, pitchSpeed: video.pitchSpeed)
            }
        }

        // Check if anything actually changed before touching updatedAt / saving
        let statsChanged = stats.atBats != oldAtBats
            || stats.hits != oldHits
            || stats.totalGames != oldTotalGames
            || stats.strikeouts != oldStrikeouts
            || stats.walks != oldWalks
            || stats.totalPitches != oldTotalPitches

        if statsChanged {
            stats.updatedAt = Date()
        }

        statsLog.info("Recalculated - BA: \(stats.battingAverage.formatted(.number.precision(.fractionLength(3)))), OBP: \(stats.onBasePercentage.formatted(.number.precision(.fractionLength(3)))), OPS: \(stats.ops.formatted(.number.precision(.fractionLength(3))))")

        // Also recalculate season statistics so they stay in sync
        for season in athlete.seasons ?? [] {
            try recalculateSeasonStatistics(for: season, athlete: athlete, context: context, skipSave: true)
        }

        // Clean up orphaned AthleteStatistics left behind by the old bug
        // where season stats stole the athlete relationship
        let allStatsDescriptor = FetchDescriptor<AthleteStatistics>()
        if let allStats = try? context.fetch(allStatsDescriptor) {
            for stat in allStats where stat.athlete == nil && stat.season == nil {
                context.delete(stat)
            }
        }

        if !skipSave && context.hasChanges {
            try context.save()
        }
    }

    /// Recalculates statistics for a specific season
    func recalculateSeasonStatistics(for season: Season, athlete: Athlete, context: ModelContext, skipSave: Bool = false) throws {
        statsLog.debug("Recalculating statistics for season \(season.displayName)")

        // Ensure season has statistics model
        // Do NOT set stats.athlete here — Athlete.statistics is a one-to-one
        // inverse on AthleteStatistics.athlete. Setting it on season stats
        // would steal the relationship from the career stats object.
        if season.seasonStatistics == nil {
            let stats = AthleteStatistics()
            stats.season = season
            season.seasonStatistics = stats
            context.insert(stats)
        }

        guard let stats = season.seasonStatistics else { return }

        stats.resetAllCounts()

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
                stats.groundOuts += gameStats.groundOuts
                stats.flyOuts += gameStats.flyOuts
                stats.hitByPitches += gameStats.hitByPitches
                stats.totalPitches += gameStats.totalPitches
                stats.balls += gameStats.balls
                stats.strikes += gameStats.strikes
                stats.wildPitches += gameStats.wildPitches
                stats.pitchingStrikeouts += gameStats.pitchingStrikeouts
                stats.pitchingWalks += gameStats.pitchingWalks
                stats.fastballPitchCount += gameStats.fastballPitchCount
                stats.fastballSpeedTotal += gameStats.fastballSpeedTotal
                stats.offspeedPitchCount += gameStats.offspeedPitchCount
                stats.offspeedSpeedTotal += gameStats.offspeedSpeedTotal
            }
        }

        // Add practice videos from this season
        let videos = season.videoClips ?? []
        let practiceVideos = videos.filter { $0.game == nil }

        for video in practiceVideos {
            if let playResult = video.playResult {
                addPlayResultToStats(playResult.type, stats: stats, pitchType: video.pitchType, pitchSpeed: video.pitchSpeed)
            } else {
                stats.applyPitchVelocity(pitchType: video.pitchType, pitchSpeed: video.pitchSpeed)
            }
        }

        stats.updatedAt = Date()

        if !skipSave {
            try context.save()
        }

        statsLog.info("Season stats - BA: \(stats.battingAverage.formatted(.number.precision(.fractionLength(3))))")
    }

    /// Recalculates game statistics from scratch based on video play results
    func recalculateGameStatistics(for game: Game, context: ModelContext) throws {
        statsLog.debug("Recalculating statistics for game vs \(game.opponent)")

        // Ensure game has statistics model
        if game.gameStats == nil {
            let stats = GameStatistics()
            stats.game = game
            game.gameStats = stats
            context.insert(stats)
        }

        guard let stats = game.gameStats else { return }

        let oldHits = stats.hits
        let oldAtBats = stats.atBats
        let oldTotalPitches = stats.totalPitches

        stats.resetAllCounts()

        // Get all videos for this game and sum up play results
        let videos = game.videoClips ?? []

        for video in videos {
            if let playResult = video.playResult {
                stats.applyPlayResult(playResult.type, pitchType: video.pitchType, pitchSpeed: video.pitchSpeed)
            } else {
                // Clip has a pitch speed but no tagged play result — still contribute to velocity aggregates.
                stats.applyPitchVelocity(pitchType: video.pitchType, pitchSpeed: video.pitchSpeed)
            }
        }

        if stats.hits != oldHits || stats.atBats != oldAtBats || stats.totalPitches != oldTotalPitches {
            if context.hasChanges { try context.save() }
        }

        statsLog.info("Game stats - Hits: \(stats.hits), AB: \(stats.atBats), BA: \(stats.battingAverage.formatted(.number.precision(.fractionLength(3))))")
    }

    // MARK: - Helper Methods

    private func addPlayResultToStats(_ type: PlayResultType, stats: AthleteStatistics, pitchType: String? = nil, pitchSpeed: Double? = nil) {
        stats.applyPlayResult(type, pitchType: pitchType, pitchSpeed: pitchSpeed)
    }

    // MARK: - Statistics Formatting

    /// Format batting average in baseball style: ".325" for values < 1.0, "1.400" for SLG/OPS >= 1.0
    func formatBattingAverage(_ value: Double) -> String {
        guard !value.isNaN, !value.isInfinite else { return ".000" }
        // SLG can exceed 1.0; show full decimal in that case
        if value >= 1.0 { return String(format: "%.3f", value) }
        let thousandths = Int((value * 1000).rounded())
        guard thousandths > 0 else { return ".000" }
        return String(format: ".%03d", thousandths)
    }

    /// Format percentage in baseball style (.XXX) — same convention as batting average
    func formatPercentage(_ value: Double) -> String {
        return formatBattingAverage(value)
    }

    /// Format OPS with 3 decimal places (X.XXX)
    func formatOPS(_ value: Double) -> String {
        return value.formatted(.number.precision(.fractionLength(3)))
    }

}
