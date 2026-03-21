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

    private enum PracticeSheet: Identifiable {
        case uploadVideo
        case addNote
        var id: String { String(describing: self) }
    }

    @State private var activeSheet: PracticeSheet?
    @State private var showingRecordCamera = false

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
                        .fontWeight(.semibold)
                    Spacer()
                    Text((practice.date ?? .distantPast).formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Type")
                        .fontWeight(.semibold)
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

                Button(action: { activeSheet = .uploadVideo }) {
                    Label("Upload from Camera Roll", systemImage: "photo.on.rectangle")
                }

                Button(action: { activeSheet = .addNote }) {
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
        .navigationTitle("\(practiceType.displayName) Practice")
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
        // Capture Firestore IDs before deletion
        let userId = practice.athlete?.user?.firebaseAuthUid ?? practice.athlete?.user?.id.uuidString
        let practiceFirestoreId = practice.firestoreId
        var deletedNoteIds: [(String, String)] = [] // (noteFirestoreId, practiceFirestoreId)

        withAnimation {
            for index in offsets {
                let note = notes[index]
                if let noteId = note.firestoreId, let pId = practiceFirestoreId {
                    deletedNoteIds.append((noteId, pId))
                }
                modelContext.delete(note)
            }

            do {
                try modelContext.save()
                Haptics.success()
            } catch {
                Haptics.error()
                log.error("Failed to delete notes: \(error.localizedDescription)")
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
        do {
            try modelContext.save()
            Haptics.success()
        } catch {
            Haptics.error()
            log.error("Failed to delete note: \(error.localizedDescription)")
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

            do {
                try modelContext.save()

                if let athlete = practiceAthlete {
                    try StatisticsService.shared.recalculateAthleteStatistics(for: athlete, context: modelContext)
                }

                Haptics.success()
                log.info("Successfully deleted video from practice")
            } catch {
                Haptics.error()
                log.error("Failed to delete video: \(error.localizedDescription)")
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

        do {
            try modelContext.save()

            // Recalculate athlete statistics to reflect the removed play results
            if let athlete = practiceAthlete {
                try StatisticsService.shared.recalculateAthleteStatistics(for: athlete, context: modelContext)
            }

            Haptics.success()
            log.info("Successfully deleted practice")
            dismiss()
        } catch {
            Haptics.error()
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
