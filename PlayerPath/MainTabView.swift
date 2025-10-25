//
//  MainTabView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import SwiftData
import Foundation
import Combine

struct MainTabView: View {
    let user: User
    @Binding var selectedAthlete: Athlete?
    
    var body: some View {
        TabView {
            DashboardView(
                user: user,
                selectedAthlete: $selectedAthlete
            )
            .tabItem {
                Image(systemName: "house.fill")
                Text("Dashboard")
            }
            
            TournamentsView(athlete: selectedAthlete)
                .tabItem {
                    Image(systemName: "trophy.fill")
                    Text("Tournaments")
                }
            
            GamesView(athlete: selectedAthlete)
                .tabItem {
                    Image(systemName: "figure.baseball")
                    Text("Games")
                }
            
            PracticesView(athlete: selectedAthlete)
                .tabItem {
                    Image(systemName: "baseball.diamond.bases")
                    Text("Practice")
                }
            
            VideoClipsView(athlete: selectedAthlete)
                .tabItem {
                    Image(systemName: "video.fill")
                    Text("Videos")
                }
            
            HighlightsView(athlete: selectedAthlete)
                .tabItem {
                    Image(systemName: "star.fill")
                    Text("Highlights")
                }
            
            StatisticsView(athlete: selectedAthlete)
                .tabItem {
                    Image(systemName: "chart.bar.fill")
                    Text("Statistics")
                }
            
            ProfileView(user: user, selectedAthlete: $selectedAthlete)
                .tabItem {
                    Image(systemName: "person.fill")
                    Text("Profile")
                }
        }
        .accentColor(.blue)
    }
}

// MARK: - Dashboard View
struct DashboardView: View {
    let user: User
    @Binding var selectedAthlete: Athlete?
    @State private var showingVideoRecorder = false
    @Environment(\.modelContext) private var modelContext
    
    // Use @Query to observe all games and filter in computed properties
    @Query private var allGames: [Game]
    @Query private var allTournaments: [Tournament] 
    @Query private var allPractices: [Practice]
    @Query private var allVideoClips: [VideoClip]
    
    // Computed properties that will automatically update when data changes
    private var currentLiveGame: Game? {
        selectedAthlete?.games.first { $0.isLive }
    }
    
    private var gameCount: Int {
        guard let selectedAthlete = selectedAthlete else { return 0 }
        
        // Get both counts for comparison
        let relationshipCount = selectedAthlete.games.count
        let queryCount = allGames.filter { $0.athlete?.id == selectedAthlete.id }.count
        
        print("=== DETAILED GAME ANALYSIS ===")
        print("Selected athlete: \(selectedAthlete.name)")
        print("Athlete ID: \(selectedAthlete.id)")
        print("Relationship count: \(relationshipCount)")
        print("Query count: \(queryCount)")
        print("Total games in database: \(allGames.count)")
        
        // Analyze each game in the athlete's games array
        print("\n--- ATHLETE'S GAMES ARRAY (\(relationshipCount) items) ---")
        for (index, game) in selectedAthlete.games.enumerated() {
            let gameAthleteId = game.athlete?.id.uuidString ?? "NO ATHLETE ID"
            let gameAthleteName = game.athlete?.name ?? "NO ATHLETE NAME"
            let isInDatabase = allGames.contains(game)
            print("\(index + 1). '\(game.opponent)' - Date: \(game.date)")
            print("   - Game Athlete: \(gameAthleteName) (\(gameAthleteId))")
            print("   - In Database: \(isInDatabase)")
            print("   - Game ID: \(game.id)")
        }
        
        // Analyze each game that claims to belong to this athlete via query
        print("\n--- GAMES CLAIMING THIS ATHLETE (\(queryCount) items) ---")
        let athleteGames = allGames.filter { $0.athlete?.id == selectedAthlete.id }
        for (index, game) in athleteGames.enumerated() {
            let inAthleteArray = selectedAthlete.games.contains(game)
            print("\(index + 1). '\(game.opponent)' - Date: \(game.date)")
            print("   - In Athlete Array: \(inAthleteArray)")
            print("   - Game ID: \(game.id)")
        }
        
        // Check for phantom games (in athlete array but not in database)
        let phantomGames = selectedAthlete.games.filter { game in
            !allGames.contains(game)
        }
        
        if !phantomGames.isEmpty {
            print("\n--- PHANTOM GAMES (In array but not in DB) ---")
            for game in phantomGames {
                print("PHANTOM: '\(game.opponent)' - \(game.date)")
            }
        }
        
        // Check for orphaned references (in DB with athlete ID but not in athlete array)
        let orphanedReferences = allGames.filter { game in
            game.athlete?.id == selectedAthlete.id && !selectedAthlete.games.contains(game)
        }
        
        if !orphanedReferences.isEmpty {
            print("\n--- ORPHANED REFERENCES (Has athlete ID but not in array) ---")
            for game in orphanedReferences {
                print("ORPHANED: '\(game.opponent)' - \(game.date)")
            }
        }
        
        print("========================")
        
        // Return the relationship count, but flag inconsistency
        if relationshipCount != queryCount {
            print("🚨 DATA INCONSISTENCY: Relationship count (\(relationshipCount)) != Query count (\(queryCount))")
        }
        
        return relationshipCount
    }
    
    private var activeTournamentCount: Int {
        guard let selectedAthlete = selectedAthlete else { return 0 }
        let count = selectedAthlete.tournaments.filter { $0.isActive }.count
        
        print("=== TOURNAMENT COUNT DEBUG ===")
        print("Selected athlete: \(selectedAthlete.name)")
        print("Active tournament count: \(count)")
        print("Total tournaments in database: \(allTournaments.count)")
        
        // Print ALL tournaments in database
        print("\n--- ALL TOURNAMENTS IN DATABASE ---")
        for (index, tournament) in allTournaments.enumerated() {
            let athleteName = tournament.athlete?.name ?? "NO ATHLETE"
            let inAthleteArray = tournament.athlete?.tournaments.contains(tournament) ?? false
            print("\(index + 1). '\(tournament.name)' - Athlete: '\(athleteName)' - Active: \(tournament.isActive) - InAthleteArray: \(inAthleteArray)")
        }
        
        // Print tournaments via relationship
        print("\n--- TOURNAMENTS VIA RELATIONSHIP ---")
        for (index, tournament) in selectedAthlete.tournaments.enumerated() {
            print("\(index + 1). '\(tournament.name)' - Active: \(tournament.isActive)")
        }
        print("========================")
        
        return count
    }
    
    private var totalTournamentCount: Int {
        guard let selectedAthlete = selectedAthlete else { return 0 }
        return selectedAthlete.tournaments.count
    }
    
    private var practiceCount: Int {
        guard let selectedAthlete = selectedAthlete else { return 0 }
        return selectedAthlete.practices.count
    }
    
    private var videoClipCount: Int {
        guard let selectedAthlete = selectedAthlete else { return 0 }
        return selectedAthlete.videoClips.count
    }
    
    private var highlightCount: Int {
        guard let selectedAthlete = selectedAthlete else { return 0 }
        return selectedAthlete.videoClips.filter { $0.isHighlight }.count
    }
    
    private var battingAverage: Double {
        selectedAthlete?.statistics?.battingAverage ?? 0.0
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20, pinnedViews: []) {
                    // Athlete Selection Header
                    AthleteHeaderCard(
                        user: user,
                        selectedAthlete: $selectedAthlete
                    )
                    
                    // Quick Record Button
                    QuickRecordCard(
                        showingVideoRecorder: $showingVideoRecorder,
                        currentLiveGame: currentLiveGame
                    )
                    
                    // Dashboard Cards Grid
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 15) {
                        NavigationLink(destination: TournamentsView(athlete: selectedAthlete)) {
                            DashboardCard(
                                icon: "trophy.fill",
                                title: "Tournaments",
                                subtitle: activeTournamentCount > 0 ? "\(activeTournamentCount) Active" : "\(totalTournamentCount) Total",
                                color: activeTournamentCount > 0 ? .green : .orange
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        NavigationLink(destination: GamesView(athlete: selectedAthlete)) {
                            DashboardCard(
                                icon: "figure.baseball",
                                title: "Games",
                                subtitle: "\(gameCount) Total",
                                color: .green
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        NavigationLink(destination: PracticesView(athlete: selectedAthlete)) {
                            DashboardCard(
                                icon: "baseball.diamond.bases",
                                title: "Practice",
                                subtitle: "\(practiceCount) Sessions",
                                color: .mint
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        NavigationLink(destination: VideoClipsView(athlete: selectedAthlete)) {
                            DashboardCard(
                                icon: "video.fill",
                                title: "Video Clips",
                                subtitle: "\(videoClipCount) Recorded",
                                color: .purple
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        NavigationLink(destination: HighlightsView(athlete: selectedAthlete)) {
                            DashboardCard(
                                icon: "star.fill",
                                title: "Highlights",
                                subtitle: "\(highlightCount) Amazing",
                                color: .yellow
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        NavigationLink(destination: StatisticsView(athlete: selectedAthlete)) {
                            DashboardCard(
                                icon: "chart.bar.fill",
                                title: "Statistics",
                                subtitle: String(format: "%.3f AVG", battingAverage),
                                color: .blue
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // Recent Statistics
                    if let athlete = selectedAthlete,
                       let stats = athlete.statistics {
                        RecentStatsCard(statistics: stats)
                    }
                    
                    // Recent Activity
                    RecentActivityCard(athlete: selectedAthlete)
                    

                }
                .padding()
                .padding(.bottom, 50) // Extra space at bottom
            }
            .scrollContentBackground(.hidden)
            .clipped()
            .navigationTitle("PlayerPath")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                // Pull to refresh forces SwiftUI to re-evaluate computed properties
                cleanupOrphanedData()
            }
            .onAppear {
                cleanupOrphanedData()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                // Also cleanup when app becomes active
                cleanupOrphanedData()
            }
        }
        .sheet(isPresented: $showingVideoRecorder) {
            VideoRecorderView(
                athlete: selectedAthlete,
                game: currentLiveGame
            )
        }
        .refreshable {
            // Pull to refresh forces SwiftUI to re-evaluate computed properties
        }
    }
    
    private func cleanupOrphanedData() {
        print("=== STARTING AGGRESSIVE DATA CLEANUP ===")
        
        // Count items before cleanup
        let totalGamesBefore = allGames.count
        let totalTournamentsBefore = allTournaments.count
        let totalPracticesBefore = allPractices.count
        let totalVideoClipsBefore = allVideoClips.count
        
        print("Before cleanup:")
        print("  - Total games: \(totalGamesBefore)")
        print("  - Total tournaments: \(totalTournamentsBefore)")
        print("  - Total practices: \(totalPracticesBefore)")
        print("  - Total video clips: \(totalVideoClipsBefore)")
        
        var deletedCount = 0
        
        // 1. Remove games that have no athlete association
        let orphanedGames = allGames.filter { $0.athlete == nil }
        for game in orphanedGames {
            print("Deleting orphaned game (no athlete): \(game.opponent)")
            modelContext.delete(game)
            deletedCount += 1
        }
        
        // 2. Remove games that have athlete but aren't in athlete's games array
        let inconsistentGames = allGames.filter { game in
            if let athlete = game.athlete {
                return !athlete.games.contains(game)
            }
            return false
        }
        for game in inconsistentGames {
            print("Deleting inconsistent game (not in athlete array): \(game.opponent) for \(game.athlete?.name ?? "unknown")")
            modelContext.delete(game)
            deletedCount += 1
        }
        
        // 3. Remove duplicate games (same opponent, same date, same athlete)
        var duplicateGames: [Game] = []
        let groupedGames = Dictionary(grouping: allGames.filter { $0.athlete != nil }) { game in
            "\(game.athlete!.id.uuidString)_\(game.opponent)_\(Int(game.date.timeIntervalSince1970))"
        }
        
        for (key, games) in groupedGames {
            if games.count > 1 {
                print("Found \(games.count) duplicate games for key: \(key)")
                // Keep the first one, mark the rest for deletion
                let duplicatesToDelete = Array(games.dropFirst())
                duplicateGames.append(contentsOf: duplicatesToDelete)
            }
        }
        
        for game in duplicateGames {
            print("Deleting duplicate game: \(game.opponent) for athlete: \(game.athlete?.name ?? "nil")")
            if let athlete = game.athlete,
               let index = athlete.games.firstIndex(of: game) {
                athlete.games.remove(at: index)
            }
            modelContext.delete(game)
            deletedCount += 1
        }
        
        // 4. Remove tournaments that have no athlete association
        let orphanedTournaments = allTournaments.filter { $0.athlete == nil }
        for tournament in orphanedTournaments {
            print("Deleting orphaned tournament (no athlete): \(tournament.name)")
            modelContext.delete(tournament)
            deletedCount += 1
        }
        
        // 5. Remove tournaments that have athlete but aren't in athlete's tournaments array
        let inconsistentTournaments = allTournaments.filter { tournament in
            if let athlete = tournament.athlete {
                return !athlete.tournaments.contains(tournament)
            }
            return false
        }
        for tournament in inconsistentTournaments {
            print("Deleting inconsistent tournament (not in athlete array): \(tournament.name) for \(tournament.athlete?.name ?? "unknown")")
            modelContext.delete(tournament)
            deletedCount += 1
        }
        
        // 6. Remove orphaned practices and video clips
        let orphanedPractices = allPractices.filter { $0.athlete == nil }
        for practice in orphanedPractices {
            print("Deleting orphaned practice")
            modelContext.delete(practice)
            deletedCount += 1
        }
        
        let orphanedVideoClips = allVideoClips.filter { $0.athlete == nil }
        for clip in orphanedVideoClips {
            print("Deleting orphaned video clip: \(clip.fileName)")
            modelContext.delete(clip)
            deletedCount += 1
        }
        
        // Save changes if there were any problematic items
        if deletedCount > 0 {
            print("Found and cleaned up \(deletedCount) problematic items:")
            print("  - Orphaned games: \(orphanedGames.count)")
            print("  - Inconsistent games: \(inconsistentGames.count)")
            print("  - Duplicate games: \(duplicateGames.count)")
            print("  - Orphaned tournaments: \(orphanedTournaments.count)")
            print("  - Inconsistent tournaments: \(inconsistentTournaments.count)")
            print("  - Orphaned practices: \(orphanedPractices.count)")
            print("  - Orphaned video clips: \(orphanedVideoClips.count)")
            
            do {
                try modelContext.save()
                print("Successfully saved cleanup changes")
            } catch {
                print("Failed to save cleanup changes: \(error)")
            }
        } else {
            print("No problematic data found")
        }
        
        print("=== CLEANUP COMPLETED ===")
    }
}

struct AthleteHeaderCard: View {
    let user: User
    @Binding var selectedAthlete: Athlete?
    @State private var showingAthleteSelection = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("Welcome back,")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if let athlete = selectedAthlete {
                    Button(action: { showingAthleteSelection = true }) {
                        HStack {
                            Text(athlete.name)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            
                            Image(systemName: "chevron.down")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    Button(action: { showingAthleteSelection = true }) {
                        Text("Select Athlete")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            Spacer()
            
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(.blue)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(15)
        .contentShape(Rectangle())
        .onTapGesture {
            showingAthleteSelection = true
        }
        .sheet(isPresented: $showingAthleteSelection) {
            AthleteSelectionSheet(
                user: user,
                selectedAthlete: $selectedAthlete
            )
        }
    }
}

struct AthleteSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let user: User
    @Binding var selectedAthlete: Athlete?
    @State private var showingAddAthlete = false
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(user.athletes) { athlete in
                    Button(action: {
                        selectedAthlete = athlete
                        dismiss()
                    }) {
                        HStack {
                            Text(athlete.name)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if athlete.id == selectedAthlete?.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Athlete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Add Athlete") {
                        showingAddAthlete = true
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingAddAthlete) {
                QuickAddAthleteView(user: user, selectedAthlete: $selectedAthlete)
            }
        }
    }
}

struct QuickRecordCard: View {
    @Binding var showingVideoRecorder: Bool
    let currentLiveGame: Game?
    
    var body: some View {
        VStack(spacing: 15) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Quick Record")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    if let game = currentLiveGame {
                        Text("Live: vs \(game.opponent)")
                            .font(.subheadline)
                            .foregroundColor(.green)
                    } else {
                        Text("No active game")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button(action: { showingVideoRecorder = true }) {
                    Image(systemName: "video.badge.plus")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(Color.red)
                        .clipShape(Circle())
                }
                .disabled(currentLiveGame == nil)
                .opacity(currentLiveGame == nil ? 0.6 : 1.0)
            }
            
            if currentLiveGame == nil {
                Text("Create a game and mark it as live to start recording")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(15)
        .contentShape(Rectangle())
    }
}

struct DashboardCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundColor(color)
            
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .cornerRadius(15)
        .contentShape(Rectangle()) // Makes the entire area tappable
        .scaleEffect(1.0) // For animation
        .animation(.easeInOut(duration: 0.1), value: false)
    }
}

struct RecentStatsCard: View {
    let statistics: Statistics
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Quick Stats")
                .font(.headline)
                .fontWeight(.bold)
            
            HStack {
                StatBox(
                    title: "AVG",
                    value: String(format: "%.3f", statistics.battingAverage),
                    color: .blue
                )
                
                StatBox(
                    title: "OBP",
                    value: String(format: "%.3f", statistics.onBasePercentage),
                    color: .green
                )
                
                StatBox(
                    title: "SLG",
                    value: String(format: "%.3f", statistics.sluggingPercentage),
                    color: .orange
                )
                
                StatBox(
                    title: "H",
                    value: "\(statistics.hits)",
                    color: .purple
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(15)
    }
}

struct StatBox: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
    }
}

struct RecentActivityCard: View {
    let athlete: Athlete?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Recent Activity")
                .font(.headline)
                .fontWeight(.bold)
            
            if let athlete = athlete {
                if athlete.videoClips.isEmpty {
                    Text("No recent activity")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    let recentClips = Array(athlete.videoClips.sorted { $0.createdAt > $1.createdAt }.prefix(3))
                    
                    ForEach(recentClips) { clip in
                        HStack {
                            Image(systemName: clip.isHighlight ? "star.fill" : "video.fill")
                                .foregroundColor(clip.isHighlight ? .yellow : .blue)
                            
                            VStack(alignment: .leading) {
                                Text(clip.playResult?.type.rawValue ?? "Unrecorded Play")
                                    .font(.subheadline)
                                
                                Text(clip.createdAt, formatter: DateFormatter.shortDateTime)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                }
            } else {
                Text("Select an athlete to view activity")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(15)
    }
}

// Helper extension for date formatting
extension DateFormatter {
    static let shortDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - Quick Add Athlete View
struct QuickAddAthleteView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let user: User
    @Binding var selectedAthlete: Athlete?
    @State private var athleteName = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                VStack {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("Add New Athlete")
                        .font(.title)
                        .fontWeight(.bold)
                }
                
                TextField("Athlete Name", text: $athleteName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("New Athlete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveAthlete()
                    }
                    .disabled(athleteName.isEmpty)
                }
            }
        }
    }
    
    private func saveAthlete() {
        let athlete = Athlete(name: athleteName)
        athlete.user = user
        athlete.statistics = Statistics()
        
        user.athletes.append(athlete)
        modelContext.insert(athlete)
        
        // Also insert the statistics
        if let statistics = athlete.statistics {
            statistics.athlete = athlete
            modelContext.insert(statistics)
        }
        
        do {
            try modelContext.save()
            selectedAthlete = athlete // Auto-select the new athlete
            dismiss()
        } catch {
            print("Failed to save athlete: \(error)")
        }
    }
}