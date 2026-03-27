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
            if let existing = athleteFolders[folder.ownerAthleteID] {
                if folder.folderType == "lessons" && existing.folderType != "lessons" {
                    athleteFolders[folder.ownerAthleteID] = folder
                }
            } else {
                athleteFolders[folder.ownerAthleteID] = folder
            }
        }

        return athleteFolders.values.compactMap { folder in
            guard let folderID = folder.id else { return nil }
            return (athleteID: folder.ownerAthleteID, athleteName: folder.ownerAthleteName ?? "Athlete", folderID: folderID)
        }
    }
}
