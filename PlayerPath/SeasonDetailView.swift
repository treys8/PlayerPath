//
//  SeasonDetailView.swift
//  PlayerPath
//
//  Created by Assistant on 11/13/25.
//

import SwiftUI
import SwiftData

enum SeasonContentFilter: String, CaseIterable {
    case all = "All"
    case games = "Games"
    case videos = "Videos"
    case highlights = "Highlights"
    case practices = "Practices"
}

struct SeasonDetailView: View {
    let season: Season
    let athlete: Athlete
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingDeleteConfirmation = false
    @State private var showingReactivateConfirmation = false
    @State private var showingEndSeasonConfirmation = false
    @State private var showingRenameSheet = false
    @State private var editedSeasonName = ""
    @State private var isProcessing = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var selectedFilter: SeasonContentFilter = .all
    @State private var showingSuccess = false
    @State private var successTitle = "Success"
    @State private var successMessage = ""
    @State private var videoUploadTrigger = false
    @State private var photoUploadTrigger = false

    // Cached stats - updated via relationships
    @State private var completedGames: Int = 0
    @State private var totalVideos: Int = 0
    @State private var highlights: Int = 0
    @State private var practices: Int = 0

    // Cached filtered content arrays to avoid expensive recomputation on every render
    @State private var filteredGames: [Game] = []
    @State private var filteredVideos: [VideoClip] = []
    @State private var filteredHighlights: [VideoClip] = []
    @State private var filteredPractices: [Practice] = []

    var body: some View {
        List {
            // Overview Section
            Section {
                HStack {
                    Image(systemName: season.sport.icon)
                        .font(.title)
                        .foregroundColor(.brandNavy)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(season.displayName)
                            .font(.title2)
                            .fontWeight(.bold)

                        if season.isActive {
                            Label("Active", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else {
                            Label("Archived", systemImage: "archivebox.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            // Add Content — routes every upload to this season regardless of
            // whether it is active or archived, and regardless of the photo/
            // video capture dates in the library.
            Section("Add Content") {
                Button {
                    videoUploadTrigger = true
                } label: {
                    Label("Upload Videos", systemImage: "video.badge.plus")
                        .foregroundColor(.brandNavy)
                }

                Button {
                    photoUploadTrigger = true
                } label: {
                    Label("Upload Photos", systemImage: "photo.badge.plus")
                        .foregroundColor(.brandNavy)
                }
            }

            // Date Range
            Section("Season Dates") {
                if let start = season.startDate {
                    LabeledContent("Started", value: start.formatted(date: .long, time: .omitted))
                }

                if let end = season.endDate {
                    LabeledContent("Ended", value: end.formatted(date: .long, time: .omitted))
                } else if season.isActive {
                    HStack {
                        Text("End Date")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("In Progress")
                            .foregroundColor(.brandNavy)
                    }
                }
            }

            // Content Filter
            Section {
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(SeasonContentFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Statistics - using computed values for live updates (shown for All filter)
            if selectedFilter == .all {
                Section("Season Stats") {
                    LabeledContent("Total Games", value: "\(completedGames)")
                    LabeledContent("Total Videos", value: "\(totalVideos)")
                    LabeledContent("Highlights", value: "\(highlights)")
                    LabeledContent("Practices", value: "\(practices)")
                }

                // Baseball Stats (if available)
                if let stats = season.seasonStatistics, stats.atBats > 0 {
                    Section("Batting Statistics") {
                        LabeledContent("Batting Average", value: String(format: ".%03d", Int(stats.battingAverage * 1000)))
                        LabeledContent("At Bats", value: "\(stats.atBats)")
                        LabeledContent("Hits", value: "\(stats.hits)")
                        LabeledContent("Home Runs", value: "\(stats.homeRuns)")
                        LabeledContent("RBIs", value: "\(stats.rbis)")
                        LabeledContent("Walks", value: "\(stats.walks)")
                        LabeledContent("Strikeouts", value: "\(stats.strikeouts)")
                    }
                }

                // Notes
                if !season.notes.isEmpty {
                    Section("Notes") {
                        Text(season.notes)
                    }
                }
            }

            // Filtered Content
            filteredContent

            // Actions
            Section {
                Button {
                    editedSeasonName = season.name
                    showingRenameSheet = true
                } label: {
                    Label("Edit Season Name", systemImage: "pencil")
                }

                if season.isActive {
                    Button {
                        Haptics.warning()
                        showingEndSeasonConfirmation = true
                    } label: {
                        Label("End Season", systemImage: "checkmark.circle")
                            .foregroundStyle(.orange)
                    }
                } else if season.isArchived {
                    Button {
                        showingReactivateConfirmation = true
                    } label: {
                        Label("Reactivate Season", systemImage: "arrow.counterclockwise")
                    }
                }

                Button(role: .destructive) {
                    Haptics.warning()
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete Season", systemImage: "trash")
                }
            }
        }
        .navigationTitle("Season Details")
        .navigationBarTitleDisplayMode(.inline)
        .bulkImportAttach(athlete: athlete, season: season, trigger: $videoUploadTrigger)
        .bulkPhotoImportAttach(athlete: athlete, season: season, trigger: $photoUploadTrigger)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .alert("Delete Season", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Haptics.heavy()
                deleteSeason()
            }
        } message: {
            Text("Are you sure you want to delete this season? This will not delete the games, practices, or videos, but they will no longer be associated with a season.")
        }
        .alert("End Season", isPresented: $showingEndSeasonConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("End Season", role: .destructive) {
                Haptics.heavy()
                endSeason()
            }
        } message: {
            Text("Are you sure you want to end \(season.displayName)? This will archive the season and you won't be able to add new games or practices to it. You can reactivate it later if needed.")
        }
        .alert("Reactivate Season", isPresented: $showingReactivateConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reactivate") {
                reactivateSeason()
            }
        } message: {
            if athlete.activeSeason != nil {
                Text("This will end the current active season and make \(season.displayName) active again.")
            } else {
                Text("This will make \(season.displayName) the active season.")
            }
        }
        .alert("Unable to Update Season", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert(successTitle, isPresented: $showingSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(successMessage)
        }
        .sheet(isPresented: $showingRenameSheet) {
            NavigationStack {
                Form {
                    Section {
                        TextField("Season Name", text: $editedSeasonName)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                    } header: {
                        Text("Season Name")
                    } footer: {
                        Text("Enter a new name for this season")
                    }
                }
                .navigationTitle("Rename Season")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showingRenameSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            showingRenameSheet = false
                            renameSeason(to: editedSeasonName)
                        }
                        .disabled(editedSeasonName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .overlay {
            if isProcessing {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView()
                        .scaleEffect(1.2)
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .disabled(isProcessing)
        .task {
            updateStats()
            updateFilteredContent()
        }
        .onChange(of: selectedFilter) { _, _ in
            updateFilteredContent()
        }
        .onChange(of: season.games) { _, _ in
            updateStats()
            updateFilteredContent()
        }
        .onChange(of: season.videoClips) { _, _ in
            updateStats()
            updateFilteredContent()
        }
        .onChange(of: season.practices) { _, _ in
            updateStats()
            updateFilteredContent()
        }
    }

    // Extracted to a separate @ViewBuilder to keep body small enough for Swift's type checker.
    // Uses pre-computed @State arrays instead of filtering/sorting on every render.
    @ViewBuilder private var filteredContent: some View {
        if selectedFilter == .games || selectedFilter == .all {
            if !filteredGames.isEmpty {
                let totalGames = season.games?.count ?? 0
                let displayGames = selectedFilter == .all ? Array(filteredGames.prefix(5)) : filteredGames
                Section(selectedFilter == .all ? "Recent Games" : "Games (\(totalGames))") {
                    ForEach(displayGames) { game in
                        SeasonGameRow(game: game)
                    }
                    if selectedFilter == .all && totalGames > 5 {
                        Button("See All \(totalGames) Games") { selectedFilter = .games }
                            .font(.subheadline)
                            .foregroundColor(.brandNavy)
                    }
                }
            }
        }
        if selectedFilter == .videos || selectedFilter == .all {
            if !filteredVideos.isEmpty {
                Section("Videos (\(filteredVideos.count))") {
                    ForEach(selectedFilter == .all ? Array(filteredVideos.prefix(5)) : filteredVideos) { video in
                        SeasonVideoRow(video: video)
                    }
                    if selectedFilter == .all && filteredVideos.count > 5 {
                        Button("See All \(filteredVideos.count) Videos") { selectedFilter = .videos }
                            .font(.subheadline)
                            .foregroundColor(.brandNavy)
                    }
                }
            }
        }
        if selectedFilter == .highlights || selectedFilter == .all {
            if !filteredHighlights.isEmpty {
                Section("Highlights (\(filteredHighlights.count))") {
                    ForEach(selectedFilter == .all ? Array(filteredHighlights.prefix(5)) : filteredHighlights) { video in
                        SeasonVideoRow(video: video)
                    }
                    if selectedFilter == .all && filteredHighlights.count > 5 {
                        Button("See All \(filteredHighlights.count) Highlights") { selectedFilter = .highlights }
                            .font(.subheadline)
                            .foregroundColor(.brandNavy)
                    }
                }
            }
        }
        if selectedFilter == .practices || selectedFilter == .all {
            if !filteredPractices.isEmpty {
                Section("Practices (\(filteredPractices.count))") {
                    ForEach(selectedFilter == .all ? Array(filteredPractices.prefix(5)) : filteredPractices) { practice in
                        HStack {
                            Image(systemName: "figure.run")
                                .foregroundStyle(.green)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Practice")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                if let date = practice.date {
                                    Text(date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            let videoCount = practice.videoClips?.count ?? 0
                            if videoCount > 0 {
                                Text("\(videoCount) videos")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    if selectedFilter == .all && filteredPractices.count > 5 {
                        Button("See All \(filteredPractices.count) Practices") { selectedFilter = .practices }
                            .font(.subheadline)
                            .foregroundColor(.brandNavy)
                    }
                }
            }
        }
    }

    private func updateFilteredContent() {
        filteredGames = (season.games ?? [])
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        filteredVideos = (season.videoClips ?? [])
            .filter { !$0.isHighlight }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        filteredHighlights = (season.videoClips ?? [])
            .filter { $0.isHighlight }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        filteredPractices = (season.practices ?? [])
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private func updateStats() {
        completedGames = season.games?.filter { $0.isComplete }.count ?? 0
        totalVideos = season.videoClips?.count ?? 0
        highlights = season.videoClips?.filter { $0.isHighlight }.count ?? 0
        practices = season.practices?.count ?? 0
    }

    private func deleteSeason() {
        isProcessing = true

        Task {
            // Delete from Firestore first — if this fails, don't delete locally
            if let firestoreId = season.firestoreId,
               let user = season.athlete?.user {
                let userId = user.id.uuidString
                do {
                    try await withRetry {
                        try await FirestoreManager.shared.deleteSeason(userId: userId, seasonId: firestoreId)
                    }
                } catch {
                    isProcessing = false
                    errorMessage = "Unable to delete season. Check your connection and try again."
                    showingError = true
                    ErrorHandlerService.shared.handle(error, context: "SeasonDetail.deleteFromFirestore", showAlert: false)
                    return
                }
            }

            // Delink relationships so games/practices/videos are not cascade-deleted
            season.games = nil
            season.practices = nil
            season.videoClips = nil

            modelContext.delete(season)

            do {
                try modelContext.save()
                isProcessing = false
                Haptics.medium()
                dismiss()
            } catch {
                // Firestore is already deleted and is the source of truth. Don't
                // re-insert locally — that would produce a permanent divergence
                // (gone remotely, present locally). SyncCoordinator will
                // reconcile the missing Firestore doc on the next pull.
                ErrorHandlerService.shared.handle(
                    error,
                    context: "SeasonDetail.localSaveAfterFirestoreDelete",
                    showAlert: false
                )
                isProcessing = false
                errorMessage = "Deleted from cloud but local cleanup didn't finish. It'll clear on the next sync."
                showingError = true
            }
        }
    }

    private func endSeason() {
        isProcessing = true

        // Save state for rollback
        let wasActive = season.isActive
        let previousEndDate = season.endDate

        // End the season
        season.archive()

        // Mark for Firestore sync (Phase 2)
        season.needsSync = true

        Task {
            do {
                try modelContext.save()

                // Track season end analytics
                let gameCount = season.games?.count ?? 0
                AnalyticsService.shared.trackSeasonEnded(
                    seasonID: season.id.uuidString,
                    totalGames: gameCount
                )

                // Trigger immediate sync to Firestore
                if let user = season.athlete?.user {
                    do {
                        try await SyncCoordinator.shared.syncSeasons(for: user)
                    } catch {
                        ErrorHandlerService.shared.handle(error, context: "SeasonManagement.syncSeasons", showAlert: false)
                    }
                }

                withAnimation {
                    isProcessing = false
                }
                Haptics.medium()
                successTitle = "Season Archived"
                successMessage = "\(season.displayName) has been ended and archived."
                showingSuccess = true
            } catch {
                // Rollback on failure
                if wasActive {
                    season.activate()
                }
                season.endDate = previousEndDate

                isProcessing = false
                errorMessage = "Failed to end season: \(error.localizedDescription)"
                showingError = true
            }
        }
    }

    private func renameSeason(to newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard trimmedName != season.name else { return }

        isProcessing = true

        // Save state for rollback
        let oldName = season.name
        let oldClipSeasonNames: [(VideoClip, String)] = (season.videoClips ?? []).map { ($0, $0.seasonName ?? "") }

        // Update season name
        season.name = trimmedName
        season.needsSync = true

        // Batch-update all VideoClips with the new season name
        for clip in season.videoClips ?? [] {
            clip.seasonName = season.displayName
            if clip.firestoreId != nil {
                clip.needsSync = true
            }
        }

        Task {
            do {
                try modelContext.save()

                // Trigger sync for both season and video metadata
                if let user = season.athlete?.user {
                    do {
                        try await SyncCoordinator.shared.syncSeasons(for: user)
                    } catch {
                        ErrorHandlerService.shared.handle(error, context: "SeasonManagement.syncSeasons", showAlert: false)
                    }
                    do {
                        try await SyncCoordinator.shared.syncVideos(for: user)
                    } catch {
                        ErrorHandlerService.shared.handle(error, context: "SeasonManagement.syncVideos", showAlert: false)
                    }
                }

                withAnimation {
                    isProcessing = false
                }
                Haptics.medium()
                successTitle = "Season Renamed"
                successMessage = "Season renamed to \"\(trimmedName)\"."
                showingSuccess = true
            } catch {
                // Rollback season name and clip seasonNames
                season.name = oldName
                for (clip, oldSeasonName) in oldClipSeasonNames {
                    clip.seasonName = oldSeasonName
                }

                isProcessing = false
                errorMessage = "Failed to rename season: \(error.localizedDescription)"
                showingError = true
            }
        }
    }

    private func reactivateSeason() {
        isProcessing = true

        // Capture before any mutations so rollback has the correct reference
        let previousActive = athlete.activeSeason
        let previousActiveWasActive = previousActive?.isActive ?? false
        let previousActiveEndDate = previousActive?.endDate
        let wasActive = season.isActive
        let previousEndDate = season.endDate

        // Archive current active season if exists
        previousActive?.archive()

        // Reactivate this season
        season.activate()

        // Mark for Firestore sync
        season.needsSync = true
        previousActive?.needsSync = true

        Task {
            do {
                try modelContext.save()

                // Track season reactivation analytics
                AnalyticsService.shared.trackSeasonActivated(seasonID: season.id.uuidString)

                // Trigger immediate sync to Firestore
                if let user = season.athlete?.user {
                    do {
                        try await SyncCoordinator.shared.syncSeasons(for: user)
                    } catch {
                        ErrorHandlerService.shared.handle(error, context: "SeasonManagement.syncSeasons", showAlert: false)
                    }
                }

                withAnimation {
                    isProcessing = false
                }
                Haptics.medium()
                successTitle = "Season Reactivated"
                successMessage = "\(season.displayName) is now active."
                showingSuccess = true
            } catch {
                // Rollback on failure
                if previousActiveWasActive {
                    previousActive?.activate()
                    previousActive?.endDate = previousActiveEndDate
                }

                if !wasActive {
                    season.isActive = false
                }
                season.endDate = previousEndDate

                isProcessing = false
                errorMessage = "Failed to reactivate season: \(error.localizedDescription)"
                showingError = true
            }
        }
    }
}
