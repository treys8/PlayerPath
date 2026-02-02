//
//  SampleDataGenerator.swift
//  PlayerPath
//
//  Generates realistic sample data for new users to explore the app
//

import Foundation
import SwiftUI
import SwiftData

@MainActor
struct SampleDataGenerator {

    // MARK: - Generate Sample Data

    static func generateSampleData(for user: User, context: ModelContext) throws {
        print("🎯 Generating sample data for user: \(user.username)")

        // Create sample athlete
        let athlete = createSampleAthlete(for: user)
        context.insert(athlete)

        // Create sample season
        let season = createSampleSeason(for: athlete)
        context.insert(season)

        // Create sample games
        let (games, gameStats) = createSampleGames(for: athlete, season: season)
        games.forEach { context.insert($0) }
        gameStats.forEach { context.insert($0) }

        // Create sample practices
        let practices = createSamplePractices(for: athlete, season: season)
        practices.forEach { context.insert($0) }

        // Save all
        try context.save()

        print("✅ Sample data generated successfully")
        print("   - 1 athlete: \(athlete.name)")
        print("   - 1 season: \(season.name)")
        print("   - \(games.count) games")
        print("   - \(practices.count) practices")
    }

    // MARK: - Sample Athlete

    private static func createSampleAthlete(for user: User) -> Athlete {
        let athlete = Athlete(name: "Demo Player")
        athlete.user = user
        athlete.createdAt = Date()
        return athlete
    }

    // MARK: - Sample Season

    private static func createSampleSeason(for athlete: Athlete) -> Season {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())

        let season = Season(
            name: "Spring \(currentYear)",
            startDate: calendar.date(from: DateComponents(year: currentYear, month: 3, day: 1))!,
            sport: .baseball
        )
        season.endDate = calendar.date(from: DateComponents(year: currentYear, month: 6, day: 30))
        season.athlete = athlete
        season.isActive = true

        return season
    }

    // MARK: - Sample Games

    private static func createSampleGames(for athlete: Athlete, season: Season) -> ([Game], [GameStatistics]) {
        let calendar = Calendar.current
        let opponents = [
            "Eagles", "Tigers", "Panthers", "Wildcats", "Bears",
            "Hawks", "Cougars", "Bulldogs", "Rams", "Trojans"
        ]

        var games: [Game] = []
        var gameStats: [GameStatistics] = []
        let startDate = season.startDate ?? Date()

        for i in 0..<8 {
            // Create games spaced ~1 week apart
            guard let gameDate = calendar.date(byAdding: .day, value: i * 7, to: startDate) else { continue }

            let game = Game(
                date: gameDate,
                opponent: opponents[i % opponents.count]
            )
            game.athlete = athlete
            game.season = season
            game.isComplete = gameDate < Date() // Mark past games as complete

            // Add realistic stats for completed games
            if game.isComplete == true {
                addSampleStatsToGame(game)
                if let stats = game.gameStats {
                    gameStats.append(stats)
                }
            }

            games.append(game)
        }

        return (games, gameStats)
    }

    private static func addSampleStatsToGame(_ game: Game) {
        // Realistic game stats
        let atBats = Int.random(in: 3...5)
        let hits = Int.random(in: 0...min(atBats, 3))
        let walks = Int.random(in: 0...2)

        // Distribute hits
        var remainingHits = hits
        let homeRuns = min(remainingHits, Int.random(in: 0...1))
        remainingHits -= homeRuns

        let triples = min(remainingHits, Int.random(in: 0...1))
        remainingHits -= triples

        let doubles = min(remainingHits, Int.random(in: 0...min(remainingHits, 2)))
        remainingHits -= doubles

        let singles = remainingHits

        let rbis = Int.random(in: 0...min(hits + walks, 4))
        let runs = Int.random(in: 0...min(hits + walks, 3))
        let strikeouts = Int.random(in: 0...min(atBats - hits, 2))

        // Create GameStatistics object
        let stats = GameStatistics()
        stats.atBats = atBats
        stats.hits = hits
        stats.singles = singles
        stats.doubles = doubles
        stats.triples = triples
        stats.homeRuns = homeRuns
        stats.runs = runs
        stats.rbis = rbis
        stats.walks = walks
        stats.strikeouts = strikeouts
        stats.game = game
        game.gameStats = stats
    }

    // MARK: - Sample Practices

    private static func createSamplePractices(for athlete: Athlete, season: Season) -> [Practice] {
        let calendar = Calendar.current
        var practices: [Practice] = []
        let startDate = season.startDate ?? Date()

        // Create 5 practices between games
        for i in 0..<5 {
            guard let practiceDate = calendar.date(byAdding: .day, value: (i * 7) + 3, to: startDate),
                  practiceDate < Date() else { continue }

            let practice = Practice(date: practiceDate)
            practice.athlete = athlete
            practice.season = season

            // Add practice notes
            let notes = [
                "Worked on timing and weight transfer. Focused on hitting to opposite field.",
                "Batting practice: 50 swings. Concentrated on keeping hands inside the ball.",
                "Tee work focusing on launch angle. Made good progress on uppercut swing.",
                "Live pitching practice. Improved recognition of breaking balls.",
                "Soft toss and video review. Identified early hand movement issue."
            ]

            let note = PracticeNote(content: notes[i % notes.count])
            note.createdAt = practiceDate
            note.practice = practice
            practice.notes = [note]

            practices.append(practice)
        }

        return practices
    }

    // MARK: - Check if Sample Data Exists

    static func hasSampleData(for user: User) -> Bool {
        guard let athletes = user.athletes, !athletes.isEmpty else { return false }

        // Check if any athlete is named "Demo Player"
        return athletes.contains { $0.name == "Demo Player" }
    }

    // MARK: - Remove Sample Data

    static func removeSampleData(for user: User, context: ModelContext) throws {
        guard let athletes = user.athletes else { return }

        for athlete in athletes where athlete.name == "Demo Player" {
            // Delete all related data
            if let games = athlete.games {
                games.forEach { context.delete($0) }
            }
            if let practices = athlete.practices {
                practices.forEach { practice in
                    if let notes = practice.notes {
                        notes.forEach { context.delete($0) }
                    }
                    context.delete(practice)
                }
            }
            if let seasons = athlete.seasons {
                seasons.forEach { context.delete($0) }
            }

            context.delete(athlete)
        }

        try context.save()
        print("✅ Sample data removed")
    }
}

// MARK: - Sample Data Prompt View

struct SampleDataPromptView: View {
    let user: User
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isGenerating = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 12) {
                Text("Explore with Sample Data")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Try out PlayerPath with realistic sample data to see how it works")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "person.fill", text: "Demo athlete profile")
                FeatureRow(icon: "baseball.fill", text: "8 sample games with stats")
                FeatureRow(icon: "figure.baseball", text: "5 practice sessions")
                FeatureRow(icon: "chart.bar.fill", text: "Calculated statistics")
            }
            .padding(.horizontal)

            if let error = error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }

            VStack(spacing: 12) {
                Button {
                    generateSampleData()
                } label: {
                    if isGenerating {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Add Sample Data")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.blue)
                .foregroundStyle(.white)
                .cornerRadius(12)
                .disabled(isGenerating)

                Button("Skip") {
                    dismiss()
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .shadow(radius: 20)
        .padding()
    }

    private func generateSampleData() {
        Task {
            await MainActor.run {
                isGenerating = true
                error = nil
            }

            do {
                try SampleDataGenerator.generateSampleData(for: user, context: modelContext)

                await MainActor.run {
                    Haptics.success()
                    OnboardingManager.shared.markMilestoneComplete(.initialOnboarding)
                    dismiss()
                }
            } catch let generationError {
                await MainActor.run {
                    error = "Failed to generate sample data: \(generationError.localizedDescription)"
                    isGenerating = false
                    Haptics.error()
                }
            }
        }
    }
}

struct SampleDataPromptView_Previews: PreviewProvider {
    static var previews: some View {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: User.self, configurations: config)
        let user = User(username: "Test", email: "test@example.com")

        return SampleDataPromptView(user: user)
            .modelContainer(container)
    }
}
