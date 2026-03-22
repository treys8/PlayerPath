//
//  CoachFolderArchiveManager.swift
//  PlayerPath
//
//  Tracks which folders a coach has locally archived, stored in UserDefaults.
//  Archiving is per-coach (keyed by coach UID) and per-device — it only hides
//  the folder from the list without revoking Firestore access.
//

import Foundation

@MainActor
@Observable
class CoachFolderArchiveManager {
    static let shared = CoachFolderArchiveManager()

    private(set) var archivedFolderIDs: Set<String> = []

    private var coachUID: String = ""
    private var defaultsKey: String { "archivedCoachFolders_\(coachUID)" }

    private init() {}

    func configure(coachUID: String) {
        guard coachUID != self.coachUID else { return }
        self.coachUID = coachUID
        let stored = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        archivedFolderIDs = Set(stored)
    }

    func archive(folderID: String) {
        archivedFolderIDs.insert(folderID)
        persist()
    }

    func unarchive(folderID: String) {
        archivedFolderIDs.remove(folderID)
        persist()
    }

    func isArchived(_ folderID: String) -> Bool {
        archivedFolderIDs.contains(folderID)
    }

    private func persist() {
        UserDefaults.standard.set(Array(archivedFolderIDs), forKey: defaultsKey)
    }
}
