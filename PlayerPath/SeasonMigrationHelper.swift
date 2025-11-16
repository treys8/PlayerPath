//
//  SeasonMigrationHelper.swift
//  PlayerPath
//
//  Created by Assistant on 11/13/25.
//

import Foundation
import SwiftData

/// Helper for migrating existing data to seasons for users upgrading to the season system
@MainActor
struct SeasonMigrationHelper {
    
    /// Migrates all existing games, practices, and videos for an athlete to appropriate seasons
    /// This should be called once per athlete when they first upgrade to the season system
    /// - Parameters:
    ///   - athlete: The athlete whose data needs migration
    ///   - modelContext: The SwiftData model context
    static func migrateExistingData(for athlete: Athlete, in modelContext: ModelContext) async {
        print("🔄 Starting season migration for \(athlete.name)...")
        
        // Check if athlete already has seasons - if so, skip migration
        if !athlete.seasons.isEmpty {
            print("⏭️ Athlete already has seasons, skipping migration")
            return
        }
        
        // Collect all items without seasons
        let gamesWithoutSeason = athlete.games.filter { $0.season == nil }
        let practicesWithoutSeason = athlete.practices.filter { $0.season == nil }
        let videosWithoutSeason = athlete.videoClips.filter { $0.season == nil }
        let tournamentsWithoutSeason = athlete.tournaments.filter { $0.season == nil }
        
        guard !gamesWithoutSeason.isEmpty || !practicesWithoutSeason.isEmpty || 
              !videosWithoutSeason.isEmpty || !tournamentsWithoutSeason.isEmpty else {
            print("✅ No data to migrate")
            return
        }
        
        print("📊 Found data to migrate:")
        print("  • \(gamesWithoutSeason.count) games")
        print("  • \(practicesWithoutSeason.count) practices")
        print("  • \(videosWithoutSeason.count) videos")
        print("  • \(tournamentsWithoutSeason.count) tournaments")
        
        // Group items by date ranges to create appropriate seasons
        let seasons = createSeasonsFromData(
            games: gamesWithoutSeason,
            practices: practicesWithoutSeason,
            videos: videosWithoutSeason,
            tournaments: tournamentsWithoutSeason
        )
        
        // Create season objects and link data
        for (seasonInfo, items) in seasons {
            let season = Season(
                name: seasonInfo.name,
                startDate: seasonInfo.startDate,
                sport: .baseball
            )
            
            // Make most recent season active
            if seasonInfo.isRecent {
                season.activate()
            } else {
                season.archive(endDate: seasonInfo.endDate)
            }
            
            season.athlete = athlete
            athlete.seasons.append(season)
            
            // Link all items to this season
            for game in items.games {
                game.season = season
                season.games.append(game)
            }
            
            for practice in items.practices {
                practice.season = season
                season.practices.append(practice)
            }
            
            for video in items.videos {
                video.season = season
                season.videoClips.append(video)
            }
            
            for tournament in items.tournaments {
                tournament.season = season
                season.tournaments.append(tournament)
            }
            
            modelContext.insert(season)
            
            print("✅ Created season: \(season.displayName) with \(items.totalItems) items")
        }
        
        // Save everything
        do {
            try modelContext.save()
            print("✅ Migration complete for \(athlete.name)")
        } catch {
            print("❌ Migration error: \(error)")
        }
    }
    
    /// Groups data by date ranges to intelligently create seasons
    private static func createSeasonsFromData(
        games: [Game],
        practices: [Practice],
        videos: [VideoClip],
        tournaments: [Tournament]
    ) -> [(seasonInfo: SeasonInfo, items: SeasonItems)] {
        
        // Collect all dates
        var allDates: [Date] = []
        allDates += games.compactMap { $0.date }
        allDates += practices.compactMap { $0.date }
        allDates += videos.compactMap { $0.createdAt }
        allDates += tournaments.compactMap { $0.date }
        
        guard !allDates.isEmpty else {
            // No dates available, create a single default season
            let now = Date()
            return [(
                seasonInfo: SeasonInfo(
                    name: "All Data",
                    startDate: now,
                    endDate: now,
                    isRecent: true
                ),
                items: SeasonItems(
                    games: games,
                    practices: practices,
                    videos: videos,
                    tournaments: tournaments
                )
            )]
        }
        
        allDates.sort()
        
        // Group by year and season (Spring/Fall)
        var seasonGroups: [SeasonKey: SeasonItems] = [:]
        let calendar = Calendar.current
        
        // Process games
        for game in games {
            guard let date = game.date else { continue }
            let key = seasonKey(for: date, calendar: calendar)
            seasonGroups[key, default: SeasonItems()].games.append(game)
        }
        
        // Process practices
        for practice in practices {
            guard let date = practice.date else { continue }
            let key = seasonKey(for: date, calendar: calendar)
            seasonGroups[key, default: SeasonItems()].practices.append(practice)
        }
        
        // Process videos
        for video in videos {
            guard let date = video.createdAt else { continue }
            let key = seasonKey(for: date, calendar: calendar)
            seasonGroups[key, default: SeasonItems()].videos.append(video)
        }
        
        // Process tournaments
        for tournament in tournaments {
            guard let date = tournament.date else { continue }
            let key = seasonKey(for: date, calendar: calendar)
            seasonGroups[key, default: SeasonItems()].tournaments.append(tournament)
        }
        
        // Convert to sorted array
        let sortedKeys = seasonGroups.keys.sorted { $0.year > $1.year || ($0.year == $1.year && $0.season > $1.season) }
        
        return sortedKeys.map { key in
            let items = seasonGroups[key]!
            let isRecent = key == sortedKeys.first
            
            // Determine start and end dates from actual data
            var dates: [Date] = []
            dates += items.games.compactMap { $0.date }
            dates += items.practices.compactMap { $0.date }
            dates += items.videos.compactMap { $0.createdAt }
            dates += items.tournaments.compactMap { $0.date }
            dates.sort()
            
            let startDate = dates.first ?? Date()
            let endDate = dates.last ?? Date()
            
            return (
                seasonInfo: SeasonInfo(
                    name: "\(key.seasonName) \(key.year)",
                    startDate: startDate,
                    endDate: isRecent ? nil : endDate,
                    isRecent: isRecent
                ),
                items: items
            )
        }
    }
    
    private static func seasonKey(for date: Date, calendar: Calendar) -> SeasonKey {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        
        let seasonType: SeasonType
        if month >= 2 && month <= 6 {
            seasonType = .spring
        } else if month >= 7 && month <= 10 {
            seasonType = .fall
        } else if month == 1 {
            seasonType = .winter
        } else {
            seasonType = .winter
        }
        
        return SeasonKey(year: year, season: seasonType)
    }
    
    struct SeasonInfo {
        let name: String
        let startDate: Date
        let endDate: Date?
        let isRecent: Bool
    }
    
    struct SeasonItems {
        var games: [Game] = []
        var practices: [Practice] = []
        var videos: [VideoClip] = []
        var tournaments: [Tournament] = []
        
        var totalItems: Int {
            games.count + practices.count + videos.count + tournaments.count
        }
    }
    
    struct SeasonKey: Hashable {
        let year: Int
        let season: SeasonType
        
        var seasonName: String {
            season.rawValue
        }
    }
    
    enum SeasonType: String, Comparable {
        case spring = "Spring"
        case fall = "Fall"
        case winter = "Winter"
        
        static func < (lhs: SeasonType, rhs: SeasonType) -> Bool {
            let order: [SeasonType] = [.winter, .spring, .fall]
            guard let lhsIndex = order.firstIndex(of: lhs),
                  let rhsIndex = order.firstIndex(of: rhs) else {
                return false
            }
            return lhsIndex < rhsIndex
        }
    }
    
    /// Quick check to see if an athlete needs migration
    /// - Parameter athlete: The athlete to check
    /// - Returns: True if migration is needed
    static func needsMigration(for athlete: Athlete) -> Bool {
        // If athlete has no seasons but has data, they need migration
        if athlete.seasons.isEmpty {
            let hasData = !athlete.games.isEmpty || 
                         !athlete.practices.isEmpty || 
                         !athlete.videoClips.isEmpty ||
                         !athlete.tournaments.isEmpty
            return hasData
        }
        
        // Check if there's any data without a season
        let hasUnlinkedData = athlete.games.contains(where: { $0.season == nil }) ||
                             athlete.practices.contains(where: { $0.season == nil }) ||
                             athlete.videoClips.contains(where: { $0.season == nil }) ||
                             athlete.tournaments.contains(where: { $0.season == nil })
        
        return hasUnlinkedData
    }
}
