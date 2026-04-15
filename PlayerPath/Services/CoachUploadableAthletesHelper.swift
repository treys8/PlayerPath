//
//  CoachUploadableAthletesHelper.swift
//  PlayerPath
//
//  Shared logic for resolving uploadable athletes from coach folders.
//  Used by StartSessionSheet and CoachDashboardView to avoid duplication.
//

import Foundation

@MainActor
enum CoachUploadableAthletesHelper {

    /// Returns deduplicated athletes the coach can upload to, preferring "lessons" folders.
    static func availableAthletes(coachID: String) -> [(athleteID: String, athleteName: String, folderID: String)] {
        let uploadableFolders = SharedFolderManager.shared.coachFolders.filter { folder in
            folder.getPermissions(for: coachID)?.canUpload == true
        }

        var athleteFolders: [String: SharedFolder] = [:]
        for folder in uploadableFolders {
            guard folder.id != nil else { continue }
            // Prefer per-athlete UUID (one key per real athlete); fall back to account UID for legacy rows.
            let key = folder.athleteUUID ?? folder.ownerAthleteID
            if let existing = athleteFolders[key] {
                if folder.folderType == "lessons" && existing.folderType != "lessons" {
                    athleteFolders[key] = folder
                }
            } else {
                athleteFolders[key] = folder
            }
        }

        return athleteFolders.map { key, folder in
            guard let folderID = folder.id else { return nil as (athleteID: String, athleteName: String, folderID: String)? }
            return (athleteID: key, athleteName: folder.ownerAthleteName ?? "Athlete", folderID: folderID)
        }.compactMap { $0 }
    }
}
