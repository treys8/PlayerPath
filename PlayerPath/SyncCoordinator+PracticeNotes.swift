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
        let allPractices = athletes.flatMap { $0.practices ?? [] }

        var syncedNotes: [PracticeNote] = []

        for practice in allPractices {
            guard let practiceFirestoreId = practice.firestoreId else { continue }

            // Upload dirty notes
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

            // Download notes that exist remotely but not locally
            let remoteNotes = try await FirestoreManager.shared.fetchPracticeNotes(
                userId: userId,
                practiceFirestoreId: practiceFirestoreId
            )
            let localNoteIds = Set((practice.notes ?? []).compactMap { $0.firestoreId })
            for remoteNote in remoteNotes where !localNoteIds.contains(remoteNote.id ?? "") {
                let newNote = PracticeNote(content: remoteNote.content)
                newNote.createdAt = remoteNote.createdAt
                newNote.firestoreId = remoteNote.id
                newNote.needsSync = false
                newNote.practice = practice
                context.insert(newNote)
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
}
