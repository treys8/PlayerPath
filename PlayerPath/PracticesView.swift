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

    var practices: [Practice] {
        let items = athlete?.practices ?? []
        switch sortOrder {
        case .newestFirst:
            return items.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        case .oldestFirst:
            return items.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        case .mostVideos:
            return items.sorted { ($0.videoClips?.count ?? 0) > ($1.videoClips?.count ?? 0) }
        case .mostNotes:
            return items.sorted { ($0.notes?.count ?? 0) > ($1.notes?.count ?? 0) }
        }
    }

    // Get all unique seasons from practices
    private var availableSeasons: [Season] {
        let seasons = (athlete?.practices ?? []).compactMap { $0.season }
        let uniqueSeasons = Array(Set(seasons))
        return uniqueSeasons.sorted { ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast) }
    }

    // Check if filters are active
    private var hasActiveFilters: Bool {
        selectedSeasonFilter != nil ||
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Check if we have any practices at all (before filtering)
    private var hasAnyPractices: Bool {
        !(athlete?.practices?.isEmpty ?? true)
    }

    var filteredPractices: [Practice] {
        var items: [Practice] = practices

        // Filter by season
        if let seasonFilter = selectedSeasonFilter {
            items = items.filter { practice in
                if seasonFilter == "no_season" {
                    return practice.season == nil
                } else {
                    return practice.season?.id.uuidString == seasonFilter
                }
            }
        }

        // Filter by search text
        let trimmed: String = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }

        let q: String = trimmed.lowercased()
        return items.filter { practice in
            matchesSearch(practice, query: q)
        }
    }

    private var filterDescription: String {
        var parts: [String] = []

        if let seasonID = selectedSeasonFilter {
            if seasonID == "no_season" {
                parts.append("season: None")
            } else if let season = availableSeasons.first(where: { $0.id.uuidString == seasonID }) {
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
        // Precompute components to help the type-checker and keep the filter closure small
        let dateValue: Date = practice.date ?? .distantPast
        let dateString: String = dateValue
            .formatted(date: .abbreviated, time: .omitted)
            .lowercased()

        let videoCount: Int = (practice.videoClips ?? []).count
        let noteCount: Int = (practice.notes ?? []).count

        let videoCountString: String = String(videoCount)
        let noteCountString: String = String(noteCount)

        let matchesDate: Bool = dateString.contains(q)
        let matchesVideoCount: Bool = videoCountString.contains(q)
        let matchesNoteCount: Bool = noteCountString.contains(q)

        // NEW: Search notes content
        let matchesNotes: Bool = (practice.notes ?? []).contains { note in
            note.content.lowercased().contains(q)
        }

        // NEW: Search season name
        let matchesSeason: Bool = practice.season?.displayName.lowercased().contains(q) ?? false

        return matchesDate || matchesVideoCount || matchesNoteCount || matchesNotes || matchesSeason
    }
    
    var body: some View {
        Group {
            VStack {
                if filteredPractices.isEmpty {
                    if hasActiveFilters && hasAnyPractices {
                        // Filtered empty state
                        FilteredEmptyStateView(
                            filterDescription: filterDescription,
                            onClearFilters: clearAllFilters
                        )
                    } else {
                        // True empty state
                        EmptyPracticesView {
                            showingAddPractice = true
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        // Season recommendation banner
                        if let athlete = athlete {
                            let seasonRecommendation = SeasonManager.checkSeasonStatus(for: athlete)
                            if seasonRecommendation.message != nil {
                                SeasonRecommendationBanner(athlete: athlete, recommendation: seasonRecommendation)
                                    .padding()
                            }
                        }

                        // Statistics summary
                        if !practices.isEmpty && editMode == .inactive {
                            HStack {
                                Image(systemName: "chart.bar.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)

                                Text(practicesSummary)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)

                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(Color(.secondarySystemBackground))
                        }

                        List(selection: $selection) {
                            ForEach(filteredPractices, id: \.persistentModelID) { practice in
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
            }
        }
        .navigationTitle("Practices (\(practices.count))")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic))
        .animation(.default, value: filteredPractices.count)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAddPractice = true }) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Practice")
            }

            // Season filter
            if !practices.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    SeasonFilterMenu(
                        selectedSeasonID: $selectedSeasonFilter,
                        availableSeasons: availableSeasons,
                        showNoSeasonOption: (athlete?.practices ?? []).contains(where: { $0.season == nil })
                    )
                }
            }

            // Sort menu
            if !practices.isEmpty && editMode == .inactive {
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

            // Edit button
            if !practices.isEmpty {
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
        .sheet(isPresented: $showingAddPractice) {
            AddPracticeView(athlete: athlete)
        }
    }
    
    private func deleteSinglePractice(_ practice: Practice) {
        withAnimation {
            practice.delete(in: modelContext)

            do {
                try modelContext.save()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                log.info("Successfully deleted practice")
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                log.error("Failed to delete practice: \(error.localizedDescription)")
            }
        }
    }
    
    private func deletePracticesFromFiltered(offsets: IndexSet) {
        let idsToDelete = offsets.map { filteredPractices[$0].persistentModelID }
        let toDelete = practices.filter { idsToDelete.contains($0.persistentModelID) }
        for practice in toDelete { deleteSinglePractice(practice) }
    }

    @MainActor
    private func refreshPractices() async {
        Haptics.light()
        // Practices automatically refresh via SwiftData
    }

    private var practicesSummary: String {
        let practiceCount = practices.count
        guard practiceCount > 0 else { return "" }

        let videoCount = practices.reduce(0) { $0 + ($1.videoClips?.count ?? 0) }
        let noteCount = practices.reduce(0) { $0 + ($1.notes?.count ?? 0) }

        guard let oldest = practices.last?.date,
              let newest = practices.first?.date else {
            return "\(practiceCount) practice\(practiceCount == 1 ? "" : "s") • \(videoCount) videos"
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        let dateRange = "\(dateFormatter.string(from: oldest)) - \(dateFormatter.string(from: newest))"

        return "\(practiceCount) practices • \(videoCount) videos • \(noteCount) notes • \(dateRange)"
    }

    private func getSortIcon(_ order: SortOrder) -> String {
        switch order {
        case .newestFirst:
            return "arrow.down"
        case .oldestFirst:
            return "arrow.up"
        case .mostVideos:
            return "video.fill"
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
            .disabled(selection.isEmpty)

            Spacer()

            Button {
                selectAll()
            } label: {
                Label("Select All", systemImage: "checkmark.circle")
            }
            .disabled(practices.isEmpty)

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
        selection = Set(filteredPractices.map { $0.id })
    }

    private func batchDeleteSelected() {
        let toDelete = practices.filter { selection.contains($0.id) }
        guard !toDelete.isEmpty else { return }

        withAnimation {
            for practice in toDelete {
                practice.delete(in: modelContext)
            }

            do {
                try modelContext.save()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                log.info("Successfully deleted \(toDelete.count) practices")
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                log.error("Failed to delete practices: \(error.localizedDescription)")
            }
        }

        selection.removeAll()
        editMode = .inactive
    }

    private func batchAssignToActiveSeason() {
        guard let athlete = athlete else { return }
        let toAssign = practices.filter { selection.contains($0.id) }
        guard !toAssign.isEmpty else { return }

        withAnimation {
            for practice in toAssign {
                SeasonManager.linkPracticeToActiveSeason(practice, for: athlete, in: modelContext)
            }

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
        }

        selection.removeAll()
        editMode = .inactive
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
        VStack(spacing: 30) {
            Image(systemName: "figure.baseball")
                .font(.system(size: 80))
                .foregroundColor(.green)
            
            Text("No Practice Sessions Yet")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Create your first practice to track training")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Add Practice", action: onAddPractice)
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .accessibilityLabel("Add Practice")
        }
        .padding()
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
                    .minimumScaleFactor(0.8)

                if let season = practice.season {
                    SeasonBadge(season: season, fontSize: 8)
                }

                Spacer()

                HStack(spacing: 6) {
                    Label("\((practice.videoClips ?? []).count)", systemImage: "video.fill")
                        .labelStyle(.iconOnly)
                        .foregroundColor(.blue)
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
                        .foregroundColor(.secondary)
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
                                .foregroundColor(.green)
                            Text("Video will be uploaded after practice is created")
                                .font(.caption)
                                .foregroundColor(.secondary)
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
        .sheet(item: $createdPractice) { practice in
            VideoRecorderView_Refactored(athlete: athlete, practice: practice)
        }
    }
    
    private func savePractice() {
        guard let athlete = athlete else { return }
        
        let practice = Practice(date: date)
        practice.athlete = athlete
        
        if athlete.practices == nil {
            athlete.practices = []
        }
        athlete.practices?.append(practice)
        modelContext.insert(practice)
        
        // ✅ Link practice to active season
        SeasonManager.linkPracticeToActiveSeason(practice, for: athlete, in: modelContext)
        
        do {
            try modelContext.save()
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
    @State private var showingVideoRecorder = false
    @State private var showingAddNote = false
    @State private var selectedVideo: VideoClip?
    @State private var showingDeleteConfirmation = false
    
    private enum PracticeSheet: Identifiable {
        case recordVideo
        case addNote
        var id: String { String(describing: self) }
    }
    
    @State private var activeSheet: PracticeSheet?
    
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
                        .foregroundColor(.secondary)
                }
            }
            
            // Actions Section
            Section("Actions") {
                Button(action: { activeSheet = .recordVideo }) {
                    Label("Record Video", systemImage: "video.badge.plus")
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
                    Button(action: { activeSheet = .recordVideo }) {
                        Label("Record your first video", systemImage: "video.badge.plus")
                    }
                } else {
                    ForEach(videoClips) { clip in
                        PracticeVideoClipRow(clip: clip)
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
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .recordVideo:
                VideoRecorderView_Refactored(athlete: practice.athlete, practice: practice)
            case .addNote:
                AddPracticeNoteView(practice: practice)
            }
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
        practice.delete(in: modelContext)

        do {
            try modelContext.save()
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
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct PracticeVideoClipRow: View {
    let clip: VideoClip
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "video.fill")
                    .foregroundColor(.blue)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(clip.fileName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    if let playResult = clip.playResult {
                        Text(playResult.type.displayName)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                }
                
                Spacer()
                
                if let createdAt = clip.createdAt {
                    Text(createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
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
        note.practice = practice
        
        if practice.notes == nil {
            practice.notes = []
        }
        practice.notes?.append(note)
        modelContext.insert(note)
        
        do {
            try modelContext.save()
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
