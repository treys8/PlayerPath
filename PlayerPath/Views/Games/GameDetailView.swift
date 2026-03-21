//
//  GameDetailView.swift
//  PlayerPath
//
//  Detail view for a single game showing stats, clips, and actions.
//

import SwiftUI
import SwiftData

struct GameDetailView: View {
    let game: Game
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @State private var showingEndGame = false
    @State private var showingVideoRecorder = false
    @State private var showingUploadRecorder = false
    @State private var showingDeleteConfirmation = false
    @State private var showingManualStats = false
    @State private var showingEditGame = false
    @State private var gameService: GameService? = nil

    var videoClips: [VideoClip] {
        (game.videoClips ?? []).sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    var body: some View {
        List {
            // Game Info Section
            Section("Game Details") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Opponent")
                            .fontWeight(.semibold)
                        Spacer()
                        Text(game.opponent)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Date")
                            .fontWeight(.semibold)
                        Spacer()
                        if let date = game.date {
                            Text(date, format: .dateTime.month().day().hour().minute())
                                .foregroundColor(.secondary)
                        } else {
                            Text("Unknown Date")
                                .foregroundColor(.secondary)
                        }
                    }

                    if let location = game.location, !location.isEmpty {
                        HStack {
                            Text("Location")
                                .fontWeight(.semibold)
                            Spacer()
                            Text(location)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Text("Status")
                            .fontWeight(.semibold)
                        Spacer()

                        Group {
                            if game.isLive {
                                Text("LIVE")
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.red)
                                    .cornerRadius(4)
                            } else if game.isComplete {
                                Text("COMPLETED")
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.gray)
                                    .cornerRadius(4)
                            } else {
                                Text("SCHEDULED")
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.brandNavy)
                                    .cornerRadius(4)
                            }
                        }
                        .font(.caption)
                        .fontWeight(.bold)
                    }

                    if let notes = game.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes")
                                .fontWeight(.semibold)
                            Text(notes)
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        }
                    }
                }
                .padding(.vertical, 5)
            }

            // Quick Actions Section
            Section("Actions") {
                if !game.isComplete {
                    Button(action: { showingVideoRecorder = true }) {
                        Label("Record Video", systemImage: "video.badge.plus")
                    }

                    if game.isLive {
                        Button(role: .destructive) {
                            showingEndGame = true
                        } label: {
                            Label("End Game", systemImage: "stop.circle")
                        }
                    } else {
                        Button {
                            startGame()
                        } label: {
                            Label("Start Game", systemImage: "play.circle")
                        }
                    }
                } else {
                    Button {
                        game.isComplete = false
                        game.isLive = true
                        ErrorHandlerService.shared.saveContext(modelContext, caller: "GamesView.restartGame")
                    } label: {
                        Label("Restart Game", systemImage: "arrow.counterclockwise")
                    }

                    Button(action: { showingUploadRecorder = true }) {
                        Label("Upload from Camera Roll", systemImage: "photo.badge.plus")
                    }
                }

                // Edit Game Details - available for all games
                Button(action: { showingEditGame = true }) {
                    Label("Edit Game", systemImage: "pencil")
                }

                // Manual Statistics Entry
                Button(action: { showingManualStats = true }) {
                    Label("Enter Statistics", systemImage: "chart.bar.doc.horizontal")
                }

                if !game.isLive {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Game", systemImage: "trash")
                    }
                }
            }

            // Video Clips Section
            Section("Video Clips (\(videoClips.count))") {
                if videoClips.isEmpty {
                    Text("No videos recorded yet")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(videoClips) { clip in
                        VideoClipRow(clip: clip, hasCoachingAccess: authManager.hasCoachingAccess)
                    }
                }
            }

            // Game Statistics
            if let stats = game.gameStats {
                Section("Game Statistics") {
                    HStack {
                        Text("At Bats")
                        Spacer()
                        Text("\(stats.atBats)")
                            .fontWeight(.semibold)
                    }
                    HStack {
                        Text("Hits")
                        Spacer()
                        Text("\(stats.hits)")
                            .fontWeight(.semibold)
                    }
                    HStack {
                        Text("Runs")
                        Spacer()
                        Text("\(stats.runs)")
                            .fontWeight(.semibold)
                    }
                    HStack {
                        Text("RBIs")
                        Spacer()
                        Text("\(stats.rbis)")
                            .fontWeight(.semibold)
                    }
                    HStack {
                        Text("Strikeouts")
                        Spacer()
                        Text("\(stats.strikeouts)")
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                    }
                    HStack {
                        Text("Ground Outs")
                        Spacer()
                        Text("\(stats.groundOuts)")
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                    }
                    HStack {
                        Text("Fly Outs")
                        Spacer()
                        Text("\(stats.flyOuts)")
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                    }
                    HStack {
                        Text("Walks")
                        Spacer()
                        Text("\(stats.walks)")
                            .fontWeight(.semibold)
                    }

                    // Calculate and show batting average for this game
                    if stats.atBats > 0 {
                        HStack {
                            Text("Batting Average")
                            Spacer()
                            Text(String(format: "%.3f", Double(stats.hits) / Double(stats.atBats)))
                                .fontWeight(.semibold)
                                .foregroundColor(.brandNavy)
                        }
                    }
                }
            }
        }
        .navigationTitle("vs \(game.opponent)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    // Video Actions
                    if !game.isComplete {
                        Button(action: { showingVideoRecorder = true }) {
                            Label("Record Video", systemImage: "video.badge.plus")
                        }
                    }

                    // Game State Actions
                    if !game.isComplete {
                        if game.isLive {
                            Button(action: { showingEndGame = true }) {
                                Label("End Game", systemImage: "stop.circle")
                            }
                        } else {
                            Button(action: { startGame() }) {
                                Label("Start Game", systemImage: "play.circle")
                            }
                        }
                    } else {
                        Button(action: {
                            game.isComplete = false
                            game.isLive = true
                            ErrorHandlerService.shared.saveContext(modelContext, caller: "GamesView.restartGame")
                        }) {
                            Label("Restart Game", systemImage: "arrow.counterclockwise")
                        }

                        Button(action: { showingUploadRecorder = true }) {
                            Label("Upload from Camera Roll", systemImage: "photo.badge.plus")
                        }
                    }

                    Divider()

                    // Edit Game Details
                    Button(action: { showingEditGame = true }) {
                        Label("Edit Game", systemImage: "pencil")
                    }

                    // Statistics Action
                    Button(action: { showingManualStats = true }) {
                        Label("Enter Statistics", systemImage: "chart.bar.doc.horizontal")
                    }

                    Divider()

                    // Destructive Actions
                    if !game.isLive {
                        Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                            Label("Delete Game", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
            }
        }
        .alert("End Game", isPresented: $showingEndGame) {
            Button("Cancel", role: .cancel) { }
            Button("End", role: .destructive) {
                endGame()
            }
        } message: {
            Text("Are you sure you want to end this game? You won't be able to record more videos for it.")
        }
        .alert("Delete Game", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteGame()
            }
        } message: {
            if game.isComplete, !videoClips.isEmpty || game.gameStats != nil {
                let clipCount = videoClips.count
                let hasStats = game.gameStats != nil
                if clipCount > 0 && hasStats {
                    Text("This game has \(clipCount) video clip\(clipCount == 1 ? "" : "s") and recorded statistics. Deleting it will permanently remove all data and recalculate career stats.")
                } else if clipCount > 0 {
                    Text("This game has \(clipCount) video clip\(clipCount == 1 ? "" : "s"). Deleting it will permanently remove all data.")
                } else {
                    Text("This game has recorded statistics. Deleting it will permanently remove all data and recalculate career stats.")
                }
            } else {
                Text("Are you sure you want to delete this game? This action cannot be undone.")
            }
        }
        .fullScreenCover(isPresented: $showingVideoRecorder) {
            DirectCameraRecorderView(athlete: game.athlete, game: game)
        }
        .fullScreenCover(isPresented: $showingUploadRecorder) {
            VideoRecorderView_Refactored(athlete: game.athlete, game: game)
        }
        .sheet(isPresented: $showingManualStats) {
            ManualStatisticsEntryView(game: game)
        }
        .sheet(isPresented: $showingEditGame) {
            EditGameSheet(game: game)
        }
        .onAppear {
            if gameService == nil { gameService = GameService(modelContext: modelContext) }
        }
    }

    @MainActor
    private func startGame() {
        Task { await gameService?.start(game) }
    }

    @MainActor
    private func endGame() {
        Task { await gameService?.end(game) }
    }

    @MainActor
    private func deleteGame() {
        Task {
            await gameService?.deleteGameDeep(game)
            dismiss()
        }
    }
}
