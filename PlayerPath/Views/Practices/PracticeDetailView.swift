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

    // Bulk import from Photos — state owned by BulkImportAttach modifier.
    @State private var importTrigger = false

    private var practiceType: PracticeType {
        practice.type
    }

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
                        ForEach(PracticeType.allCases) { type in
                            Button {
                                practice.practiceType = type.rawValue
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

            // Actions Section
            Section("Actions") {
                Button(action: { showingRecordCamera = true }) {
                    Label("Record Video", systemImage: "video.badge.plus")
                }

                Button(action: { importTrigger = true }) {
                    Label("Upload Video", systemImage: "square.and.arrow.down.on.square")
                }

                Button(action: { showingAddNote = true }) {
                    Label("Add Note", systemImage: "note.text.badge.plus")
                }

                Button(role: .destructive, action: {
                    Haptics.warning()
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
                            .swipeActions {
                                Button(role: .destructive) { deleteVideo(clip) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }

            // Notes Section
            Section("Notes (\(notes.count))") {
                if notes.isEmpty {
                    Button(action: { showingAddNote = true }) {
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
        .navigationTitle("\(practiceType.displayName) Practice")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showingRecordCamera) {
            DirectCameraRecorderView(athlete: practice.athlete, practice: practice)
        }
        .sheet(isPresented: $showingAddNote) {
            AddPracticeNoteView(practice: practice)
        }
        .bulkImportAttach(athlete: practice.athlete, practice: practice, trigger: $importTrigger)
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
