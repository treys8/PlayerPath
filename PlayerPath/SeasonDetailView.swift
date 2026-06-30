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
    @Environment(\.ppAccent) private var ppAccent
    @EnvironmentObject private var authManager: ComprehensiveAuthManager

    @State private var showingDeleteConfirmation = false
    @State private var showingReactivateConfirmation = false
    @State private var showingEndSeasonConfirmation = false
    @State private var showingRenameSheet = false
    @State private var editedSeasonName = ""
    @State private var showingDatesSheet = false
    @State private var editedStartDate = Date()
    @State private var editedEndDate = Date()
    @State private var editingEndDate = false
    @State private var isProcessing = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var selectedFilter: SeasonContentFilter = .all
    @State private var showingSuccess = false
    @State private var successTitle = "Success"
    @State private var successMessage = ""
    @State private var videoUploadTrigger = false
    @State private var photoUploadTrigger = false
    /// Season reel export (Plus+): stitch this season's starred clips into one
    /// shareable reel. Free taps route to the paywall.
    @State private var showingReel = false
    @State private var showingReelPaywall = false

    // Cached filtered content arrays to avoid expensive recomputation on every render
    @State private var filteredGames: [Game] = []
    @State private var filteredVideos: [VideoClip] = []
    @State private var filteredHighlights: [VideoClip] = []
    @State private var filteredPractices: [Practice] = []

    var body: some View {
        List {
            // Overview Section
            Section {
                HStack(spacing: 14) {
                    Image(systemName: (season.sport ?? .baseball).icon)
                        .font(.title)
                        .foregroundStyle(ppAccent)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(season.displayName)
                            .font(.ppTitle)
                            .foregroundStyle(Theme.textPrimary)

                        Label(season.status.displayName, systemImage: season.status.icon)
                            .font(.ppCaption)
                            .foregroundStyle(season.isActive ? .green : Theme.textSecondary)
                    }
                }
                .padding(.vertical, 8)
            }

            // Season Recap — year-in-review summary (stats + top moments + reel).
            Section {
                NavigationLink {
                    SeasonRecapView(season: season, athlete: athlete)
                } label: {
                    Label("Season Recap", systemImage: "sparkles.rectangle.stack")
                }
            }
            .labelStyle(ActionRowLabelStyle())

            // Add Content — routes every upload to this season regardless of
            // whether it is active or archived, and regardless of the photo/
            // video capture dates in the library.
            Section(header: Text("Add Content").smallCapsLabel()) {
                Button {
                    videoUploadTrigger = true
                } label: {
                    Label("Upload Videos", systemImage: "video.badge.plus")
                }

                Button {
                    photoUploadTrigger = true
                } label: {
                    Label("Upload Photos", systemImage: "photo.badge.plus")
                }
            }
            .labelStyle(ActionRowLabelStyle())

            // Date Range
            Section(header: Text("Season Dates").smallCapsLabel()) {
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
                            .foregroundStyle(ppAccent)
                    }
                }
            }

            // Content Filter
            Section {
                PPFilterPillRow(
                    options: SeasonContentFilter.allCases,
                    title: { $0.rawValue },
                    selection: $selectedFilter
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            // Statistics - using computed values for live updates (shown for All filter)
            if selectedFilter == .all {
                Section(header: Text("Season Stats").smallCapsLabel()) {
                    LabeledContent("\(season.gameUnitNounPlural) Played", value: "\(season.completedGames)")
                    LabeledContent("Total Videos", value: "\(season.totalVideos)")
                    LabeledContent("Highlights", value: "\(season.highlights.count)")
                    LabeledContent("Practices", value: "\(season.practicesCount)")
                }

                // Baseball Stats (if available)
                if let stats = season.seasonStatistics, stats.atBats > 0 {
                    let avg = stats.battingAverage
                    let avgDisplay = avg >= 1.0 ? "1.000" : String(format: ".%03d", Int(avg * 1000))
                    Section(header: Text("Batting Statistics").smallCapsLabel()) {
                        LabeledContent("Batting Average", value: avgDisplay)
                        LabeledContent("At Bats", value: "\(stats.atBats)")
                        LabeledContent("Hits", value: "\(stats.hits)")
                        LabeledContent("Home Runs", value: "\(stats.homeRuns)")
                        // RBIs omitted — derivable-stats-only (no game context).
                        LabeledContent("Walks", value: "\(stats.walks)")
                        LabeledContent("Strikeouts", value: "\(stats.strikeouts)")
                    }
                }

                // Notes
                if !season.notes.isEmpty {
                    Section(header: Text("Notes").smallCapsLabel()) {
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

                Button {
                    editedStartDate = season.startDate ?? Date()
                    editedEndDate = season.endDate ?? Date()
                    editingEndDate = season.endDate != nil
                    showingDatesSheet = true
                } label: {
                    Label("Edit Season Dates", systemImage: "calendar")
                }

                if season.isActive {
                    Button {
                        Haptics.warning()
                        showingEndSeasonConfirmation = true
                    } label: {
                        Label("End Season", systemImage: "checkmark.circle")
                    }
                } else if season.isArchived {
                    Button {
                        showingReactivateConfirmation = true
                    } label: {
                        Label("Reactivate Season", systemImage: "arrow.counterclockwise")
                    }

                    Button {
                        recalculateStats()
                    } label: {
                        Label("Recalculate Stats", systemImage: "arrow.triangle.2.circlepath")
                    }
                }

                Button(role: .destructive) {
                    Haptics.warning()
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete Season", systemImage: "trash")
                        .labelStyle(DestructiveRowLabelStyle())
                }
            }
            .labelStyle(ActionRowLabelStyle())
        }
        .ppDetailBackground()
        .navigationTitle("Season Details")
        .navigationBarTitleDisplayMode(.inline)
        .bulkImportAttach(athlete: athlete, season: season, trigger: $videoUploadTrigger)
        .bulkPhotoImportAttach(athlete: athlete, season: season, trigger: $photoUploadTrigger)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
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
                        Text("Season Name").smallCapsLabel()
                    } footer: {
                        Text("Enter a new name for this season")
                    }
                }
                .ppDetailBackground()
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
        .sheet(isPresented: $showingDatesSheet) {
            NavigationStack {
                Form {
                    Section {
                        DatePicker("Start Date", selection: $editedStartDate, displayedComponents: .date)

                        if season.isActive {
                            Text("The end date is set automatically when you end this season.")
                                .font(.ppCaption)
                                .foregroundStyle(Theme.textSecondary)
                        } else {
                            Toggle("Set End Date", isOn: $editingEndDate.animation())
                            if editingEndDate {
                                DatePicker("End Date", selection: $editedEndDate, in: editedStartDate..., displayedComponents: .date)
                            }
                        }
                    } header: {
                        Text("Season Dates").smallCapsLabel()
                    } footer: {
                        Text("Changing dates won't move games or videos already in this season.")
                    }

                    if let overlap = overlappingSeason {
                        Section {
                            Label {
                                Text("These dates overlap \(overlap.displayName).")
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Theme.warning)
                            }
                            .font(.ppCaption)
                        }
                    }
                }
                .ppDetailBackground()
                .navigationTitle("Edit Season Dates")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showingDatesSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            showingDatesSheet = false
                            updateSeasonDates()
                        }
                        .disabled(editingEndDate && editedEndDate < editedStartDate)
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
            updateFilteredContent()
        }
        .onChange(of: selectedFilter) { _, _ in
            updateFilteredContent()
        }
        .onChange(of: season.games) { _, _ in
            updateFilteredContent()
        }
        .onChange(of: season.videoClips) { _, _ in
            updateFilteredContent()
        }
        .onChange(of: season.practices) { _, _ in
            updateFilteredContent()
        }
        .fullScreenCover(isPresented: $showingReel) {
            GenerateReelView(
                clips: reelClips,
                scopeKey: "season_\(season.id.uuidString)",
                title: season.displayName
            )
        }
        .sheet(isPresented: $showingReelPaywall) {
            if let user = authManager.localUser {
                ImprovedPaywallView(user: user, requiredTier: .plus)
            }
        }
    }

    // Extracted to a separate @ViewBuilder to keep body small enough for Swift's type checker.
    // Uses pre-computed @State arrays instead of filtering/sorting on every render.
    @ViewBuilder private var filteredContent: some View {
        if selectedFilter == .games || selectedFilter == .all {
            if !filteredGames.isEmpty {
                let totalGames = season.games?.count ?? 0
                let displayGames = selectedFilter == .all ? Array(filteredGames.prefix(5)) : filteredGames
                Section(header: Text(selectedFilter == .all ? "Recent Games" : "Games (\(totalGames))").smallCapsLabel()) {
                    ForEach(displayGames) { game in
                        SeasonGameRow(game: game)
                    }
                    if selectedFilter == .all && totalGames > 5 {
                        Button("See All \(totalGames) Games") { selectedFilter = .games }
                            .font(.ppCallout)
                            .foregroundStyle(ppAccent)
                    }
                }
            }
        }
        if selectedFilter == .videos || selectedFilter == .all {
            if !filteredVideos.isEmpty {
                Section(header: Text("Videos (\(filteredVideos.count))").smallCapsLabel()) {
                    ForEach(selectedFilter == .all ? Array(filteredVideos.prefix(5)) : filteredVideos) { video in
                        SeasonVideoRow(video: video)
                    }
                    if selectedFilter == .all && filteredVideos.count > 5 {
                        Button("See All \(filteredVideos.count) Videos") { selectedFilter = .videos }
                            .font(.ppCallout)
                            .foregroundStyle(ppAccent)
                    }
                }
            }
        }
        if selectedFilter == .highlights || selectedFilter == .all {
            if !filteredHighlights.isEmpty {
                Section(header: Text("Highlights (\(filteredHighlights.count))").smallCapsLabel()) {
                    if reelEligible {
                        Button(action: { generateReelTapped() }) {
                            Label("Generate Season Reel", systemImage: "film.stack")
                        }
                        .font(.ppCallout)
                        .foregroundStyle(ppAccent)
                    }
                    ForEach(selectedFilter == .all ? Array(filteredHighlights.prefix(5)) : filteredHighlights) { video in
                        SeasonVideoRow(video: video)
                    }
                    if selectedFilter == .all && filteredHighlights.count > 5 {
                        Button("See All \(filteredHighlights.count) Highlights") { selectedFilter = .highlights }
                            .font(.ppCallout)
                            .foregroundStyle(ppAccent)
                    }
                }
            }
        }
        if selectedFilter == .practices || selectedFilter == .all {
            if !filteredPractices.isEmpty {
                Section(header: Text("Practices (\(filteredPractices.count))").smallCapsLabel()) {
                    ForEach(selectedFilter == .all ? Array(filteredPractices.prefix(5)) : filteredPractices) { practice in
                        HStack {
                            Image(systemName: "figure.run")
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Practice")
                                    .font(.ppHeadline)
                                    .foregroundStyle(Theme.textPrimary)
                                if let date = practice.date {
                                    Text(date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.ppCaption)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                            Spacer()
                            let videoCount = practice.videoClips?.count ?? 0
                            if videoCount > 0 {
                                Text("\(videoCount) video\(videoCount == 1 ? "" : "s")")
                                    .font(.ppCaption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    if selectedFilter == .all && filteredPractices.count > 5 {
                        Button("See All \(filteredPractices.count) Practices") { selectedFilter = .practices }
                            .font(.ppCallout)
                            .foregroundStyle(ppAccent)
                    }
                }
            }
        }
    }

    /// Starred clips for this season in chronological (playback) order.
    /// `filteredHighlights` is newest-first, so reverse for the reel.
    private var reelClips: [VideoClip] { Array(filteredHighlights.reversed()) }

    /// A reel needs at least two clips.
    private var reelEligible: Bool { filteredHighlights.count >= 2 }

    /// Plus-gated: open the generator, or route free users to the paywall.
    private func generateReelTapped() {
        Haptics.light()
        if SubscriptionGate.effectiveAthleteTier.hasAutoHighlights {
            showingReel = true
        } else {
            showingReelPaywall = true
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

    private func deleteSeason() {
        isProcessing = true
        Task {
            do {
                try await SeasonService.deleteSeason(season, modelContext: modelContext)
                isProcessing = false
                Haptics.medium()
                dismiss()
            } catch {
                isProcessing = false
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func endSeason() {
        isProcessing = true
        Task {
            do {
                try await SeasonService.endSeason(season, modelContext: modelContext)
                withAnimation {
                    isProcessing = false
                }
                Haptics.medium()
                successTitle = "Season Archived"
                successMessage = "\(season.displayName) has been ended and archived."
                showingSuccess = true
            } catch {
                isProcessing = false
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func renameSeason(to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != season.name else { return }

        isProcessing = true
        Task {
            do {
                try await SeasonService.renameSeason(season, to: trimmed, modelContext: modelContext)
                withAnimation {
                    isProcessing = false
                }
                Haptics.medium()
                successTitle = "Season Renamed"
                successMessage = "Season renamed to \"\(trimmed)\"."
                showingSuccess = true
            } catch {
                isProcessing = false
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    /// Sibling season (if any) whose date range overlaps the candidate dates in the editor.
    /// Drives the warn-but-allow overlap note; never blocks the save.
    private var overlappingSeason: Season? {
        let others = (athlete.seasons ?? []).filter { $0.id != season.id }
        return Season.firstOverlapping(
            start: editedStartDate,
            end: editingEndDate ? editedEndDate : nil,
            in: others
        )
    }

    private func updateSeasonDates() {
        isProcessing = true
        Task {
            do {
                try await SeasonService.updateSeasonDates(
                    season,
                    startDate: editedStartDate,
                    endDate: editingEndDate ? editedEndDate : nil,
                    modelContext: modelContext
                )
                withAnimation {
                    isProcessing = false
                }
                Haptics.medium()
                successTitle = "Season Dates Updated"
                successMessage = "\(season.displayName)'s dates were updated."
                showingSuccess = true
            } catch {
                isProcessing = false
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    /// Backstop for the rare case where an archived season's aggregated stats drift
    /// from its games — e.g. a game backfilled into it, or a stat edited through a
    /// path that didn't recalc. `recalculateAthleteStatistics` re-aggregates every
    /// season (archived included), so a single call refreshes this season's totals.
    private func recalculateStats() {
        do {
            try StatisticsService.shared.recalculateAthleteStatistics(for: athlete, context: modelContext)
            Haptics.medium()
            successTitle = "Stats Recalculated"
            successMessage = "\(season.displayName)'s statistics were recalculated from its games."
            showingSuccess = true
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func reactivateSeason() {
        isProcessing = true
        Task {
            do {
                try await SeasonService.reactivateSeason(season, athlete: athlete, modelContext: modelContext)
                withAnimation {
                    isProcessing = false
                }
                Haptics.medium()
                successTitle = "Season Reactivated"
                successMessage = "\(season.displayName) is now active."
                showingSuccess = true
            } catch {
                isProcessing = false
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
}
