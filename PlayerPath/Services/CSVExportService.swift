//
//  CSVExportService.swift
//  PlayerPath
//
//  Service for exporting statistics and data to CSV format
//

import Foundation
import SwiftData

@MainActor
final class CSVExportService {
    static let shared = CSVExportService()

    private init() {}

    // MARK: - Athlete Statistics Export

    /// Export athlete statistics to CSV format
    /// - Parameter athlete: The athlete to export statistics for
    /// - Returns: CSV string ready for file export
    func exportAthleteStatistics(for athlete: Athlete) -> String {
        var csv = "Athlete Statistics Export\n"
        csv += "Generated: \(Date().formatted(date: .long, time: .standard))\n\n"

        // Athlete info
        csv += "Athlete Name,\(escapeCSV(athlete.name))\n"
        if let createdAt = athlete.createdAt {
            csv += "Profile Created,\(createdAt.formatted(date: .abbreviated, time: .omitted))\n"
        }
        csv += "\n"

        // Overall statistics
        if let stats = athlete.statistics {
            csv += "Overall Career Statistics\n"
            csv += "Metric,Value\n"
            csv += "Total Games,\(stats.totalGames)\n"
            csv += "At Bats,\(stats.atBats)\n"
            csv += "Hits,\(stats.hits)\n"
            csv += "Singles,\(stats.singles)\n"
            csv += "Doubles,\(stats.doubles)\n"
            csv += "Triples,\(stats.triples)\n"
            csv += "Home Runs,\(stats.homeRuns)\n"
            csv += "Runs,\(stats.runs)\n"
            csv += "RBIs,\(stats.rbis)\n"
            csv += "Walks,\(stats.walks)\n"
            csv += "Strikeouts,\(stats.strikeouts)\n"
            csv += "Ground Outs,\(stats.groundOuts)\n"
            csv += "Fly Outs,\(stats.flyOuts)\n"
            csv += "Batting Average,\(StatisticsService.shared.formatBattingAverage(stats.battingAverage))\n"
            csv += "On-Base Percentage,\(StatisticsService.shared.formatPercentage(stats.onBasePercentage))\n"
            csv += "Slugging Percentage,\(StatisticsService.shared.formatPercentage(stats.sluggingPercentage))\n"
            csv += "OPS,\(StatisticsService.shared.formatOPS(stats.ops))\n"
            csv += "\n"
        }

        // Season-by-season breakdown
        let seasons = athlete.seasons ?? []
        if !seasons.isEmpty {
            csv += "Season-by-Season Statistics\n"
            csv += "Season,Games,AB,H,1B,2B,3B,HR,R,RBI,BB,K,AVG,OBP,SLG,OPS\n"

            for season in seasons.sorted(by: { ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast) }) {
                if let seasonStats = season.seasonStatistics {
                    csv += "\(escapeCSV(season.displayName)),"
                    csv += "\(seasonStats.totalGames),"
                    csv += "\(seasonStats.atBats),"
                    csv += "\(seasonStats.hits),"
                    csv += "\(seasonStats.singles),"
                    csv += "\(seasonStats.doubles),"
                    csv += "\(seasonStats.triples),"
                    csv += "\(seasonStats.homeRuns),"
                    csv += "\(seasonStats.runs),"
                    csv += "\(seasonStats.rbis),"
                    csv += "\(seasonStats.walks),"
                    csv += "\(seasonStats.strikeouts),"
                    csv += "\(StatisticsService.shared.formatBattingAverage(seasonStats.battingAverage)),"
                    csv += "\(StatisticsService.shared.formatPercentage(seasonStats.onBasePercentage)),"
                    csv += "\(StatisticsService.shared.formatPercentage(seasonStats.sluggingPercentage)),"
                    csv += "\(StatisticsService.shared.formatOPS(seasonStats.ops))\n"
                }
            }
            csv += "\n"
        }

        return csv
    }

    // MARK: - Game Log Export

    /// Export game-by-game log to CSV format
    /// - Parameters:
    ///   - athlete: The athlete whose games to export
    ///   - season: Optional season filter (nil = all games)
    /// - Returns: CSV string ready for file export
    func exportGameLog(for athlete: Athlete, season: Season? = nil) -> String {
        var csv = "Game Log Export\n"
        csv += "Generated: \(Date().formatted(date: .long, time: .standard))\n"
        csv += "Athlete: \(escapeCSV(athlete.name))\n"
        if let season = season {
            csv += "Season: \(escapeCSV(season.displayName))\n"
        }
        csv += "\n"

        // Header
        csv += "Date,Opponent,Result,AB,H,1B,2B,3B,HR,R,RBI,BB,K,AVG,OBP,SLG,OPS\n"

        // Get games
        var games = athlete.games ?? []
        if let season = season {
            games = games.filter { $0.season?.id == season.id }
        }

        // Sort by date descending
        games.sort { ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast) }

        // Export each game
        for game in games {
            guard game.isComplete, let gameStats = game.gameStats else { continue }

            let dateStr = game.date?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown"
            let opponent = escapeCSV(game.opponent)
            let result = game.isComplete ? "Complete" : "In Progress"

            csv += "\(dateStr),"
            csv += "\(opponent),"
            csv += "\(result),"
            csv += "\(gameStats.atBats),"
            csv += "\(gameStats.hits),"
            csv += "\(gameStats.singles),"
            csv += "\(gameStats.doubles),"
            csv += "\(gameStats.triples),"
            csv += "\(gameStats.homeRuns),"
            csv += "\(gameStats.runs),"
            csv += "\(gameStats.rbis),"
            csv += "\(gameStats.walks),"
            csv += "\(gameStats.strikeouts),"
            csv += "\(StatisticsService.shared.formatBattingAverage(gameStats.battingAverage)),"
            csv += "\(StatisticsService.shared.formatPercentage(gameStats.onBasePercentage)),"
            csv += "\(StatisticsService.shared.formatPercentage(gameStats.sluggingPercentage)),"
            csv += "\(StatisticsService.shared.formatOPS(gameStats.ops))\n"
        }

        return csv
    }

    // MARK: - Play-by-Play Export

    /// Export play-by-play data from video clips
    /// - Parameters:
    ///   - athlete: The athlete whose plays to export
    ///   - season: Optional season filter
    ///   - game: Optional game filter
    /// - Returns: CSV string ready for file export
    func exportPlayByPlay(for athlete: Athlete, season: Season? = nil, game: Game? = nil) -> String {
        var csv = "Play-by-Play Export\n"
        csv += "Generated: \(Date().formatted(date: .long, time: .standard))\n"
        csv += "Athlete: \(escapeCSV(athlete.name))\n"
        if let season = season {
            csv += "Season: \(escapeCSV(season.displayName))\n"
        }
        if let game = game {
            csv += "Game: vs \(escapeCSV(game.opponent))\n"
        }
        csv += "\n"

        // Header
        csv += "Date,Context,Play Result,Is Highlight,Video File\n"

        // Get video clips
        var clips = athlete.videoClips ?? []
        if let season = season {
            clips = clips.filter { $0.season?.id == season.id }
        }
        if let game = game {
            clips = clips.filter { $0.game?.id == game.id }
        }

        // Sort by date descending
        clips.sort { ($0.createdAt ?? Date.distantPast) > ($1.createdAt ?? Date.distantPast) }

        // Export each clip
        for clip in clips {
            let dateStr = clip.createdAt?.formatted(date: .abbreviated, time: .standard) ?? "Unknown"

            var context = "Practice"
            if let game = clip.game {
                context = "vs \(escapeCSV(game.opponent))"
            }

            let playResult = clip.playResult?.type.displayName ?? "Unrecorded"
            let isHighlight = clip.isHighlight ? "Yes" : "No"
            let fileName = escapeCSV(clip.fileName)

            csv += "\(dateStr),"
            csv += "\(context),"
            csv += "\(playResult),"
            csv += "\(isHighlight),"
            csv += "\(fileName)\n"
        }

        return csv
    }

    // MARK: - Season Summary Export

    /// Export comprehensive season summary
    /// - Parameter season: The season to export
    /// - Returns: CSV string ready for file export
    func exportSeasonSummary(for season: Season) -> String {
        var csv = "Season Summary Export\n"
        csv += "Generated: \(Date().formatted(date: .long, time: .standard))\n\n"

        // Season info
        csv += "Season Name,\(escapeCSV(season.displayName))\n"
        if let startDate = season.startDate {
            csv += "Start Date,\(startDate.formatted(date: .abbreviated, time: .omitted))\n"
        }
        if let endDate = season.endDate {
            csv += "End Date,\(endDate.formatted(date: .abbreviated, time: .omitted))\n"
        }
        csv += "Status,\(season.isActive ? "Active" : "Completed")\n"
        csv += "Sport,\(season.sport.displayName)\n"
        csv += "\n"

        // Season statistics
        if let stats = season.seasonStatistics {
            csv += "Season Statistics\n"
            csv += "Metric,Value\n"
            csv += "Total Games,\(stats.totalGames)\n"
            csv += "At Bats,\(stats.atBats)\n"
            csv += "Hits,\(stats.hits)\n"
            csv += "Batting Average,\(StatisticsService.shared.formatBattingAverage(stats.battingAverage))\n"
            csv += "On-Base Percentage,\(StatisticsService.shared.formatPercentage(stats.onBasePercentage))\n"
            csv += "Slugging Percentage,\(StatisticsService.shared.formatPercentage(stats.sluggingPercentage))\n"
            csv += "OPS,\(StatisticsService.shared.formatOPS(stats.ops))\n"
            csv += "\n"
        }

        // Games list
        let games = season.games ?? []
        if !games.isEmpty {
            csv += "Games in Season\n"
            csv += "Date,Opponent,Status,AB,H,AVG\n"

            for game in games.sorted(by: { ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast) }) {
                let dateStr = game.date?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown"
                let opponent = escapeCSV(game.opponent)
                let status = game.isComplete ? "Complete" : (game.isLive ? "Live" : "Scheduled")

                csv += "\(dateStr),\(opponent),\(status)"

                if let gameStats = game.gameStats {
                    csv += ",\(gameStats.atBats),\(gameStats.hits),\(StatisticsService.shared.formatBattingAverage(gameStats.battingAverage))"
                } else {
                    csv += ",,,"
                }

                csv += "\n"
            }
        }

        return csv
    }

    // MARK: - Helper Methods

    /// Escape CSV values that contain special characters
    private func escapeCSV(_ value: String) -> String {
        // If value contains comma, quote, or newline, wrap in quotes and escape internal quotes
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    /// Save CSV string to temporary file and return URL
    func saveCSVToTemporaryFile(_ csv: String, filename: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(filename)

        try csv.write(to: fileURL, atomically: true, encoding: .utf8)

        return fileURL
    }
}
