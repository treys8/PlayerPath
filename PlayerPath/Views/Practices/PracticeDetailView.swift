//
//  PracticeDetailView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import SwiftData
import os

private let log = Logger(subsystem: "com.playerpath.app", category: "Practices")

struct PracticeDetailView: View {
    let practice: Practice
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @State private var selectedVideo: VideoClip?
    @State private var showingDeleteConfirmation = false

    @State private var showingAddNote = false
    @State private var showingRecordCamera = false
    /// Confirms ending the live session (only reachable while `isLive`).
    @State private var showingEndConfirmation = false
    /// Non-nil presents ScoreHoleSheet for the chosen hole (golf practice
    /// rounds only). Cleared on dismissal.
    @State private var scoreHoleTarget: ScoreHoleTarget?

    // Bulk import from Photos — state owned by BulkImportAttach modifier.
    @State private var importTrigger = false
    // Bulk PHOTO import preset to this practice — owned by BulkPhotoImportAttach.
    @State private var photoImportTrigger = false

    private var practiceType: PracticeType {
        practice.type
    }

    private var isPracticeRound: Bool {
        practice.practiceType == PracticeType.practiceRound.rawValue
    }

    /// Type-aware label for ending the live session — "End Session" for a range
    /// session, "End Round" for a practice round (mirrors GameDetailView's golf
    /// "End Round"). Only shown while `practice.isLive`.
    private var endLabel: String {
        practice.practiceType == PracticeType.rangeSession.rawValue ? "End Session" : "End Round"
    }

    /// Sport-aware type list for the in-place Type-change Menu. Falls back to
    /// the union when athlete is missing (shouldn't happen — practice with no
    /// athlete is orphaned — but defensive).
    private var typeMenuOptions: [PracticeType] {
        guard let sport = practice.athlete?.sportType else { return PracticeType.allCases }
        return PracticeType.cases(for: sport)
    }

    private var sortedHoleScores: [HoleScore] {
        (practice.holeScores ?? []).sorted { $0.holeNumber < $1.holeNumber }
    }

    /// Next unscored hole (capped at Practice.holes ?? 18). Used to label the
    /// "Score Hole X" button. Derived inline (matching GameDetailView) rather
    /// than via LiveHoleTracker.currentHole, because the detail screen scores
    /// rounds regardless of live state, while currentHole is gated on `isLive`
    /// for clip attribution.
    private var nextHoleNumber: Int {
        let total = practice.holes ?? 18
        let scoredMax = sortedHoleScores.last?.holeNumber ?? 0
        return min(scoredMax + 1, total)
    }

    var videoClips: [VideoClip] {
        (practice.videoClips ?? []).sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    private var isRangeSession: Bool {
        practice.practiceType == PracticeType.rangeSession.rawValue
    }

    // MARK: Golf practice-round clip grouping (by hole)

    /// Hole numbers (ascending) that have at least one clip — drives the golf
    /// practice-round "by hole" navigation. Keys off clips, not scores, so a
    /// hole filmed but not scored still gets a row.
    private var clipHoleNumbers: [Int] {
        Set((practice.videoClips ?? []).compactMap { $0.holeNumber }).sorted()
    }

    private var unassignedHoleClipCount: Int {
        (practice.videoClips ?? []).filter { $0.holeNumber == nil }.count
    }

    private func clipCount(onHole hole: Int) -> Int {
        (practice.videoClips ?? []).filter { $0.holeNumber == hole }.count
    }

    private func holeScore(_ hole: Int) -> HoleScore? {
        sortedHoleScores.first { $0.holeNumber == hole }
    }

    // MARK: Golf range-session clip grouping (by club)

    /// Clubs in display order that have at least one clip — drives the range
    /// session "by club" navigation.
    private var clubsWithClips: [Club] {
        let present = Set((practice.videoClips ?? []).compactMap { $0.club })
        return Club.allCases.filter { present.contains($0) }
    }

    private var untaggedClubClipCount: Int {
        (practice.videoClips ?? []).filter { $0.club == nil }.count
    }

    private func clipCount(forClub club: Club) -> Int {
        (practice.videoClips ?? []).filter { $0.club == club }.count
    }

    var notes: [PracticeNote] {
        (practice.notes ?? []).sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    var practicePhotos: [Photo] {
        (practice.photos ?? []).sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    var body: some View {
        List {
            // Practice Info Section
            Section(header: Text("Practice Details").smallCapsLabel()) {
                HStack {
                    Text("Date")
                        .font(.headingMedium)
                    Spacer()
                    Text((practice.date ?? .distantPast).formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Type")
                        .font(.headingMedium)
                    Spacer()
                    Menu {
                        ForEach(typeMenuOptions) { type in
                            Button {
                                practice.practiceType = type.rawValue
                                // Practice rounds want a hole count; range
                                // sessions and any baseball type clear it so
                                // LiveHoleTracker's gate stays clean.
                                if type == .practiceRound {
                                    if practice.holes == nil { practice.holes = 18 }
                                } else {
                                    practice.holes = nil
                                }
                                practice.needsSync = true
                                ErrorHandlerService.shared.saveContext(modelContext, caller: "PracticesView.changePracticeType")
                                Haptics.light()
                            } label: {
                                Label(type.displayName, systemImage: type.icon)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: practiceType.icon)
                                .foregroundStyle(practiceType.color)
                            Text(practiceType.displayName)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            // Live practices are act-first: surface the contextual CTAs (Score
            // Hole / Record) right under the details. Non-live practices are
            // watch-first — their CTA block sits at the bottom (see below).
            // End and Delete live only in the `•••` toolbar menu either way.
            if practice.isLive {
                contextualActions
            }

            // Per-hole grid — only renders when at least one hole has been
            // scored on a practice round. Tapping a cell re-opens the score
            // sheet for that hole (edit-in-place via ScoreHoleSheet's
            // existingHole lookup).
            if isPracticeRound && !sortedHoleScores.isEmpty {
                Section(header: Text("Holes").smallCapsLabel()) {
                    HoleScoreGrid(holes: sortedHoleScores) { tapped in
                        scoreHoleTarget = ScoreHoleTarget(holeNumber: tapped.holeNumber)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 8, trailing: 8))
                    .listRowBackground(Color.clear)
                }
            }

            // Videos Section
            Section(header: Text("Videos (\(videoClips.count))").smallCapsLabel()) {
                if videoClips.isEmpty {
                    Button(action: { showingRecordCamera = true }) {
                        Label("Record your first video", systemImage: "video.badge.plus")
                    }
                    .labelStyle(ActionRowLabelStyle())
                } else if isPracticeRound {
                    // Golf practice round — group clips by hole (mirrors
                    // GameDetailView). Each row pushes that hole's clips + score.
                    ForEach(clipHoleNumbers, id: \.self) { hole in
                        holeClipNavRow(holeNumber: hole, count: clipCount(onHole: hole))
                    }
                    if unassignedHoleClipCount > 0 {
                        holeClipNavRow(holeNumber: nil, count: unassignedHoleClipCount)
                    }
                } else if isRangeSession {
                    // Golf range session — group clips by club. A "film every
                    // swing" session is unbrowsable as a flat list.
                    ForEach(clubsWithClips, id: \.self) { club in
                        clubClipNavRow(club: club, count: clipCount(forClub: club))
                    }
                    if untaggedClubClipCount > 0 {
                        clubClipNavRow(club: nil, count: untaggedClubClipCount)
                    }
                } else {
                    ForEach(videoClips) { clip in
                        PracticeVideoClipRow(clip: clip, hasCoachingAccess: authManager.hasCoachingAccess, onPlay: { selectedVideo = clip })
                            .swipeActions {
                                Button(role: .destructive) { deleteVideo(clip) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }

            // Photos Section
            Section(header: Text("Photos (\(practicePhotos.count))").smallCapsLabel()) {
                if practicePhotos.isEmpty {
                    Button(action: { photoImportTrigger = true }) {
                        Label("Add a photo", systemImage: "photo.on.rectangle")
                    }
                    .labelStyle(ActionRowLabelStyle())
                } else {
                    ForEach(practicePhotos) { photo in
                        NavigationLink {
                            PhotoDetailView(photo: photo) {
                                deletePracticePhoto(photo)
                            }
                        } label: {
                            EventPhotoRow(photo: photo)
                        }
                    }
                }
            }

            // Notes Section
            Section(header: Text("Notes (\(notes.count))").smallCapsLabel()) {
                if notes.isEmpty {
                    Button(action: { showingAddNote = true }) {
                        Label("Add your first note", systemImage: "note.text.badge.plus")
                    }
                    .labelStyle(ActionRowLabelStyle())
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

            // Non-live practices are watch-first: the content greets you and
            // the additive CTAs sit at the bottom as the floor.
            if !practice.isLive {
                contextualActions
            }
        }
        .ppDetailBackground()
        .navigationTitle("\(practiceType.displayName) Practice")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { primaryActionMenu }
        .fullScreenCover(isPresented: $showingRecordCamera) {
            DirectCameraRecorderView(athlete: practice.athlete, practice: practice)
        }
        .sheet(isPresented: $showingAddNote) {
            AddPracticeNoteView(practice: practice)
        }
        .sheet(item: $scoreHoleTarget) { target in
            ScoreHoleSheet(practice: practice, holeNumber: target.holeNumber)
        }
        .bulkImportAttach(athlete: practice.athlete, practice: practice, trigger: $importTrigger)
        .bulkPhotoImportAttach(athlete: practice.athlete, practice: practice, trigger: $photoImportTrigger)
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
        .alert(endLabel, isPresented: $showingEndConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("End", role: .destructive) {
                Haptics.heavy()
                endLiveSession()
            }
        } message: {
            // Unlike games, practices stay fully editable after ending — you
            // can keep adding clips/photos/notes; ending only stops the live
            // strip and live-hole clip attribution.
            Text("This ends the live session. You can still add videos, photos, and notes afterward.")
        }
    }

    /// The slimmed in-body action block: only the additive / time-sensitive
    /// actions that belong on a viewer-first page (Score Hole, Record, Upload,
    /// Add Note, Add Photos). End and Delete live solely in `primaryActionMenu`
    /// (the `•••` toolbar menu). Placed under details for live practices, at the
    /// bottom for non-live ones (see `body`).
    @ViewBuilder
    private var contextualActions: some View {
        Section {
            // Score Hole — golf practice rounds only. Promoted first so the
            // primary on-course action is the top tap target.
            if isPracticeRound {
                Button {
                    Haptics.medium()
                    scoreHoleTarget = ScoreHoleTarget(holeNumber: nextHoleNumber)
                } label: {
                    Label("Score Hole \(nextHoleNumber)", systemImage: "flag.fill")
                }
            }

            Button(action: { showingRecordCamera = true }) {
                Label("Record Video", systemImage: "video.badge.plus")
            }

            Button(action: { importTrigger = true }) {
                Label("Upload Video", systemImage: "square.and.arrow.down.on.square")
            }

            Button(action: { showingAddNote = true }) {
                Label("Add Note", systemImage: "note.text.badge.plus")
            }

            Button(action: { photoImportTrigger = true }) {
                Label("Add Photos", systemImage: "photo.on.rectangle")
            }
        }
        .labelStyle(ActionRowLabelStyle())
    }

    /// One row in the golf practice-round "by hole" clip list. Pushes
    /// HoleDetailView for the hole (or the Unassigned bucket when nil).
    @ViewBuilder
    private func holeClipNavRow(holeNumber: Int?, count: Int) -> some View {
        NavigationLink {
            HoleDetailView(round: .practice(practice), holeNumber: holeNumber)
        } label: {
            HStack(spacing: 8) {
                if let holeNumber {
                    Text("Hole \(holeNumber)")
                        .font(.headingMedium)
                    if let score = holeScore(holeNumber) {
                        Text(score.diffLabel)
                            .font(.labelSmall)
                            .foregroundColor(.parRelative(score.diff))
                    }
                } else {
                    Text("Unassigned")
                        .font(.headingMedium)
                }
                Spacer()
                Text("\(count) clip\(count == 1 ? "" : "s")")
                    .font(.bodySmall)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// One row in the golf range-session "by club" clip list. Pushes
    /// ClubDetailView for the club (or the Untagged bucket when nil).
    @ViewBuilder
    private func clubClipNavRow(club: Club?, count: Int) -> some View {
        NavigationLink {
            ClubDetailView(practice: practice, club: club)
        } label: {
            HStack(spacing: 8) {
                Text(club?.displayName ?? "Untagged")
                    .font(.headingMedium)
                Spacer()
                Text("\(count) clip\(count == 1 ? "" : "s")")
                    .font(.bodySmall)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The `•••` toolbar menu — sole home for the editorial/destructive actions
    /// (End, Delete), plus the additive actions mirrored for reach from
    /// anywhere on the page. Mirrors GameDetailView's primaryActionMenu so the
    /// two event detail pages behave consistently.
    @ToolbarContentBuilder
    private var primaryActionMenu: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                // End the live session — keeps the practice, just clears isLive
                // so it leaves the "Live Now" strip. Only reachable while live.
                if practice.isLive {
                    Button(action: { Haptics.warning(); showingEndConfirmation = true }) {
                        Label(endLabel, systemImage: "stop.circle")
                    }
                }

                if isPracticeRound {
                    Button(action: {
                        Haptics.medium()
                        scoreHoleTarget = ScoreHoleTarget(holeNumber: nextHoleNumber)
                    }) {
                        Label("Score Hole \(nextHoleNumber)", systemImage: "flag.fill")
                    }
                }

                Button(action: { showingRecordCamera = true }) {
                    Label("Record Video", systemImage: "video.badge.plus")
                }
                Button(action: { importTrigger = true }) {
                    Label("Upload Video", systemImage: "square.and.arrow.down.on.square")
                }
                Button(action: { showingAddNote = true }) {
                    Label("Add Note", systemImage: "note.text.badge.plus")
                }
                Button(action: { photoImportTrigger = true }) {
                    Label("Add Photos", systemImage: "photo.on.rectangle")
                }

                Divider()

                Button(role: .destructive, action: {
                    Haptics.warning()
                    showingDeleteConfirmation = true
                }) {
                    Label("Delete Practice", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
        }
    }

    /// Clear the live flags via PracticeService (handles save + Firestore sync).
    private func endLiveSession() {
        Task { @MainActor in
            await PracticeService(modelContext: modelContext).end(practice)
        }
    }

    private func deleteNotes(offsets: IndexSet) {
        // Capture Firestore IDs before deletion
        let userId = practice.athlete?.user?.firebaseAuthUid ?? practice.athlete?.user?.id.uuidString
        let practiceFirestoreId = practice.firestoreId
        var deletedNoteIds: [(String, String)] = [] // (noteFirestoreId, practiceFirestoreId)

        // Snapshot the sorted array so indices match what ForEach rendered
        let currentNotes = notes

        withAnimation {
            for index in offsets {
                guard index < currentNotes.count else { continue }
                let note = currentNotes[index]
                if let noteId = note.firestoreId, let pId = practiceFirestoreId {
                    deletedNoteIds.append((noteId, pId))
                }
                modelContext.delete(note)
            }

            if ErrorHandlerService.shared.saveContext(modelContext, caller: "PracticeDetailView.deleteNotes") {
                Haptics.success()
            } else {
                Haptics.error()
            }
        }

        // Sync deletions to Firestore
        if let userId, !deletedNoteIds.isEmpty {
            Task {
                for (noteId, pId) in deletedNoteIds {
                    await retryAsync {
                        try await FirestoreManager.shared.deletePracticeNote(userId: userId, practiceFirestoreId: pId, noteId: noteId)
                    }
                }
            }
        }
    }

    private func delete(note: PracticeNote) {
        let noteFirestoreId = note.firestoreId
        let userId = practice.athlete?.user?.firebaseAuthUid ?? practice.athlete?.user?.id.uuidString
        let practiceFirestoreId = practice.firestoreId

        modelContext.delete(note)
        if ErrorHandlerService.shared.saveContext(modelContext, caller: "PracticeDetailView.deleteNote") {
            Haptics.success()
        } else {
            Haptics.error()
        }

        // Sync deletion to Firestore
        if let noteFirestoreId, let userId, let practiceFirestoreId {
            Task {
                await retryAsync {
                    try await FirestoreManager.shared.deletePracticeNote(userId: userId, practiceFirestoreId: practiceFirestoreId, noteId: noteFirestoreId)
                }
            }
        }
    }

    private func deletePracticePhoto(_ photo: Photo) {
        PhotoPersistenceService().deletePhoto(photo, context: modelContext)
        Haptics.light()
    }

    private func deleteVideo(_ clip: VideoClip) {
        let practiceAthlete = practice.athlete

        withAnimation {
            clip.delete(in: modelContext)

            if ErrorHandlerService.shared.saveContext(modelContext, caller: "PracticeDetailView.deleteVideo") {
                if let athlete = practiceAthlete {
                    try? StatisticsService.shared.recalculateAthleteStatistics(for: athlete, context: modelContext)
                }
                Haptics.success()
            } else {
                Haptics.error()
            }
        }
    }

    private func deletePractice() {
        // Sync deletion to Firestore if practice was synced
        if let firestoreId = practice.firestoreId,
           let athlete = practice.athlete,
           let user = athlete.user {
            let userId = user.id.uuidString
            Task {
                await retryAsync {
                    try await FirestoreManager.shared.deletePractice(userId: userId, practiceId: firestoreId)
                }
            }
        }

        // Capture athlete before deletion — accessing SwiftData object properties after
        // context.delete() is undefined behavior.
        let practiceAthlete = practice.athlete

        practice.delete(in: modelContext)

        if ErrorHandlerService.shared.saveContext(modelContext, caller: "PracticeDetailView.deletePractice") {
            if let athlete = practiceAthlete {
                try? StatisticsService.shared.recalculateAthleteStatistics(for: athlete, context: modelContext)
            }
            Haptics.success()
            dismiss()
        } else {
            Haptics.error()
        }
    }
}

struct PracticeNoteRow: View {
    let note: PracticeNote

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(note.content)
                .font(.bodyMedium)

            if let createdAt = note.createdAt {
                Text(createdAt, formatter: DateFormatter.shortDateTime)
                    .font(.bodySmall)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
