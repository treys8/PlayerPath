//
//  PracticesView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import SwiftData
import os
import UIKit

private let log = Logger(subsystem: "com.playerpath.app", category: "Practices")

struct PracticesView: View {
    let athlete: Athlete?
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddPractice = false
    @State private var selectedPractice: Practice?
    @State private var searchText: String = ""
    @State private var selectedSeasonFilter: String? = nil

    enum SortOrder: String, CaseIterable, Identifiable {
        case newestFirst = "Newest First"
        case oldestFirst = "Oldest First"
        case mostVideos = "Most Videos"
        case mostNotes = "Most Notes"

        var id: String { rawValue }
    }

    @State private var sortOrder: SortOrder = .newestFirst
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<Practice.ID>()
    @State private var isBatchProcessing = false

    // Cached arrays (updated via updatePracticesCache)
    @State private var cachedPractices: [Practice] = []
    @State private var cachedFilteredPractices: [Practice] = []
    @State private var cachedPracticesSummary: String = ""
    @State private var cachedAvailableSeasons: [Season] = []

    // Check if filters are active
    private var hasActiveFilters: Bool {
        selectedSeasonFilter != nil ||
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Check if we have any practices at all (before filtering)
    private var hasAnyPractices: Bool {
        !(athlete?.practices?.isEmpty ?? true)
    }

    private func updatePracticesCache() {
        // Sort practices
        let items = athlete?.practices ?? []
        switch sortOrder {
        case .newestFirst:
            cachedPractices = items.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        case .oldestFirst:
            cachedPractices = items.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        case .mostVideos:
            cachedPractices = items.sorted { ($0.videoClips?.count ?? 0) > ($1.videoClips?.count ?? 0) }
        case .mostNotes:
            cachedPractices = items.sorted { ($0.notes?.count ?? 0) > ($1.notes?.count ?? 0) }
        }

        // Filter practices
        var filtered: [Practice] = cachedPractices
        if let seasonFilter = selectedSeasonFilter {
            filtered = filtered.filter { practice in
                if seasonFilter == "no_season" {
                    return practice.season == nil
                } else {
                    return practice.season?.id.uuidString == seasonFilter
                }
            }
        }
        let trimmed: String = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let q: String = trimmed.lowercased()
            filtered = filtered.filter { practice in
                matchesSearch(practice, query: q)
            }
        }
        cachedFilteredPractices = filtered

        // Compute summary
        cachedPracticesSummary = computePracticesSummary(from: filtered)

        // Available seasons
        let seasons = (athlete?.practices ?? []).compactMap { $0.season }
        let uniqueSeasons = Array(Set(seasons))
        cachedAvailableSeasons = uniqueSeasons.sorted { ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast) }
    }

    private var filterDescription: String {
        var parts: [String] = []

        if let seasonID = selectedSeasonFilter {
            if seasonID == "no_season" {
                parts.append("season: None")
            } else if let season = cachedAvailableSeasons.first(where: { $0.id.uuidString == seasonID }) {
                parts.append("season: \(season.displayName)")
            }
        }

        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("search: \"\(searchText)\"")
        }

        return parts.isEmpty ? "your filters" : parts.joined(separator: ", ")
    }

    private func clearAllFilters() {
        Haptics.light()
        withAnimation {
            selectedSeasonFilter = nil
            searchText = ""
        }
    }
    
    private func matchesSearch(_ practice: Practice, query q: String) -> Bool {
        let dateString: String = (practice.date ?? .distantPast)
            .formatted(date: .abbreviated, time: .omitted)
            .lowercased()

        let matchesDate: Bool = dateString.contains(q)
        let matchesSeason: Bool = practice.season?.displayName.lowercased().contains(q) ?? false
        let matchesNotes: Bool = (practice.notes ?? []).contains { note in
            note.content.lowercased().contains(q)
        }

        return matchesDate || matchesSeason || matchesNotes
    }
    
    @ViewBuilder
    private var practicesContent: some View {
        if cachedFilteredPractices.isEmpty {
            if hasActiveFilters && hasAnyPractices {
                FilteredEmptyStateView(
                    filterDescription: filterDescription,
                    onClearFilters: clearAllFilters
                )
            } else {
                EmptyPracticesView {
                    showingAddPractice = true
                }
            }
        } else {
            practicesListContent
        }
    }

    @ViewBuilder
    private var practicesListContent: some View {
        VStack(spacing: 0) {
            if let athlete = athlete {
                let seasonRecommendation = SeasonManager.checkSeasonStatus(for: athlete)
                if seasonRecommendation.message != nil {
                    SeasonRecommendationBanner(athlete: athlete, recommendation: seasonRecommendation)
                        .padding()
                }
            }

            List(selection: $selection) {
                if !cachedFilteredPractices.isEmpty && editMode == .inactive {
                    HStack {
                        Image(systemName: "chart.bar.fill")
                            .foregroundStyle(.green)
                            .font(.caption)

                        Text(cachedPracticesSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.8)

                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                ForEach(cachedFilteredPractices, id: \.persistentModelID) { practice in
                    if editMode == .active {
                        PracticeRow(practice: practice)
                            .tag(practice.id)
                    } else {
                        PracticeListRow(practice: practice) {
                            deleteSinglePractice(practice)
                        }
                    }
                }
                .onDelete { offsets in deletePracticesFromFiltered(offsets: offsets) }
            }
            .environment(\.editMode, $editMode)
            .refreshable {
                await refreshPractices()
            }
            .safeAreaInset(edge: .bottom) {
                if editMode == .active {
                    bottomToolbar
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var practicesToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: { showingAddPractice = true }) {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add Practice")
        }

        if !cachedPractices.isEmpty {
            ToolbarItem(placement: .topBarLeading) {
                SeasonFilterMenu(
                    selectedSeasonID: $selectedSeasonFilter,
                    availableSeasons: cachedAvailableSeasons,
                    showNoSeasonOption: (athlete?.practices ?? []).contains(where: { $0.season == nil })
                )
            }
        }

        if !cachedPractices.isEmpty && editMode == .inactive {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sortOrder) {
                        ForEach(SortOrder.allCases) { order in
                            Label(order.rawValue, systemImage: getSortIcon(order)).tag(order)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                }
                .accessibilityLabel("Sort practices")
            }
        }

        if !cachedPractices.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation {
                        if editMode == .active {
                            editMode = .inactive
                            selection.removeAll()
                        } else {
                            editMode = .active
                        }
                    }
                } label: {
                    Text(editMode == .active ? "Done" : "Edit")
                }
            }
        }
    }

    var body: some View {
        practicesContent
        .onAppear {
            AnalyticsService.shared.trackScreenView(screenName: "Practices", screenClass: "PracticesView")
            updatePracticesCache()
        }
        .onChange(of: searchText) { _, _ in updatePracticesCache() }
        .onChange(of: selectedSeasonFilter) { _, _ in updatePracticesCache() }
        .onChange(of: sortOrder) { _, _ in updatePracticesCache() }
        .onChange(of: athlete?.practices?.count) { _, _ in updatePracticesCache() }
        .navigationTitle("Practices")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic))
        .toolbar { practicesToolbar }
        .sheet(isPresented: $showingAddPractice) {
            AddPracticeView(athlete: athlete)
        }
    }
    
    private func deleteSinglePractice(_ practice: Practice) {
        let practiceAthlete = practice.athlete

        withAnimation {
            practice.delete(in: modelContext)

            Task {
                do {
                    try modelContext.save()

                    // Recalculate athlete statistics to reflect the removed play results
                    if let athlete = practiceAthlete {
                        try StatisticsService.shared.recalculateAthleteStatistics(for: athlete, context: modelContext)
                    }

                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    log.info("Successfully deleted practice")
                } catch {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    log.error("Failed to delete practice: \(error.localizedDescription)")
                }
            }
        }
    }

    private func deletePracticesFromFiltered(offsets: IndexSet) {
        let toDelete = offsets.compactMap { index in
            index < cachedFilteredPractices.count ? cachedFilteredPractices[index] : nil
        }
        let practiceAthlete = toDelete.first?.athlete

        withAnimation {
            for practice in toDelete {
                practice.delete(in: modelContext)
            }

            Task {
                do {
                    try modelContext.save()

                    // Recalculate athlete statistics to reflect the removed play results
                    if let athlete = practiceAthlete {
                        try StatisticsService.shared.recalculateAthleteStatistics(for: athlete, context: modelContext)
                    }

                    Haptics.success()
                    log.info("Successfully deleted \(toDelete.count) practices")
                } catch {
                    Haptics.error()
                    log.error("Failed to delete practices: \(error.localizedDescription)")
                }
            }
        }
    }

    @MainActor
    private func refreshPractices() async {
        Haptics.light()
        // Practices automatically refresh via SwiftData
    }

    private static let summaryDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    private func computePracticesSummary(from practices: [Practice]) -> String {
        let practiceCount = practices.count
        guard practiceCount > 0 else { return "" }

        let videoCount = practices.reduce(0) { $0 + ($1.videoClips?.count ?? 0) }
        let noteCount = practices.reduce(0) { $0 + ($1.notes?.count ?? 0) }

        let dates = practices.compactMap(\.date)
        guard let oldest = dates.min(), let newest = dates.max() else {
            return "\(practiceCount) practice\(practiceCount == 1 ? "" : "s") • \(videoCount) videos"
        }

        let dateRange = "\(Self.summaryDateFormatter.string(from: oldest)) - \(Self.summaryDateFormatter.string(from: newest))"

        return "\(practiceCount) practices • \(videoCount) videos • \(noteCount) notes • \(dateRange)"
    }

    private func getSortIcon(_ order: SortOrder) -> String {
        switch order {
        case .newestFirst:
            return "arrow.down"
        case .oldestFirst:
            return "arrow.up"
        case .mostVideos:
            return "video"
        case .mostNotes:
            return "note.text"
        }
    }

    private var bottomToolbar: some View {
        HStack(spacing: 20) {
            Menu {
                Button(role: .destructive) {
                    batchDeleteSelected()
                } label: {
                    Label("Delete", systemImage: "trash")
                }

                Button {
                    batchAssignToActiveSeason()
                } label: {
                    Label("Assign to Active Season", systemImage: "calendar.badge.plus")
                }
            } label: {
                Label("Actions", systemImage: "ellipsis.circle")
            }
            .disabled(selection.isEmpty || isBatchProcessing)

            Spacer()

            Button {
                selectAll()
            } label: {
                Label("Select All", systemImage: "checkmark.circle")
            }
            .disabled(cachedPractices.isEmpty)

            Spacer()

            Button {
                selection.removeAll()
            } label: {
                Label("Deselect All", systemImage: "xmark.circle")
            }
            .disabled(selection.isEmpty)
        }
        .padding()
        .background(.regularMaterial)
    }

    private func selectAll() {
        Haptics.light()
        selection = Set(cachedFilteredPractices.map { $0.id })
    }

    private func batchDeleteSelected() {
        let toDelete = cachedPractices.filter { selection.contains($0.id) }
        guard !toDelete.isEmpty else { return }
        guard !isBatchProcessing else { return }
        isBatchProcessing = true

        // Sync deletions to Firestore with retry
        for practice in toDelete {
            if let firestoreId = practice.firestoreId,
               let athlete = practice.athlete,
               let user = athlete.user {
                let userId = user.id.uuidString
                Task {
                    for attempt in 1...3 {
                        do {
                            try await FirestoreManager.shared.deletePractice(
                                userId: userId,
                                practiceId: firestoreId
                            )
                            log.info("Practice deletion synced to Firestore")
                            return
                        } catch {
                            log.warning("Failed to sync practice deletion (attempt \(attempt)/3): \(error.localizedDescription)")
                            if attempt < 3 {
                                try? await Task.sleep(for: .seconds(2))
                            }
                        }
                    }
                }
            }
        }

        let practiceAthlete = toDelete.first?.athlete

        withAnimation {
            for practice in toDelete {
                practice.delete(in: modelContext)
            }

            Task {
                do {
                    try modelContext.save()

                    // Recalculate athlete statistics to reflect the removed play results
                    if let athlete = practiceAthlete {
                        try StatisticsService.shared.recalculateAthleteStatistics(for: athlete, context: modelContext)
                    }

                    Haptics.success()
                    log.info("Successfully deleted \(toDelete.count) practices")
                } catch {
                    Haptics.error()
                    log.error("Failed to delete practices: \(error.localizedDescription)")
                }

                isBatchProcessing = false
                selection.removeAll()
                editMode = .inactive
            }
        }
    }

    private func batchAssignToActiveSeason() {
        guard let athlete = athlete else { return }
        let toAssign = cachedPractices.filter { selection.contains($0.id) }
        guard !toAssign.isEmpty else { return }
        guard !isBatchProcessing else { return }
        isBatchProcessing = true

        withAnimation {
            for practice in toAssign {
                SeasonManager.linkPracticeToActiveSeason(practice, for: athlete, in: modelContext)
            }

            Task {
                do {
                    try modelContext.save()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    log.info("Successfully assigned \(toAssign.count) practices to active season")
                    Haptics.success()
                } catch {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    log.error("Failed to assign practices: \(error.localizedDescription)")
                    Haptics.error()
                }

                isBatchProcessing = false
                selection.removeAll()
                editMode = .inactive
            }
        }
    }
}

struct PracticeListRow: View {
    let practice: Practice
    let onDelete: () -> Void

    var body: some View {
        NavigationLink(destination: PracticeDetailView(practice: practice)) {
            PracticeRow(practice: practice)
        }
        .swipeActions {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

struct EmptyPracticesView: View {
    let onAddPractice: () -> Void

    var body: some View {
        EmptyStateView(
            systemImage: "figure.baseball",
            title: "No Practice Sessions Yet",
            message: "Create your first practice to track training",
            actionTitle: "Add Practice",
            action: onAddPractice
        )
    }
}

struct PracticeRow: View {
    let practice: Practice

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text((practice.date ?? .distantPast).formatted(date: .abbreviated, time: .omitted))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.8)

                if let season = practice.season {
                    SeasonBadge(season: season, fontSize: 8)
                }

                Spacer()

                HStack(spacing: 6) {
                    Label("\((practice.videoClips ?? []).count)", systemImage: "video")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.blue)
                    Text("\((practice.videoClips ?? []).count)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.thinMaterial)
                        .clipShape(Capsule())
                }
            }

            if !(practice.notes ?? []).isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "note.text")
                        .foregroundStyle(.secondary)
                    Text("\((practice.notes ?? []).count)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.thinMaterial)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct AddPracticeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let athlete: Athlete?
    
    @State private var date = Date()
    @State private var shouldUploadVideo = false
    @State private var createdPractice: Practice?
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Practice Details") {
                    DatePicker("Practice Date", selection: $date, displayedComponents: [.date])
                }
                
                Section("Video Options") {
                    Toggle("Upload video after creating practice", isOn: $shouldUploadVideo)
                        .toggleStyle(SwitchToggleStyle(tint: .green))
                    
                    if shouldUploadVideo {
                        HStack {
                            Image(systemName: "video.badge.plus")
                                .foregroundStyle(.green)
                            Text("Video will be uploaded after practice is created")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("New Practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        savePractice()
                    }
                }
            }
        }
        .fullScreenCover(item: $createdPractice) { practice in
            DirectCameraRecorderView(athlete: athlete, practice: practice)
        }
    }
    
    private func savePractice() {
        guard let athlete = athlete else { return }
        
        let practice = Practice(date: date)
        practice.athlete = athlete

        // Mark for Firestore sync (Phase 3)
        practice.needsSync = true

        if athlete.practices == nil {
            athlete.practices = []
        }
        athlete.practices?.append(practice)
        modelContext.insert(practice)

        // ✅ Link practice to active season
        SeasonManager.linkPracticeToActiveSeason(practice, for: athlete, in: modelContext)

        do {
            try modelContext.save()

            // Track practice creation analytics
            AnalyticsService.shared.trackPracticeCreated(
                practiceID: practice.id.uuidString,
                seasonID: practice.season?.id.uuidString
            )

            // Trigger immediate sync to Firestore
            Task {
                if let user = athlete.user {
                    do {
                        try await SyncCoordinator.shared.syncPractices(for: user)
                    } catch {
                        // Don't block practice creation on sync failure
                    }
                }
            }

            UINotificationFeedbackGenerator().notificationOccurred(.success)

            if shouldUploadVideo {
                createdPractice = practice
            } else {
                dismiss()
            }
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            log.error("Failed to save practice: \(error.localizedDescription)")
        }
    }
}

struct PracticeDetailView: View {
    let practice: Practice
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @State private var selectedVideo: VideoClip?
    @State private var showingDeleteConfirmation = false
    
    private enum PracticeSheet: Identifiable {
        case uploadVideo
        case addNote
        var id: String { String(describing: self) }
    }

    @State private var activeSheet: PracticeSheet?
    @State private var showingRecordCamera = false
    
    var videoClips: [VideoClip] {
        (practice.videoClips ?? []).sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }
    
    var notes: [PracticeNote] {
        (practice.notes ?? []).sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }
    
    var body: some View {
        List {
            // Practice Info Section
            Section("Practice Details") {
                HStack {
                    Text("Date")
                        .fontWeight(.semibold)
                    Spacer()
                    Text((practice.date ?? .distantPast).formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(.secondary)
                }
            }
            
            // Actions Section
            Section("Actions") {
                Button(action: { showingRecordCamera = true }) {
                    Label("Record Video", systemImage: "video.badge.plus")
                }

                Button(action: { activeSheet = .uploadVideo }) {
                    Label("Upload from Camera Roll", systemImage: "photo.on.rectangle")
                }

                Button(action: { activeSheet = .addNote }) {
                    Label("Add Note", systemImage: "note.text.badge.plus")
                }
                
                Button(role: .destructive, action: {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    showingDeleteConfirmation = true
                }) {
                    Label("Delete Practice", systemImage: "trash")
                }
            }
            
            // Videos Section
            Section("Videos (\(videoClips.count))") {
                if videoClips.isEmpty {
                    Button(action: { showingRecordCamera = true }) {
                        Label("Record your first video", systemImage: "video.badge.plus")
                    }
                } else {
                    ForEach(videoClips) { clip in
                        PracticeVideoClipRow(clip: clip, hasCoachingAccess: authManager.hasCoachingAccess, onPlay: { selectedVideo = clip })
                    }
                }
            }
            
            // Notes Section
            Section("Notes (\(notes.count))") {
                if notes.isEmpty {
                    Button(action: { activeSheet = .addNote }) {
                        Label("Add your first note", systemImage: "note.text.badge.plus")
                    }
                } else {
                    ForEach(notes) { note in
                        PracticeNoteRow(note: note)
                            .swipeActions {
                                Button(role: .destructive) { delete(note: note) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                    .onDelete(perform: deleteNotes)
                }
            }
        }
        .navigationTitle("Practice")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showingRecordCamera) {
            DirectCameraRecorderView(athlete: practice.athlete, practice: practice)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .uploadVideo:
                VideoRecorderView_Refactored(athlete: practice.athlete, practice: practice)
            case .addNote:
                AddPracticeNoteView(practice: practice)
            }
        }
        .fullScreenCover(item: $selectedVideo) { video in
            VideoPlayerView(clip: video)
        }
        .alert("Delete Practice", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deletePractice()
            }
        } message: {
            Text("This will delete all videos and notes.")
        }
    }
    
    private func deleteNotes(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let note = notes[index]
                modelContext.delete(note)
            }
            
            do {
                try modelContext.save()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                log.error("Failed to delete notes: \(error.localizedDescription)")
            }
        }
    }
    
    private func delete(note: PracticeNote) {
        modelContext.delete(note)
        do {
            try modelContext.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            log.error("Failed to delete note: \(error.localizedDescription)")
        }
    }
    
    private func deletePractice() {
        // Sync deletion to Firestore if practice was synced
        if let firestoreId = practice.firestoreId,
           let athlete = practice.athlete,
           let user = athlete.user {
            let userId = user.id.uuidString
            Task {
                for attempt in 1...3 {
                    do {
                        try await FirestoreManager.shared.deletePractice(
                            userId: userId,
                            practiceId: firestoreId
                        )
                        return
                    } catch {
                        if attempt < 3 {
                            try? await Task.sleep(for: .seconds(2))
                        }
                    }
                }
            }
        }

        // Capture athlete before deletion — accessing SwiftData object properties after
        // context.delete() is undefined behavior.
        let practiceAthlete = practice.athlete

        practice.delete(in: modelContext)

        do {
            try modelContext.save()

            // Recalculate athlete statistics to reflect the removed play results
            if let athlete = practiceAthlete {
                try StatisticsService.shared.recalculateAthleteStatistics(for: athlete, context: modelContext)
            }

            UINotificationFeedbackGenerator().notificationOccurred(.success)
            log.info("Successfully deleted practice")
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            log.error("Failed to delete practice: \(error.localizedDescription)")
        }
    }
}

struct PracticeNoteRow: View {
    let note: PracticeNote
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(note.content)
                .font(.subheadline)
            
            if let createdAt = note.createdAt {
                Text(createdAt, formatter: DateFormatter.shortDateTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PracticeVideoClipRow: View {
    let clip: VideoClip
    let hasCoachingAccess: Bool
    var onPlay: (() -> Void)? = nil
    @State private var showingShareToFolder = false
    @State private var showingNoteEditor = false
    @State private var thumbnailImage: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Thumbnail — tappable play button
                Button(action: { onPlay?() }) {
                    Group {
                        if let uiImage = thumbnailImage {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "video.fill")
                                .foregroundStyle(.blue)
                                .font(.title3)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.blue.opacity(0.1))
                        }
                    }
                    .frame(width: 56, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(alignment: .center) {
                        Image(systemName: "play.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(Circle().fill(.black.opacity(0.55)))
                    }
                }
                .buttonStyle(.plain)
                .disabled(onPlay == nil)

                VStack(alignment: .leading, spacing: 2) {
                    Text(clip.createdAt.map { Self.timeFormatter.string(from: $0) } ?? "Practice Clip")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let playResult = clip.playResult {
                        Text(playResult.type.displayName)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .cornerRadius(4)
                    }
                }

                Spacer()

                if let duration = clip.duration {
                    Text(Self.formatDuration(duration))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            // Athlete note preview
            if let note = clip.note, !note.isEmpty {
                Button {
                    showingNoteEditor = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "note.text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }

            // Coach comment thread (loads from Firestore; empty for non-Pro users)
            if let clipId = clip.firestoreId {
                ClipCommentSection(clipId: clipId)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                showingNoteEditor = true
            } label: {
                Label(clip.note?.isEmpty == false ? "Edit Note" : "Add Note", systemImage: "note.text")
            }
            if hasCoachingAccess {
                Button {
                    showingShareToFolder = true
                } label: {
                    Label("Share to Coach Folder", systemImage: "folder.badge.person.fill")
                }
            }
        }
        .sheet(isPresented: $showingShareToFolder) {
            ShareToCoachFolderView(clip: clip)
        }
        .sheet(isPresented: $showingNoteEditor) {
            EditClipNoteSheet(clip: clip)
        }
        .task {
            // Load thumbnail asynchronously instead of synchronously in the view body
            guard thumbnailImage == nil, let thumbPath = clip.thumbnailPath else { return }
            let size = CGSize(width: 112, height: 80)
            if let image = try? await ThumbnailCache.shared.loadThumbnail(at: thumbPath, targetSize: size) {
                thumbnailImage = image
            }
        }
    }

    // "2:45 PM" — readable clip title derived from creation time
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    // Static duration string — "0:24", "1:03", etc.
    private static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Edit Clip Note Sheet

struct EditClipNoteSheet: View {
    let clip: VideoClip
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var noteText: String
    @State private var isSaving = false
    @FocusState private var isFocused: Bool

    init(clip: VideoClip) {
        self.clip = clip
        _noteText = State(initialValue: clip.note ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your note is visible to your coach if you share this video.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 4)

                TextEditor(text: $noteText)
                    .focused($isFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(minHeight: 140)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                    .padding(.horizontal)

                Spacer()
            }
            .navigationTitle(clip.note?.isEmpty == false ? "Edit Note" : "Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isFocused = false }
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveNote() }
                        .disabled(isSaving)
                }
            }
            .overlay {
                if isSaving {
                    ProgressView()
                }
            }
        }
    }

    private func saveNote() {
        isSaving = true
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        clip.note = trimmed.isEmpty ? nil : trimmed
        clip.needsSync = true
        try? modelContext.save()

        // Sync to Firestore if the clip has been uploaded
        if let firestoreId = clip.firestoreId {
            Task {
                try? await VideoCloudManager.shared.updateVideoNote(clipId: firestoreId, note: clip.note)
            }
        }
        isSaving = false
        dismiss()
    }
}

struct AddPracticeNoteView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let practice: Practice
    
    @State private var noteContent = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Note") {
                    TextField("Enter your practice notes...", text: $noteContent, axis: .vertical)
                        .lineLimit(5...10)
                }
            }
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveNote()
                    }
                    .disabled(noteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func saveNote() {
        let note = PracticeNote(content: noteContent.trimmingCharacters(in: .whitespacesAndNewlines))
        note.needsSync = true
        note.practice = practice
        
        if practice.notes == nil {
            practice.notes = []
        }
        practice.notes?.append(note)
        modelContext.insert(note)
        
        do {
            try modelContext.save()

            // Track practice note added analytics
            AnalyticsService.shared.trackPracticeNoteAdded(practiceID: practice.id.uuidString)

            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            log.error("Failed to save note: \(error.localizedDescription)")
        }
    }
}

// Helper extension for practice date formatting
extension DateFormatter {
    static let practiceDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter
    }()
    
    static let shortDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

#Preview {
    PracticesView(athlete: nil)
}
