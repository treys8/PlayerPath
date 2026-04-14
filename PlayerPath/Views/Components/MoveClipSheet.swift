//
//  MoveClipSheet.swift
//  PlayerPath
//
//  Sheet for moving a VideoClip from one athlete profile to another.
//  Presented from VideoClipCard and VideoClipRow context menus.
//

import SwiftUI
import SwiftData

struct MoveClipSheet: View {
    let clip: VideoClip

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Athlete.createdAt) private var allAthletes: [Athlete]

    @State private var selectedAthlete: Athlete?
    @State private var selectedGame: Game?
    @State private var isMoving = false
    @State private var showingConfirmation = false
    @State private var errorMessage: String?
    @State private var showingError = false

    private var otherAthletes: [Athlete] {
        allAthletes.filter { $0.id != clip.athlete?.id }
    }

    private var canMove: Bool {
        guard !isMoving, selectedAthlete != nil else { return false }
        return !isBlocked
    }

    private var isBlocked: Bool {
        let isUploading = UploadQueueManager.shared.activeUploads[clip.id] != nil
            || UploadQueueManager.shared.pendingUploads.contains { $0.clipId == clip.id }
        let hasPendingSync = clip.needsSync
        return isUploading || hasPendingSync
    }

    private var blockReason: String? {
        if UploadQueueManager.shared.activeUploads[clip.id] != nil
            || UploadQueueManager.shared.pendingUploads.contains(where: { $0.clipId == clip.id }) {
            return "This clip is currently uploading. Wait for the upload to finish before moving it."
        }
        if clip.needsSync {
            return "This clip has pending changes syncing to the cloud. Try again in a moment."
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if otherAthletes.isEmpty {
                    emptyState
                } else if isBlocked {
                    blockedState
                } else {
                    pickerContent
                }
            }
            .navigationTitle("Move to Athlete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") {
                        Haptics.warning()
                        showingConfirmation = true
                    }
                    .fontWeight(.semibold)
                    .disabled(!canMove)
                }
            }
            .confirmationDialog(
                "Move clip to \(selectedAthlete?.name ?? "athlete")?",
                isPresented: $showingConfirmation,
                titleVisibility: .visible
            ) {
                Button("Move Clip") {
                    Haptics.heavy()
                    Task { await performMove() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The clip will be removed from its current game and practice. Statistics will be recalculated for both athletes.")
            }
            .alert("Move Failed", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An unexpected error occurred.")
            }
            .disabled(isMoving)
            .overlay {
                if isMoving {
                    ZStack {
                        Color(.systemBackground).opacity(0.8)
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Moving clip...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .ignoresSafeArea()
                }
            }
        }
    }

    // MARK: - Content

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            Text("No Other Athletes")
                .font(.headline)
            Text("Add another athlete profile to move clips between them.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var blockedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "hourglass")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            Text("Can't Move Right Now")
                .font(.headline)
            Text(blockReason ?? "Please try again later.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pickerContent: some View {
        List {
            Section {
                ForEach(otherAthletes) { athlete in
                    Button {
                        withAnimation {
                            selectedAthlete = athlete
                            selectedGame = nil
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(athlete.name)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                if let season = athlete.activeSeason {
                                    Text(season.displayName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if selectedAthlete?.id == athlete.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                }
            } header: {
                Text("Move to")
            }

            if let athlete = selectedAthlete {
                let games = (athlete.games ?? [])
                    .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }

                Section {
                    Button {
                        selectedGame = nil
                    } label: {
                        HStack {
                            Text("No Game")
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedGame == nil {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                                    .fontWeight(.semibold)
                            }
                        }
                    }

                    ForEach(games) { game in
                        Button {
                            selectedGame = game
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("vs \(game.opponent)")
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    if let date = game.date {
                                        Text(date, style: .date)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                if selectedGame?.id == game.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Assign to game (optional)")
                }
            }
        }
    }

    // MARK: - Move Logic

    @MainActor
    private func performMove() async {
        guard let newAthlete = selectedAthlete else { return }
        isMoving = true

        let oldAthlete = clip.athlete
        let oldGame = clip.game
        let newGame = selectedGame

        // Update relationships
        clip.athlete = newAthlete
        clip.practice = nil
        clip.practiceDate = nil

        // Season
        let newSeason = newAthlete.activeSeason ?? SeasonManager.ensureActiveSeason(for: newAthlete, in: modelContext)
        clip.season = newSeason
        clip.seasonName = newSeason?.displayName

        // Game
        if let game = newGame {
            clip.game = game
            clip.gameOpponent = game.opponent
            clip.gameDate = game.date
        } else {
            clip.game = nil
            clip.gameOpponent = nil
            clip.gameDate = nil
        }

        clip.needsSync = true

        // Save
        let saved = ErrorHandlerService.shared.saveContext(modelContext, caller: "MoveClipSheet")
        guard saved else {
            errorMessage = "Could not move clip. Please try again."
            showingError = true
            isMoving = false
            return
        }

        // Recalculate statistics: old side then new side
        do {
            if let oldGame {
                try StatisticsService.shared.recalculateGameStatistics(for: oldGame, context: modelContext)
            }
            if let oldAthlete {
                try StatisticsService.shared.recalculateAthleteStatistics(for: oldAthlete, context: modelContext)
            }
            if let newGame {
                try StatisticsService.shared.recalculateGameStatistics(for: newGame, context: modelContext)
            }
            try StatisticsService.shared.recalculateAthleteStatistics(for: newAthlete, context: modelContext)
        } catch {
            ErrorHandlerService.shared.handle(error, context: "MoveClipSheet.recalcStats", showAlert: false)
        }

        Haptics.success()
        isMoving = false
        dismiss()
    }
}
