//
//  FolderAthleteMigrationService.swift
//  PlayerPath
//
//  One-shot migration that backfills SharedFolder.athleteUUID on pre-existing folders
//  created before per-athlete folder scoping shipped. For single-athlete users this
//  runs silently. Multi-athlete users are prompted via LegacyFolderAssignmentSheet.
//

import Foundation
import FirebaseFirestore
import os

private let migrationLog = Logger(subsystem: "com.playerpath.app", category: "FolderMigration")

@MainActor
@Observable
final class FolderAthleteMigrationService {
    static let shared = FolderAthleteMigrationService()
    private init() {}

    /// True when there are unassigned legacy folders and the user has >1 athlete.
    /// Drives presentation of the assignment sheet.
    private(set) var needsAssignment = false
    private(set) var unassignedFolders: [SharedFolder] = []

    /// Allows the presenting view to clear the flag on sheet dismiss without exposing the setter.
    func cancelAssignment() {
        needsAssignment = false
    }

    private let migrationKeyPrefix = "didRunFolderAthleteMigration_v1_"

    func hasRun(forUserID userID: String) -> Bool {
        UserDefaults.standard.bool(forKey: migrationKeyPrefix + userID)
    }

    private func markRun(forUserID userID: String) {
        UserDefaults.standard.set(true, forKey: migrationKeyPrefix + userID)
    }

    /// Runs the migration for the current user.
    /// Does an authoritative one-shot Firestore fetch instead of relying on the listener cache —
    /// this avoids a race where the listener's first snapshot hasn't landed when we decide, which
    /// would otherwise cause us to mark migration done with zero legacy folders seen.
    func runIfNeeded(userID: String, athletesForUser: [Athlete]) async {
        guard !hasRun(forUserID: userID) else { return }

        let folders: [SharedFolder]
        do {
            folders = try await FirestoreManager.shared.fetchSharedFolders(forAthlete: userID)
        } catch {
            migrationLog.warning("Migration deferred: fetch failed for user \(userID): \(error.localizedDescription)")
            // Don't mark done — retry next launch.
            return
        }
        let legacy = folders.filter { $0.athleteUUID == nil && $0.ownerAthleteID == userID }

        // No legacy folders — nothing to migrate.
        if legacy.isEmpty {
            markRun(forUserID: userID)
            return
        }

        switch athletesForUser.count {
        case 0:
            // No athlete to assign to (edge case). Leave folders unmigrated — they'll still be
            // visible (nil-athleteUUID filter fallback). Don't mark done so we retry when the
            // user creates an athlete.
            migrationLog.warning("Migration skipped: user \(userID) has legacy folders but no athletes yet")
            return

        case 1:
            let uuid = athletesForUser[0].id.uuidString
            await backfill(folders: legacy, athleteUUID: uuid)
            markRun(forUserID: userID)
            migrationLog.info("Migration complete: auto-assigned \(legacy.count) legacy folders to single athlete")

        default:
            unassignedFolders = legacy
            needsAssignment = true
            migrationLog.info("Migration paused: \(legacy.count) legacy folders need user assignment across \(athletesForUser.count) athletes")
        }
    }

    /// Called by LegacyFolderAssignmentSheet once the user has picked an athlete per folder.
    func completeAssignments(_ assignments: [(folder: SharedFolder, athleteUUID: String)], userID: String) async {
        for assignment in assignments {
            guard let folderID = assignment.folder.id else { continue }
            await writeAthleteUUID(folderID: folderID, athleteUUID: assignment.athleteUUID)
        }
        needsAssignment = false
        unassignedFolders = []
        markRun(forUserID: userID)
    }

    private func backfill(folders: [SharedFolder], athleteUUID: String) async {
        for folder in folders {
            guard let folderID = folder.id else { continue }
            await writeAthleteUUID(folderID: folderID, athleteUUID: athleteUUID)
        }
    }

    private func writeAthleteUUID(folderID: String, athleteUUID: String) async {
        let db = Firestore.firestore()
        do {
            try await db.collection(FC.sharedFolders).document(folderID).updateData([
                "athleteUUID": athleteUUID,
                "updatedAt": FieldValue.serverTimestamp(),
            ])
        } catch {
            migrationLog.error("Failed to set athleteUUID on folder \(folderID): \(error.localizedDescription)")
        }
    }
}
