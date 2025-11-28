//
//  StatisticsView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import SwiftData
import Charts

struct StatisticsView: View {
    let athlete: Athlete?
    
    enum ActiveSheet: Identifiable {
        case quickEntry(Game)
        case gameSelection
        var id: String {
            switch self {
            case .quickEntry(let game):
                return "quickEntry_\(game.id.uuidString)"
            case .gameSelection:
                return "gameSelection"
            }
        }
    }
    @State private var activeSheet: ActiveSheet?
    
    var statistics: AthleteStatistics? {
        athlete?.statistics
    }
    
    var currentLiveGame: Game? {
        athlete?.games?.first(where: { $0.isLive })
    }
    
    var hasLiveGame: Bool { currentLiveGame != nil }
    
    var body: some View {
        contentView
            .navigationTitle("Statistics")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $activeSheet) { item in
                switch item {
                case .quickEntry(let game):
                    QuickStatisticsEntryView(game: game, athlete: athlete)
                case .gameSelection:
                    GameSelectionForStatsView(athlete: athlete)
                }
            }
    }
    
    @ViewBuilder
    private var contentView: some View {
        if let stats = statistics {
            ScrollView {
                LazyVStack(spacing: 20) {
                    // Manual Entry Section
                    ManualEntrySection(
                        currentLiveGame: currentLiveGame,
                        showQuickEntry: {
                            if let game = currentLiveGame { activeSheet = .quickEntry(game) }
                        },
                        showGameSelection: { activeSheet = .gameSelection }
                    )
                    
                    // Key Statistics Cards
                    KeyStatsSection(statistics: stats)
                    
                    // Batting Chart
                    BattingChartSection(statistics: stats)
                    
                    // Detailed Statistics
                    DetailedStatsSection(statistics: stats)
                    
                    // Play Results Breakdown
                    PlayResultsSection(statistics: stats)
                }
                .padding()
            }
        } else {
            EmptyStatisticsView(
                isQuickEntryEnabled: hasLiveGame,
                showQuickEntry: {
                    if let game = currentLiveGame { activeSheet = .quickEntry(game) }
                },
                showGameSelection: { activeSheet = .gameSelection }
            )
        }
    }
}

struct EmptyStatisticsView: View {
    let isQuickEntryEnabled: Bool
    let showQuickEntry: () -> Void
    let showGameSelection: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "chart.bar")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            Text("No Statistics Yet")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Record plays to start building your stats")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(spacing: 12) {
                Button(action: { showQuickEntry() }) {
                    Label("Record Live Game Stats", systemImage: "chart.bar.doc.horizontal.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(!isQuickEntryEnabled)
                
                Button(action: { showGameSelection() }) {
                    Label("Add Past Game Statistics", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
        }
        .padding()
    }
}

// MARK: - Manual Entry Section
struct ManualEntrySection: View {
    let currentLiveGame: Game?
    let showQuickEntry: () -> Void
    let showGameSelection: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Manual Statistics Entry")
                .font(.headline)
                .fontWeight(.bold)
            
            VStack(spacing: 12) {
                // Current Live Game Option
                if let game = currentLiveGame {
                    Button(action: { showQuickEntry() }) {
                        HStack {
                            VStack(alignment: .leading) {
                                HStack {
                                    Image(systemName: "circle.fill")
                                        .foregroundColor(.red)
                                        .font(.caption)
                                    Text("LIVE GAME")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.red)
                                }
                                
                                Text("Record stats for vs \(game.opponent)")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                
                                Text("Tap to add at-bats and hits")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(.blue)
                        }
                        .padding()
                        .statCardBackground()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Record statistics for live game")
                    .accessibilityHint("Add at-bats, hits, and results for the current game")
                } else {
                    // No Live Game Available
                    VStack {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.orange)
                            Text("No active game")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding()
                        .statCardBackground()
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("No active game. Start a live game to record current game stats.")
                    }
                }
                
                // Add Past Game Option
                Button(action: { showGameSelection() }) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Add Past Game Statistics")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            Text("Select a game to record statistics")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .foregroundColor(.blue)
                    }
                    .padding()
                    .statCardBackground()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add past game statistics")
                .accessibilityHint("Select a previous game to record statistics")
            }
        }
    }
}

struct KeyStatsSection: View {
    let statistics: AthleteStatistics
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Key Statistics")
                .font(.headline)
                .fontWeight(.bold)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 15) {
                StatCard(
                    title: "Batting Average",
                    value: formatBattingAverage(statistics.battingAverage),
                    color: .blue,
                    subtitle: "\(statistics.hits)/\(statistics.atBats)"
                )
                
                StatCard(
                    title: "On-Base %",
                    value: formatThreeDecimal(statistics.onBasePercentage),
                    color: .green,
                    subtitle: "Walks: \(statistics.walks)"
                )
                
                StatCard(
                    title: "Slugging %",
                    value: formatBattingAverage(statistics.sluggingPercentage),
                    color: .orange,
                    subtitle: "Total Bases"
                )
                
                StatCard(
                    title: "Games Played",
                    value: "\(statistics.totalGames)",
                    color: .purple,
                    subtitle: "Career"
                )
            }
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let color: Color
    let subtitle: String?
    
    init(title: String, value: String, color: Color, subtitle: String? = nil) {
        self.title = title
        self.value = value
        self.color = color
        self.subtitle = subtitle
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(height: 100)
        .frame(maxWidth: .infinity)
        .statCardBackground()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value)\(subtitle.map { ", \($0)" } ?? "")")
    }
}

struct BattingChartSection: View {
    let statistics: AthleteStatistics
    
    private var chartData: [PlayTypeData] {
        [
            PlayTypeData(type: "Singles", count: statistics.singles, color: .green),
            PlayTypeData(type: "Doubles", count: statistics.doubles, color: .blue),
            PlayTypeData(type: "Triples", count: statistics.triples, color: .orange),
            PlayTypeData(type: "Home Runs", count: statistics.homeRuns, color: .red)
        ].filter { $0.count > 0 }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Hit Distribution")
                .font(.headline)
                .fontWeight(.bold)
            
            if !chartData.isEmpty {
                Chart(chartData, id: \.type) { data in
                    BarMark(
                        x: .value("Count", data.count),
                        y: .value("Type", data.type)
                    )
                    .foregroundStyle(data.color)
                    .annotation(position: .trailing) {
                        Text("\(data.count)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("\(data.type): \(data.count)")
                }
                .chartXScale(domain: 0...max(1, chartData.map(\.count).max() ?? 1))
                .frame(height: 200)
                .padding()
                .statCardBackground()
            } else {
                Text("No hits recorded yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(height: 100)
                    .frame(maxWidth: .infinity)
                    .statCardBackground()
            }
        }
    }
}

struct PlayTypeData {
    let type: String
    let count: Int
    let color: Color
}

struct DetailedStatsSection: View {
    let statistics: AthleteStatistics
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Detailed Statistics")
                .font(.headline)
                .fontWeight(.bold)
            
            VStack(spacing: 0) {
                DetailedStatRow(label: "At Bats", value: "\(statistics.atBats)")
                DetailedStatRow(label: "Hits", value: "\(statistics.hits)")
                DetailedStatRow(label: "Walks", value: "\(statistics.walks)")
                DetailedStatRow(label: "Strikeouts", value: "\(statistics.strikeouts)")
                DetailedStatRow(label: "Ground Outs", value: "\(statistics.groundOuts)")
                DetailedStatRow(label: "Fly Outs", value: "\(statistics.flyOuts)", isLast: true)
            }
            .statCardBackground()
        }
    }
}

private struct LabelValueRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
}

struct DetailedStatRow: View {
    let label: String
    let value: String
    let isLast: Bool
    
    init(label: String, value: String, isLast: Bool = false) {
        self.label = label
        self.value = value
        self.isLast = isLast
    }
    
    var body: some View {
        VStack(spacing: 0) {
            LabelValueRow(label: label, value: value)
            if !isLast {
                Divider()
                    .padding(.horizontal)
            }
        }
    }
}

struct PlayResultsSection: View {
    let statistics: AthleteStatistics
    
    private var playResults: [PlayResultData] {
        [
            PlayResultData(type: "Singles", count: statistics.singles, color: .green),
            PlayResultData(type: "Doubles", count: statistics.doubles, color: .blue),
            PlayResultData(type: "Triples", count: statistics.triples, color: .orange),
            PlayResultData(type: "Home Runs", count: statistics.homeRuns, color: .red),
            PlayResultData(type: "Runs", count: statistics.runs, color: .purple),
            PlayResultData(type: "RBIs", count: statistics.rbis, color: .pink),
            PlayResultData(type: "Walks", count: statistics.walks, color: .cyan),
            PlayResultData(type: "Strikeouts", count: statistics.strikeouts, color: .red)
        ]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Play Results")
                .font(.headline)
                .fontWeight(.bold)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(playResults, id: \.type) { data in
                    PlayResultCard(data: data)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Play results summary")
        }
    }
}

struct PlayResultData {
    let type: String
    let count: Int
    let color: Color
}

struct PlayResultCard: View {
    let data: PlayResultData
    
    var body: some View {
        VStack(spacing: 8) {
            Text("\(data.count)")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(data.color)
            
            Text(data.type)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(height: 70)
        .frame(maxWidth: .infinity)
        .statCardBackground()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(data.type): \(data.count)")
    }
}

#Preview {
    let mockAthlete: Athlete = {
        let athlete = Athlete(name: "Sample Player")
        let stats = AthleteStatistics()
        stats.hits = 45
        stats.atBats = 130
        stats.walks = 20
        stats.doubles = 10
        stats.triples = 2
        stats.homeRuns = 5
        athlete.statistics = stats
        return athlete
    }()
    return NavigationStack { StatisticsView(athlete: mockAthlete) }
}

// MARK: - Quick Statistics Entry View
@MainActor
struct QuickStatisticsEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let game: Game
    let athlete: Athlete?
    
    @State private var playResultType: PlayResultType = .single
    @State private var numberOfPlays: String = "1"
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var isSaving = false
    @FocusState private var isPlaysFieldFocused: Bool
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Current Game") {
                    HStack {
                        Text("Opponent:")
                            .fontWeight(.semibold)
                        Spacer()
                        Text(game.opponent)
                            .foregroundColor(.secondary)
                    }
                    
                    if game.isLive {
                        HStack {
                            Image(systemName: "circle.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                            Text("LIVE GAME")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.red)
                        }
                    }
                }
                
                Section("Record Play Result") {
                    Picker("Play Result", selection: $playResultType) {
                        ForEach(PlayResultType.allCases, id: \.self) { playType in
                            Text(playType.displayName).tag(playType)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    HStack {
                        Text("Number of plays")
                            .fontWeight(.medium)
                        TextField("1", text: $numberOfPlays)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .focused($isPlaysFieldFocused)
                    }
                }
                
                Section("Play Details") {
                    HStack {
                        Text("Result Type:")
                        Spacer()
                        Text(playResultType.displayName)
                            .fontWeight(.semibold)
                            .foregroundColor(playResultType.isHit ? .green : .orange)
                    }
                    
                    if playResultType.isHit {
                        HStack {
                            Text("Bases:")
                            Spacer()
                            Text("\(playResultType.bases)")
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                        }
                        
                        if playResultType.isHighlight {
                            HStack {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                Text("This will be marked as a highlight")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Record Statistics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        savePlayResults()
                    }
                    .disabled(numberOfPlays.isEmpty || isSaving)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isPlaysFieldFocused = false
                    }
                }
            }
        }
        .alert("Statistics Recorded", isPresented: $showingAlert) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func pluralizedPlayType(_ playType: PlayResultType, count: Int) -> String {
        if count == 1 {
            return playType.displayName
        }
        return playType.displayName
    }

    private func updateGameStatistics(_ gameStats: GameStatistics, playResultType: PlayResultType, playCount: Int) {
        if playResultType.isHit {
            gameStats.hits += playCount
        }
        if playResultType.countsAsAtBat {
            gameStats.atBats += playCount
        }
        if playResultType == .strikeout {
            gameStats.strikeouts += playCount
        }
        if playResultType == .walk {
            gameStats.walks += playCount
        }
    }

    private func savePlayResults() {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        
        guard let playCount = Int(numberOfPlays), playCount > 0, playCount <= 99 else {
            alertMessage = "Please enter a valid number of plays (1-99)"
            showingAlert = true
            return
        }
        
        guard let athlete = athlete else {
            alertMessage = "No athlete selected"
            showingAlert = true
            return
        }
        
        // Update athlete statistics
        if let stats = athlete.statistics {
            for _ in 0..<playCount {
                stats.addPlayResult(playResultType)
            }
        } else {
            // Create statistics if they don't exist
            let newStats = AthleteStatistics()
            athlete.statistics = newStats
            newStats.athlete = athlete
            modelContext.insert(newStats)
            
            for _ in 0..<playCount {
                newStats.addPlayResult(playResultType)
            }
        }
        
        // Update game statistics
        let gameStats: GameStatistics
        if let existingStats = game.gameStats {
            gameStats = existingStats
        } else {
            let newGameStats = GameStatistics()
            game.gameStats = newGameStats
            newGameStats.game = game
            modelContext.insert(newGameStats)
            gameStats = newGameStats
        }

        updateGameStatistics(gameStats, playResultType: playResultType, playCount: playCount)
        
        do {
            try modelContext.save()
            alertMessage = "Recorded \(playCount) \(pluralizedPlayType(playResultType, count: playCount)) for \(game.opponent)"
            showingAlert = true
        } catch {
            print("Failed to save statistics: \(error)")
            alertMessage = "Failed to save statistics. Please try again."
            showingAlert = true
        }
    }
}

// MARK: - Game Selection For Stats View
struct GameSelectionForStatsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let athlete: Athlete?
    
    @State private var showingManualEntry = false
    @State private var selectedGame: Game?
    @State private var showingCreateGame = false
    
    private var availableGames: [Game] {
        let games = athlete?.games ?? []
        return games.sorted { lhs, rhs in
            switch (lhs.date, rhs.date) {
            case let (l?, r?):
                return l > r // newest first
            case (nil, _?):
                return false // nil goes after any non-nil
            case (_?, nil):
                return true  // non-nil comes before nil
            case (nil, nil):
                return false // maintain relative order for two nils
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section("Select a Game") {
                    if availableGames.isEmpty {
                        VStack(spacing: 15) {
                            Text("No games found")
                                .foregroundColor(.secondary)
                            
                            Button("Create a New Game") {
                                showingCreateGame = true
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    } else {
                        ForEach(availableGames) { game in
                            Button(action: {
                                selectedGame = game
                                showingManualEntry = true
                            }) {
                                GameRowForStats(game: game)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                Section {
                    Button("Create New Game for Statistics") {
                        showingCreateGame = true
                    }
                    .foregroundColor(.blue)
                }
            }
            .navigationTitle("Select Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingManualEntry) {
            if let game = selectedGame {
                ManualStatisticsEntryView(game: game)
            }
        }
        .sheet(isPresented: $showingCreateGame) {
            AddGameView(athlete: athlete)
        }
    }
}

struct GameRowForStats: View {
    let game: Game
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("vs \(game.opponent)")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                if let date = game.date {
                    Text(date, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Date TBD")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    if game.isLive {
                        Text("LIVE")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .cornerRadius(4)
                    } else if game.isComplete {
                        Text("COMPLETED")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray)
                            .cornerRadius(4)
                    } else {
                        Text("SCHEDULED")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .cornerRadius(4)
                    }
                    
                    Spacer()
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing) {
                if let stats = game.gameStats {
                    Text("\(stats.hits)/\(stats.atBats)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)

                    if stats.atBats > 0 {
                        Text(formatBattingAverage(Double(stats.hits) / Double(stats.atBats)))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("No stats")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Helper Functions

/// Formats batting average and slugging percentage without leading zero
private func formatBattingAverage(_ value: Double) -> String {
    let formatted = String(format: "%.3f", value)
    if formatted.hasPrefix("0.") {
        return String(formatted.dropFirst()) // Remove the leading "0"
    }
    return formatted
}

private func formatThreeDecimal(_ value: Double) -> String {
    String(format: "%.3f", value)
}

extension View {
    func statCardBackground() -> some View {
        self
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
    }
}

