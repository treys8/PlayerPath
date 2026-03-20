//
//  ImportTaggingSheet.swift
//  PlayerPath
//
//  Created by Assistant on 3/14/26.
//

import SwiftUI
import SwiftData

/// A sheet presented after importing a video from the Photos library,
/// allowing the user to link the clip to a game and optionally tag a play result.
struct ImportTaggingSheet: View {
    let clip: VideoClip
    let athlete: Athlete
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedGame: Game?
    @State private var selectedPlayResult: PlayResultType?
    @State private var recordingMode: AthleteRole = .batter
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

    // MARK: - Recent Games

    /// Cached recent games to avoid expensive filter+sort on every render.
    @State private var recentGames: [Game] = []

    private func updateRecentGames() {
        let allGames = athlete.games ?? []
        recentGames = Array(
            allGames
                .filter { !$0.isDeletedRemotely }
                .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
                .prefix(15)
        )
    }

    private static let dateFormatter = DateFormatter.mediumDate

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: .spacingXLarge) {
                    headerSection
                    gameSelectionSection
                    if selectedGame != nil {
                        playResultSection
                    }
                }
                .padding(.horizontal, .spacingLarge)
                .padding(.bottom, 100) // space for bottom buttons
            }
            .background(Color.backgroundPrimary)
            .safeAreaInset(edge: .bottom) {
                bottomButtons
            }
            .navigationTitle("Tag This Clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        dismiss()
                    }
                    .foregroundColor(.textSecondary)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .alert("Save Error", isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )) {
                Button("OK") { saveErrorMessage = nil }
            } message: {
                Text(saveErrorMessage ?? "")
            }
            .onAppear {
                updateRecentGames()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: .spacingSmall) {
            Image(systemName: "tag.fill")
                .font(.system(size: 36))
                .foregroundStyle(LinearGradient.primaryButton)
                .padding(.top, .spacingLarge)

            Text("Link to a Game?")
                .font(.headingLarge)
                .foregroundColor(.textPrimary)

            Text("Associate this clip with a game to track statistics and keep your footage organized.")
                .font(.bodyMedium)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, .spacingLarge)
        }
    }

    // MARK: - Game Selection

    private var gameSelectionSection: some View {
        VStack(alignment: .leading, spacing: .spacingMedium) {
            Text("RECENT GAMES")
                .font(.labelSmall)
                .foregroundColor(.textSecondary)
                .tracking(1.0)
                .padding(.leading, .spacingXSmall)

            if recentGames.isEmpty {
                noGamesView
            } else {
                LazyVStack(spacing: .spacingSmall) {
                    ForEach(recentGames, id: \.id) { game in
                        gameRow(game)
                    }
                }
            }
        }
    }

    private var noGamesView: some View {
        VStack(spacing: .spacingSmall) {
            Image(systemName: "sportscourt")
                .font(.system(size: 28))
                .foregroundColor(.textSecondary)
            Text("No games found")
                .font(.bodyMedium)
                .foregroundColor(.textSecondary)
            Text("Create a game first, then you can link clips to it.")
                .font(.bodySmall)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, .spacingXLarge)
        .background(
            RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous)
                .fill(Color.backgroundSecondary)
        )
    }

    private func gameRow(_ game: Game) -> some View {
        let isSelected = selectedGame?.id == game.id

        return Button {
            withAnimation(.standard) {
                if isSelected {
                    selectedGame = nil
                    selectedPlayResult = nil
                } else {
                    selectedGame = game
                }
            }
            Haptics.light()
        } label: {
            HStack(spacing: .spacingMedium) {
                // Game icon
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.brandPrimary : Color.backgroundTertiary)
                        .frame(width: 40, height: 40)

                    Image(systemName: "baseball.diamond.bases")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isSelected ? .white : .textSecondary)
                }

                // Game info
                VStack(alignment: .leading, spacing: 2) {
                    Text("vs \(game.opponent)")
                        .font(.headingSmall)
                        .foregroundColor(.textPrimary)

                    if let date = game.date {
                        Text(Self.dateFormatter.string(from: date))
                            .font(.bodySmall)
                            .foregroundColor(.textSecondary)
                    }
                }

                Spacer()

                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.brandPrimary)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.spacingMedium)
            .background(
                RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous)
                    .fill(isSelected ? Color.brandPrimary.opacity(0.08) : Color.backgroundSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous)
                    .strokeBorder(isSelected ? Color.brandPrimary.opacity(0.3) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Game vs \(game.opponent)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Play Result Section

    private var playResultSection: some View {
        VStack(alignment: .leading, spacing: .spacingMedium) {
            Text("TAG A PLAY RESULT")
                .font(.labelSmall)
                .foregroundColor(.textSecondary)
                .tracking(1.0)
                .padding(.leading, .spacingXSmall)

            Text("Optional \u{2014} add a play result to track game statistics.")
                .font(.bodySmall)
                .foregroundColor(.textSecondary)
                .padding(.leading, .spacingXSmall)

            // Mode picker
            PlayResultModePicker(selection: $recordingMode)
                .padding(.vertical, .spacingXSmall)

            // Play result grid
            VStack(spacing: .spacingSmall) {
                if recordingMode == .batter {
                    battingResultsGrid
                } else {
                    pitchingResultsGrid
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var battingResultsGrid: some View {
        VStack(spacing: .spacingSmall) {
            // Hits
            resultSectionHeader(icon: "baseball.fill", title: "HITS", color: .success)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: .spacingSmall) {
                resultChip(.single)
                resultChip(.double)
                resultChip(.triple)
                resultChip(.homeRun)
            }

            // Walk
            resultSectionHeader(icon: "figure.walk", title: "WALK", color: .info)
            resultChip(.walk)

            // Outs
            resultSectionHeader(icon: "xmark.circle.fill", title: "OUTS", color: .error)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: .spacingSmall) {
                resultChip(.strikeout)
                resultChip(.groundOut)
                resultChip(.flyOut)
            }
        }
    }

    private var pitchingResultsGrid: some View {
        VStack(spacing: .spacingSmall) {
            resultSectionHeader(icon: "figure.baseball", title: "PITCH RESULT", color: .brandSecondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: .spacingSmall) {
                resultChip(.ball)
                resultChip(.strike)
            }

            resultSectionHeader(icon: "xmark.circle.fill", title: "OUTS", color: .error)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: .spacingSmall) {
                resultChip(.strikeout)
                resultChip(.groundOut)
                resultChip(.flyOut)
            }

            resultSectionHeader(icon: "exclamationmark.triangle.fill", title: "SPECIAL", color: .warning)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: .spacingSmall) {
                resultChip(.hitByPitch)
                resultChip(.wildPitch)
            }
        }
    }

    private func resultSectionHeader(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, .spacingXSmall)
        .padding(.top, .spacingSmall)
    }

    private func resultChip(_ type: PlayResultType) -> some View {
        let isSelected = selectedPlayResult == type

        return Button {
            withAnimation(.quick) {
                if isSelected {
                    selectedPlayResult = nil
                } else {
                    selectedPlayResult = type
                }
            }
            Haptics.medium()
        } label: {
            HStack(spacing: .spacingSmall) {
                Image(systemName: type.iconName)
                    .font(.system(size: 14, weight: .semibold))
                Text(type.displayName)
                    .font(.headingSmall)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .foregroundColor(isSelected ? .white : .textPrimary)
            .padding(.horizontal, .spacingMedium)
            .padding(.vertical, .spacingMedium)
            .background(
                RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous)
                    .fill(isSelected ? type.uiColor : Color.backgroundSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous)
                    .strokeBorder(isSelected ? type.uiColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(type.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Bottom Buttons

    private var bottomButtons: some View {
        HStack(spacing: .spacingMedium) {
            // Skip button
            Button {
                dismiss()
            } label: {
                Text("Skip")
                    .font(.headingSmall)
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, .spacingLarge)
                    .background(
                        RoundedRectangle(cornerRadius: .cornerXLarge, style: .continuous)
                            .fill(Color.backgroundSecondary)
                    )
            }
            .disabled(isSaving)

            // Save button
            Button {
                saveTagging()
            } label: {
                HStack(spacing: .spacingSmall) {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                    }
                    Text("Save")
                        .font(.headingSmall)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, .spacingLarge)
                .background(
                    RoundedRectangle(cornerRadius: .cornerXLarge, style: .continuous)
                        .fill(selectedGame != nil ? LinearGradient.primaryButton : LinearGradient(colors: [.gray, .gray.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                )
            }
            .disabled(selectedGame == nil || isSaving)
        }
        .padding(.horizontal, .spacingLarge)
        .padding(.vertical, .spacingMedium)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Save Logic

    private func saveTagging() {
        guard let game = selectedGame else { return }
        isSaving = true

        // Link the clip to the selected game
        clip.game = game
        clip.gameOpponent = game.opponent
        clip.gameDate = game.date
        clip.seasonName = game.season?.displayName ?? athlete.activeSeason?.displayName

        // Link to the game's season if the clip doesn't have one
        if clip.season == nil, let gameSeason = game.season {
            clip.season = gameSeason
        }

        // Handle play result if selected
        if let playResultType = selectedPlayResult {
            // Remove existing play result if there is one (from the initial save)
            if let existingResult = clip.playResult {
                // Reverse the old stats before removing
                reversePlayResultStats(existingResult.type, game: clip.game)
                modelContext.delete(existingResult)
                clip.playResult = nil
            }

            // Create new play result
            let result = PlayResult(type: playResultType)
            clip.playResult = result
            modelContext.insert(result)

            // Auto-highlight based on user rules
            clip.isHighlight = AutoHighlightSettings.shared.shouldAutoHighlight(
                playType: playResultType,
                role: recordingMode
            )

            // Update game statistics
            if game.gameStats == nil {
                let gameStats = GameStatistics()
                gameStats.game = game
                game.gameStats = gameStats
                modelContext.insert(gameStats)
            }
            game.gameStats?.addPlayResult(playResultType)

            // Track analytics
            AnalyticsService.shared.trackVideoTagged(
                playResult: playResultType.displayName,
                videoID: clip.id.uuidString
            )
        }

        Task {
            do {
                try modelContext.save()
                Haptics.success()
                // Notify dashboard to refresh
                NotificationCenter.default.post(name: Notification.Name("VideoRecorded"), object: clip)
                dismiss()
            } catch {
                isSaving = false
                saveErrorMessage = "Failed to save: \(error.localizedDescription)"
                Haptics.error()
            }
        }
    }

    /// Reverse a play result from game statistics (when replacing a tag).
    private func reversePlayResultStats(_ type: PlayResultType, game: Game?) {
        guard let gameStats = game?.gameStats else { return }

        if type.countsAsAtBat {
            gameStats.atBats = max(0, gameStats.atBats - 1)
        }
        switch type {
        case .single:
            gameStats.hits = max(0, gameStats.hits - 1)
            gameStats.singles = max(0, gameStats.singles - 1)
        case .double:
            gameStats.hits = max(0, gameStats.hits - 1)
            gameStats.doubles = max(0, gameStats.doubles - 1)
        case .triple:
            gameStats.hits = max(0, gameStats.hits - 1)
            gameStats.triples = max(0, gameStats.triples - 1)
        case .homeRun:
            gameStats.hits = max(0, gameStats.hits - 1)
            gameStats.homeRuns = max(0, gameStats.homeRuns - 1)
        case .walk:
            gameStats.walks = max(0, gameStats.walks - 1)
        case .strikeout:
            gameStats.strikeouts = max(0, gameStats.strikeouts - 1)
        case .groundOut:
            gameStats.groundOuts = max(0, gameStats.groundOuts - 1)
        case .flyOut:
            gameStats.flyOuts = max(0, gameStats.flyOuts - 1)
        case .hitByPitch:
            gameStats.hitByPitches = max(0, gameStats.hitByPitches - 1)
        case .ball, .strike, .wildPitch:
            break
        }
    }
}
