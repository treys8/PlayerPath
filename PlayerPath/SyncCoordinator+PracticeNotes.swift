import Foundation
import SwiftData
import FirebaseAuth
import os

private let syncLog = Logger(subsystem: "com.playerpath.app", category: "Sync")

extension SyncCoordinator {
    // MARK: - Practice Notes Sync

    func syncPracticeNotes(for user: User) async throws {
        guard let context = modelContext else { return }
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let athletes = user.athletes ?? []
        let syncedPractices = athletes.flatMap { $0.practices ?? [] }.filter { $0.firestoreId != nil }

        var syncedNotes: [PracticeNote] = []

        // Phase 1 — upload dirty notes (sequential; dirty notes are typically few).
        for practice in syncedPractices {
            guard let practiceFirestoreId = practice.firestoreId else { continue }

            let dirtyNotes = (practice.notes ?? []).filter { $0.needsSync }
            for note in dirtyNotes {
                do {
                    if let noteFirestoreId = note.firestoreId {
                        try await FirestoreManager.shared.updatePracticeNote(
                            userId: userId,
                            practiceFirestoreId: practiceFirestoreId,
                            noteId: noteFirestoreId,
                            data: note.toFirestoreData(practiceFirestoreId: practiceFirestoreId)
                        )
                    } else {
                        let docId = try await FirestoreManager.shared.createPracticeNote(
                            userId: userId,
                            practiceFirestoreId: practiceFirestoreId,
                            data: note.toFirestoreData(practiceFirestoreId: practiceFirestoreId)
                        )
                        note.firestoreId = docId
                        ErrorHandlerService.shared.saveContext(context, caller: "SyncCoordinator.syncPracticeNotes.firestoreId")
                    }
                    note.needsSync = false
                    syncedNotes.append(note)
                } catch {
                    syncLog.error("Failed to sync practice note to Firestore: \(error.localizedDescription)")
                }
            }
        }

        // Phase 2 — download. Previously this fetched notes once per practice in a
        // sequential loop (an N+1 of round-trips: 200 practices → 200 serial reads).
        // Fetch in bounded-concurrency chunks so the network waits overlap, then
        // apply to the context serially on the main actor. Only Sendable values
        // (the practice firestoreId + decoded note structs) cross the task
        // boundary — the @Model objects stay on the main actor.
        let maxConcurrent = 6
        let practiceIDs = syncedPractices.compactMap { $0.firestoreId }
        let practicesByFirestoreId = Dictionary(
            syncedPractices.compactMap { p in p.firestoreId.map { ($0, p) } },
            uniquingKeysWith: { first, _ in first }
        )

        var idx = 0
        while idx < practiceIDs.count {
            let chunk = Array(practiceIDs[idx..<min(idx + maxConcurrent, practiceIDs.count)])
            idx += maxConcurrent

            let results: [(String, [FirestorePracticeNote])] = await withTaskGroup(
                of: (String, [FirestorePracticeNote]).self
            ) { group in
                for fid in chunk {
                    group.addTask {
                        let notes = (try? await FirestoreManager.shared.fetchPracticeNotes(
                            userId: userId,
                            practiceFirestoreId: fid
                        )) ?? []
                        return (fid, notes)
                    }
                }
                var acc: [(String, [FirestorePracticeNote])] = []
                for await r in group { acc.append(r) }
                return acc
            }

            for (fid, remoteNotes) in results {
                guard let practice = practicesByFirestoreId[fid] else { continue }
                applyRemoteNotes(remoteNotes, to: practice, context: context)
            }
        }

        // Save all changes to SwiftData — re-dirty on failure so next sync retries
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                for note in syncedNotes { note.needsSync = true }
                throw error
            }
        }
    }

    /// Inserts remote-only notes and (when online) removes locally-synced notes
    /// that were deleted on another device. `fetchPracticeNotes` already filters
    /// `isDeleted == false`, so a remotely-deleted note simply won't appear in the
    /// alive set. Deletion is gated on connectivity so an offline cached fetch
    /// can't wipe local notes — matches the +HoleScores tombstone reconciliation.
    private func applyRemoteNotes(
        _ remoteNotes: [FirestorePracticeNote],
        to practice: Practice,
        context: ModelContext
    ) {
        let localNotes = practice.notes ?? []
        let localNoteIds = Set(localNotes.compactMap { $0.firestoreId })

        for remoteNote in remoteNotes where !localNoteIds.contains(remoteNote.id ?? "") {
            let newNote = PracticeNote(content: remoteNote.content)
            newNote.createdAt = remoteNote.createdAt
            newNote.firestoreId = remoteNote.id
            newNote.needsSync = false
            newNote.practice = practice
            context.insert(newNote)
        }

        guard ConnectivityMonitor.shared.isConnected else { return }
        let remoteNoteIds = Set(remoteNotes.compactMap { $0.id })
        for note in localNotes where !note.needsSync {
            guard let fid = note.firestoreId, !remoteNoteIds.contains(fid) else { continue }
            context.delete(note)
        }
    }
}
