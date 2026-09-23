//
//  GameLinkerView.swift
//  PlayerPath
//
//  Sheet for linking a video clip to a game.
//

import SwiftUI
import SwiftData

struct GameLinkerView: View {
    /// One clip from a card/player menu, or several from Videos-tab selection
    /// mode. All clips belong to the same athlete. Read through `clips`.
    private let inputClips: [VideoClip]
    /// Called after a successful save only (not on Cancel), so a caller can
    /// reset state that should survive backing out.
    private let onSaved: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Game.date, order: .reverse) private var allGames: [Game]

    @State private var selectedGame: Game?
    /// False until the user taps a row. With several clips on different games
    /// there is no honest "current" selection, so nothing is checked and Save
    /// stays disabled until a choice is made.
    @State private var didPick = false
    @State private var errorMessage: String?
    @State private var showingError = false

    init(clips: [VideoClip], onSaved: (() -> Void)? = nil) {
        self.inputClips = clips
        self.onSaved = onSaved
    }

    init(clip: VideoClip) {
        self.init(clips: [clip])
    }

    /// Clips still alive in the store. A sync delete or a Move while this sheet
    /// is open would otherwise leave a deleted @Model here, and reading any of
    /// its attributes traps (build 177 class). `isDeleted`/`modelContext` are
    /// safe to read on a deleted model.
    private var clips: [VideoClip] {
        inputClips.filter { !$0.isDeleted && $0.modelContext != nil }
    }

    private var athlete: Athlete? { clips.first?.athlete }

    private var athleteGames: [Game] {
        guard let athleteId = athlete?.id else { return [] }
        return allGames.filter { $0.athlete?.id == athleteId }
    }

    /// The game every clip is on (nil = all unlinked). `.none` when they differ.
    private var sharedGameID: UUID?? {
        let ids = Set(clips.map { $0.game?.id })
        return ids.count == 1 ? ids.first : .none
    }

    private func isChecked(_ gameID: UUID?) -> Bool {
        if didPick { return selectedGame?.id == gameID }
        if case .some(let shared) = sharedGameID { return shared == gameID }
        return false
    }

    private var hasChanges: Bool {
        didPick && clips.contains { $0.game?.id != selectedGame?.id }
    }

    private var isGolfAthlete: Bool { athlete?.sport == .golf }
    private var unitNoun: String { isGolfAthlete ? "Tournament" : "Game" }
    private var unitNounPlural: String { isGolfAthlete ? "Tournaments" : "Games" }
    private var unitNounLower: String { isGolfAthlete ? "tournament" : "game" }
    private var videoNoun: String { clips.count == 1 ? "Video" : "\(clips.count) videos" }

    var body: some View {
        NavigationStack {
            List {
                // Option to unlink
                Section {
                    Button {
                        selectedGame = nil
                        didPick = true
                    } label: {
                        HStack {
                            Label("No \(unitNoun)", systemImage: "minus.circle")
                                .foregroundColor(.primary)
                            Spacer()
                            if isChecked(nil) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.brandNavy)
                            }
                        }
                    }
                } footer: {
                    Text("\(videoNoun) will not be associated with any \(unitNounLower)")
                }

                // Games list
                if athleteGames.isEmpty {
                    Section {
                        Text("No \(unitNounLower)s found for this athlete")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Section(unitNounPlural) {
                        ForEach(athleteGames) { game in
                            let isGolfGame = game.season?.sport == .golf
                            Button {
                                selectedGame = game
                                didPick = true
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(isGolfGame ? "at" : "vs") \(game.opponent.isEmpty ? "Unknown" : game.opponent)")
                                            .foregroundColor(.primary)
                                        if let date = game.date {
                                            Text(date, format: .dateTime.month(.abbreviated).day().year())
                                                .font(.bodySmall)
                                                .foregroundColor(.secondary)
                                        }
                                        if let season = game.season {
                                            Text(season.displayName)
                                                .font(.labelSmall)
                                                .foregroundColor(.brandNavy)
                                        }
                                    }
                                    Spacer()
                                    if isChecked(game.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.brandNavy)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(clips.count == 1 ? "Link to \(unitNoun)" : "Link \(clips.count) Videos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(!hasChanges)
                }
            }
            .alert("Save Failed", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func saveChanges() {
        let target = selectedGame
        // Snapshot every field we touch so a failed save rolls all of them back.
        let changed = clips.filter { $0.game?.id != target?.id }
        guard !changed.isEmpty else { dismiss(); return }
        let snapshots = changed.map { clip in
            (clip: clip, game: clip.game, season: clip.season, practice: clip.practice,
             gameOpponent: clip.gameOpponent, gameDate: clip.gameDate, practiceDate: clip.practiceDate,
             seasonName: clip.seasonName, needsSync: clip.needsSync)
        }
        let oldGames = Set(changed.compactMap(\.game)).filter { $0 != target }

        for clip in changed {
            clip.game = target
            clip.needsSync = true
            // Keep the denormalized copies in step with the relationship. Sync
            // uploads `gameOpponent ?? game?.opponent` (SyncCoordinator+Videos),
            // so a stale copy would pair the new gameId with the old opponent.
            // Same field set MoveClipSheet.performMove writes.
            clip.gameOpponent = target?.opponent
            clip.gameDate = target?.date
            if let game = target {
                clip.season = game.season
                clip.seasonName = game.season?.displayName
                // A clip lives on a game OR a practice. Leaving the practice
                // attached would count its play result in the game's stats.
                clip.practice = nil
                clip.practiceDate = nil
            }
        }

        // Save the clip changes BEFORE recalculating: recalculateGameStatistics
        // saves the context itself, so recalculating first would persist the
        // clips and make the rollback below a memory-only illusion.
        do {
            try modelContext.save()
        } catch {
            for snap in snapshots {
                snap.clip.game = snap.game
                snap.clip.season = snap.season
                snap.clip.practice = snap.practice
                snap.clip.gameOpponent = snap.gameOpponent
                snap.clip.gameDate = snap.gameDate
                snap.clip.practiceDate = snap.practiceDate
                snap.clip.seasonName = snap.seasonName
                snap.clip.needsSync = snap.needsSync
            }
            ErrorHandlerService.shared.handle(error, context: "GameLinkerView.saveClipAssignment", showAlert: false)
            errorMessage = "Could not save \(unitNounLower) assignment. Please try again."
            showingError = true
            return
        }

        // Stats are derived — a failure here is logged, not rolled back (the
        // next recalculation repairs it). Games first: athlete stats aggregate
        // from game stats.
        do {
            for game in oldGames {
                try StatisticsService.shared.recalculateGameStatistics(for: game, context: modelContext)
            }
            if let target {
                try StatisticsService.shared.recalculateGameStatistics(for: target, context: modelContext)
            }
            if let athlete {
                try StatisticsService.shared.recalculateAthleteStatistics(for: athlete, context: modelContext, skipSave: true)
            }
        } catch {
            ErrorHandlerService.shared.handle(error, context: "GameLinkerView.recalculateStats", showAlert: false)
        }
        ErrorHandlerService.shared.saveContext(modelContext, caller: "GameLinkerView.saveChanges")

        Haptics.success()
        onSaved?()
        dismiss()
    }
}
