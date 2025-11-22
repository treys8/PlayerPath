//
//  SeasonManager.swift
//  PlayerPath
//
//  Created by Assistant on 11/13/25.
//

import Foundation
import SwiftData

/// Utility for managing seasons and ensuring proper season linkage
@MainActor
struct SeasonManager {
    
    /// Ensures an athlete has an active season, creating a default one if needed
    /// - Parameters:
    ///   - athlete: The athlete to check
    ///   - modelContext: The SwiftData model context
    /// - Returns: The active season (existing or newly created)
    @discardableResult
    static func ensureActiveSeason(for athlete: Athlete, in modelContext: ModelContext) -> Season {
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
        
        // Create and activate new season
        let newSeason = Season(name: seasonName, startDate: now, sport: .baseball)
        newSeason.activate()
        newSeason.athlete = athlete
        
        if athlete.seasons == nil {
            athlete.seasons = []
        }
        athlete.seasons?.append(newSeason)
        
        modelContext.insert(newSeason)
        
        do {
            try modelContext.save()
            print("✅ Created default season: \(seasonName) for \(athlete.name)")
        } catch {
            print("❌ Error creating default season: \(error)")
        }
        
        return newSeason
    }
    
    /// Links a game to the athlete's active season
    /// - Parameters:
    ///   - game: The game to link
    ///   - athlete: The athlete
    ///   - modelContext: The SwiftData model context
    static func linkGameToActiveSeason(_ game: Game, for athlete: Athlete, in modelContext: ModelContext) {
        let activeSeason = ensureActiveSeason(for: athlete, in: modelContext)
        
        if game.season == nil {
            game.season = activeSeason
            if activeSeason.games == nil {
                activeSeason.games = []
            }
            activeSeason.games?.append(game)
            
            do {
                try modelContext.save()
                print("✅ Linked game to season: \(activeSeason.displayName)")
            } catch {
                print("❌ Error linking game to season: \(error)")
            }
        }
    }
    
    /// Links a practice to the athlete's active season
    /// - Parameters:
    ///   - practice: The practice to link
    ///   - athlete: The athlete
    ///   - modelContext: The SwiftData model context
    static func linkPracticeToActiveSeason(_ practice: Practice, for athlete: Athlete, in modelContext: ModelContext) {
        let activeSeason = ensureActiveSeason(for: athlete, in: modelContext)
        
        if practice.season == nil {
            practice.season = activeSeason
            if activeSeason.practices == nil {
                activeSeason.practices = []
            }
            activeSeason.practices?.append(practice)
            
            do {
                try modelContext.save()
                print("✅ Linked practice to season: \(activeSeason.displayName)")
            } catch {
                print("❌ Error linking practice to season: \(error)")
            }
        }
    }
    
    /// Links a video clip to the athlete's active season
    /// - Parameters:
    ///   - videoClip: The video clip to link
    ///   - athlete: The athlete
    ///   - modelContext: The SwiftData model context
    static func linkVideoToActiveSeason(_ videoClip: VideoClip, for athlete: Athlete, in modelContext: ModelContext) {
        let activeSeason = ensureActiveSeason(for: athlete, in: modelContext)
        
        if videoClip.season == nil {
            videoClip.season = activeSeason
            if activeSeason.videoClips == nil {
                activeSeason.videoClips = []
            }
            activeSeason.videoClips?.append(videoClip)
            
            do {
                try modelContext.save()
                print("✅ Linked video to season: \(activeSeason.displayName)")
            } catch {
                print("❌ Error linking video to season: \(error)")
            }
        }
    }
    
    /// Links a tournament to the athlete's active season
    /// - Parameters:
    ///   - tournament: The tournament to link
    ///   - athlete: The athlete (from tournament.athletes)
    ///   - modelContext: The SwiftData model context
    static func linkTournamentToActiveSeason(_ tournament: Tournament, for athlete: Athlete, in modelContext: ModelContext) {
        let activeSeason = ensureActiveSeason(for: athlete, in: modelContext)
        
        if tournament.season == nil {
            tournament.season = activeSeason
            if activeSeason.tournaments == nil {
                activeSeason.tournaments = []
            }
            activeSeason.tournaments?.append(tournament)
            
            do {
                try modelContext.save()
                print("✅ Linked tournament to season: \(activeSeason.displayName)")
            } catch {
                print("❌ Error linking tournament to season: \(error)")
            }
        }
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
        summary += "• Highlights: \(season.highlights.count)\n"
        summary += "• Tournaments: \((season.tournaments ?? []).count)\n\n"
        
        // Baseball stats if available
        if let stats = season.seasonStatistics, stats.atBats > 0 {
            summary += "⚾️ Batting Statistics\n"
            summary += "• Batting Average: \(String(format: ".%.3d", Int(stats.battingAverage * 1000)))\n"
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
        if let startDate = activeSeason.startDate {
            let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: Date())!
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
