//
//  SEASON_INTEGRATION_EXAMPLES.swift
//  PlayerPath
//
//  Created by Assistant on 11/13/25.
//
//  This file contains example code showing how to integrate Season Management
//  into your existing views. Copy and adapt these examples as needed.

import SwiftUI
import SwiftData

// MARK: - Example 1: Add Season Management to Profile Settings

/*
 In ProfileView.swift, add this to the settingsSection:
 
 private var settingsSection: some View {
     Section("Settings") {
         NavigationLink(destination: SettingsView(user: user)) {
             Label("Settings", systemImage: "gearshape")
         }
         
         // ADD THIS: Season Management for selected athlete
         if let athlete = selectedAthlete {
             NavigationLink(destination: SeasonManagementView(athlete: athlete)) {
                 Label("Manage Seasons", systemImage: "calendar")
             }
         }
         
         NavigationLink(destination: SecuritySettingsView(authManager: authManager)) {
             Label("Security Settings", systemImage: "lock.shield")
         }
         // ... rest of settings
     }
 }
*/

// MARK: - Example 2: Add Season Indicator to Dashboard

/*
 In your main dashboard/athlete view, add at the top:
 
 struct DashboardView: View {
     let athlete: Athlete
     @Environment(\.modelContext) private var modelContext
     
     var body: some View {
         VStack {
             // ADD THIS: Season indicator at top
             SeasonIndicatorView(athlete: athlete)
                 .padding(.horizontal)
                 .padding(.top, 8)
             
             // ADD THIS: Season recommendations if needed
             let recommendation = SeasonManager.checkSeasonStatus(for: athlete)
             SeasonRecommendationBanner(athlete: athlete, recommendation: recommendation)
                 .padding(.horizontal)
             
             // Your existing dashboard content
             ScrollView {
                 // ... existing content
             }
         }
     }
 }
*/

// MARK: - Example 3: Link Games to Seasons

/*
 In GamesView.swift (or wherever you create games), update your createGame function:
 
 private func createGame() {
     guard let athlete = athlete else { return }
     
     let newGame = Game(date: newGameDate, opponent: newGameOpponent)
     newGame.athlete = athlete
     newGame.isLive = makeGameLive
     newGame.tournament = selectedTournament
     
     athlete.games.append(newGame)
     modelContext.insert(newGame)
     
     // ADD THIS: Link to active season
     SeasonManager.linkGameToActiveSeason(newGame, for: athlete, in: modelContext)
     
     // If part of tournament, link tournament too
     if let tournament = selectedTournament {
         SeasonManager.linkTournamentToActiveSeason(tournament, for: athlete, in: modelContext)
     }
     
     do {
         try modelContext.save()
         showingGameCreation = false
         newGameOpponent = ""
         newGameDate = Date()
         selectedTournament = nil
         makeGameLive = false
     } catch {
         errorMessage = error.localizedDescription
         showingError = true
     }
 }
*/

// MARK: - Example 4: Link Practices to Seasons

/*
 When creating a practice:
 
 private func createPractice() {
     guard let athlete = athlete else { return }
     
     let newPractice = Practice(date: practiceDate)
     newPractice.athlete = athlete
     
     athlete.practices.append(newPractice)
     modelContext.insert(newPractice)
     
     // ADD THIS: Link to active season
     SeasonManager.linkPracticeToActiveSeason(newPractice, for: athlete, in: modelContext)
     
     do {
         try modelContext.save()
         // ... success handling
     } catch {
         // ... error handling
     }
 }
*/

// MARK: - Example 5: Link Videos to Seasons

/*
 When saving a recorded video:
 
 func saveRecordedVideo(fileName: String, filePath: String, athlete: Athlete, game: Game?, practice: Practice?) {
     let videoClip = VideoClip(fileName: fileName, filePath: filePath)
     videoClip.athlete = athlete
     videoClip.game = game
     videoClip.practice = practice
     videoClip.createdAt = Date()
     
     athlete.videoClips.append(videoClip)
     modelContext.insert(videoClip)
     
     // ADD THIS: Link to active season
     SeasonManager.linkVideoToActiveSeason(videoClip, for: athlete, in: modelContext)
     
     do {
         try modelContext.save()
         print("✅ Video saved and linked to season")
     } catch {
         print("❌ Error saving video: \(error)")
     }
 }
*/

// MARK: - Example 6: Add Migration Check on App Launch

/*
 In PlayerPathMainView or your root content view:
 
 struct PlayerPathMainView: View {
     @Query private var athletes: [Athlete]
     @Environment(\.modelContext) private var modelContext
     @State private var hasMigratedSeasons = false
     
     var body: some View {
         TabView {
             // Your tabs
         }
         .task {
             if !hasMigratedSeasons {
                 await performSeasonMigration()
                 hasMigratedSeasons = true
             }
         }
     }
     
     private func performSeasonMigration() async {
         for athlete in athletes {
             if SeasonMigrationHelper.needsMigration(for: athlete) {
                 print("🔄 Migrating seasons for \(athlete.name)...")
                 await SeasonMigrationHelper.migrateExistingData(for: athlete, in: modelContext)
             }
         }
     }
 }
*/

// MARK: - Example 7: Filter Games by Season

/*
 Add season filtering to your games list:
 
 struct GamesView: View {
     let athlete: Athlete
     @State private var showAllSeasons = false
     
     private var filteredGames: [Game] {
         if showAllSeasons {
             return athlete.games
         } else if let activeSeason = athlete.activeSeason {
             // Show only active season games
             return athlete.games.filter { $0.season?.id == activeSeason.id }
         } else {
             return athlete.games
         }
     }
     
     var body: some View {
         List {
             // ADD THIS: Season filter toggle
             Section {
                 Toggle("Show All Seasons", isOn: $showAllSeasons)
             }
             
             // Use filtered games
             ForEach(filteredGames) { game in
                 GameRow(game: game)
             }
         }
         .navigationTitle("Games")
     }
 }
*/

// MARK: - Example 8: Show Season in Game Detail

/*
 In GameDetailView, add season info:
 
 Section("Game Information") {
     LabeledContent("Opponent", value: game.opponent)
     
     if let date = game.date {
         LabeledContent("Date", value: date.formatted(date: .long, time: .omitted))
     }
     
     // ADD THIS: Show which season this game belongs to
     if let season = game.season {
         LabeledContent("Season") {
             HStack {
                 Image(systemName: season.sport.icon)
                 Text(season.displayName)
             }
         }
     }
 }
*/

// MARK: - Example 9: Show Season Stats in Profile

/*
 Add season statistics to athlete profile:
 
 struct AthleteStatsView: View {
     let athlete: Athlete
     
     var body: some View {
         List {
             // Current season stats
             if let activeSeason = athlete.activeSeason,
                let stats = activeSeason.seasonStatistics {
                 Section("\(activeSeason.displayName) Stats") {
                     LabeledContent("Games", value: "\(activeSeason.totalGames)")
                     LabeledContent("Batting Avg", value: String(format: ".%.3d", Int(stats.battingAverage * 1000)))
                     LabeledContent("Home Runs", value: "\(stats.homeRuns)")
                 }
             }
             
             // Past seasons comparison
             if !athlete.archivedSeasons.isEmpty {
                 Section("Season History") {
                     ForEach(athlete.archivedSeasons.prefix(3)) { season in
                         NavigationLink {
                             SeasonDetailView(season: season, athlete: athlete)
                         } label: {
                             VStack(alignment: .leading) {
                                 Text(season.displayName)
                                 Text("\(season.totalGames) games")
                                     .font(.caption)
                                     .foregroundStyle(.secondary)
                             }
                         }
                     }
                 }
             }
         }
     }
 }
*/

// MARK: - Example 10: First-Time User Onboarding

/*
 Show season creation prompt for new users:
 
 struct AthleteDetailView: View {
     let athlete: Athlete
     @State private var showingSeasonPrompt = false
     
     var body: some View {
         VStack {
             if athlete.seasons.isEmpty && athlete.games.isEmpty {
                 // First time user - show season creation prompt
                 CreateFirstSeasonPrompt(athlete: athlete)
             } else if athlete.activeSeason == nil {
                 // Has old data but no active season
                 VStack(spacing: 16) {
                     Text("No Active Season")
                         .font(.headline)
                     
                     Button("Create Season") {
                         showingSeasonPrompt = true
                     }
                     .buttonStyle(.borderedProminent)
                 }
                 .padding()
             } else {
                 // Normal content
                 DashboardContent(athlete: athlete)
             }
         }
         .sheet(isPresented: $showingSeasonPrompt) {
             NavigationStack {
                 SeasonManagementView(athlete: athlete)
             }
         }
     }
 }
*/

// MARK: - Example 11: Toolbar Season Indicator

/*
 Add season indicator to navigation toolbar:
 
 struct GamesView: View {
     let athlete: Athlete
     
     var body: some View {
         List {
             // Games list
         }
         .navigationTitle("Games")
         .toolbar {
             ToolbarItem(placement: .principal) {
                 SeasonIndicatorView(athlete: athlete)
             }
         }
     }
 }
*/

// MARK: - Example 12: Context Menu for Season Actions

/*
 Add quick season actions to context menus:
 
 GameRow(game: game)
     .contextMenu {
         // Existing menu items
         Button(action: { /* ... */ }) {
             Label("Edit Game", systemImage: "pencil")
         }
         
         Divider()
         
         // ADD THIS: Season-related actions
         if let season = game.season {
             Button(action: {
                 // Navigate to season detail
             }) {
                 Label("View \(season.displayName)", systemImage: "calendar")
             }
         } else {
             Button(action: {
                 // Link to active season
                 if let athlete = game.athlete {
                     SeasonManager.linkGameToActiveSeason(game, for: athlete, in: modelContext)
                 }
             }) {
                 Label("Add to Active Season", systemImage: "calendar.badge.plus")
             }
         }
     }
*/

// MARK: - Quick Integration Checklist

/*
 ✅ MUST DO (Core Functionality):
 1. [ ] Add Season.self to modelContainer in PlayerPathApp.swift (DONE ✅)
 2. [ ] Link games to seasons when created (Example 3)
 3. [ ] Link practices to seasons when created (Example 4)
 4. [ ] Link videos to seasons when created (Example 5)
 5. [ ] Add Season Management to Profile/Settings (Example 1)
 
 ⭐️ SHOULD DO (Better UX):
 6. [ ] Add SeasonIndicator to main dashboard (Example 2)
 7. [ ] Add migration check on app launch (Example 6)
 8. [ ] Show season recommendations (Example 2)
 9. [ ] Filter lists by active season (Example 7)
 
 💡 NICE TO HAVE (Polish):
 10. [ ] Show season info in detail views (Example 8)
 11. [ ] Add season stats to profile (Example 9)
 12. [ ] First-time user onboarding (Example 10)
 13. [ ] Toolbar season indicators (Example 11)
 14. [ ] Context menu season actions (Example 12)
*/

// MARK: - Common Patterns

// Pattern 1: Get or create active season
func ensureSeasonExists(for athlete: Athlete, in modelContext: ModelContext) -> Season {
    return SeasonManager.ensureActiveSeason(for: athlete, in: modelContext)
}

// Pattern 2: Link item to season during creation
func createNewItem<T>(item: T, athlete: Athlete, modelContext: ModelContext) where T: PersistentModel {
    modelContext.insert(item)
    
    if let game = item as? Game {
        SeasonManager.linkGameToActiveSeason(game, for: athlete, in: modelContext)
    } else if let practice = item as? Practice {
        SeasonManager.linkPracticeToActiveSeason(practice, for: athlete, in: modelContext)
    } else if let video = item as? VideoClip {
        SeasonManager.linkVideoToActiveSeason(video, for: athlete, in: modelContext)
    }
    
    try? modelContext.save()
}

// Pattern 3: Check season status and show recommendations
func checkAndShowSeasonRecommendation(for athlete: Athlete) -> SeasonManager.SeasonRecommendation {
    return SeasonManager.checkSeasonStatus(for: athlete)
}

// Pattern 4: Filter by season
func filterBySeason<T>(_ items: [T], season: Season?) -> [T] where T: AnyObject {
    guard let season = season else { return items }
    
    if let games = items as? [Game] {
        return games.filter { $0.season?.id == season.id } as! [T]
    } else if let practices = items as? [Practice] {
        return practices.filter { $0.season?.id == season.id } as! [T]
    } else if let videos = items as? [VideoClip] {
        return videos.filter { $0.season?.id == season.id } as! [T]
    }
    
    return items
}
