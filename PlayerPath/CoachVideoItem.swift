//
//  CoachVideoItem.swift
//  PlayerPath
//
//  Extracted from CoachFolderDetailView.swift
//

import Foundation

struct CoachVideoItem: Identifiable, Equatable {
    let id: String
    let fileName: String
    // `firebaseStorageURL` is deliberately NOT carried here. Since shared-folder uploads
    // stopped minting downloadURL() tokens, that Firestore field holds a Storage PATH
    // (and, on docs written by older builds, a permanent token URL) — so it is neither a
    // URL nor safe to treat as one. It had no readers; keeping a decoded, URL-named String
    // on the model every coach view already has in scope was one autocomplete away from
    // becoming an AVPlayer(url:). Playback and thumbnails resolve through SecureURLManager
    // from `fileName` + `sharedFolderID`.
    let thumbnailURL: String?
    let uploadedBy: String
    let uploadedByName: String
    let sharedFolderID: String
    let createdAt: Date?
    let fileSize: Int64?
    let duration: Double?
    let isHighlight: Bool

    // Context info
    let videoType: String?
    let gameOpponent: String?
    let gameDate: Date?
    let practiceDate: Date?
    let notes: String?
    let playResult: String?
    let pitchSpeed: Double?
    let pitchType: String?
    let seasonName: String?
    let club: String?
    let holeNumber: Int?
    let coachNote: String?
    let coachNoteAuthorID: String?
    let coachNoteAuthorName: String?
    let coachNoteUpdatedAt: Date?
    let reviewedBy: [String: Date]?
    let viewedBy: [String: Date]?
    let uploadedByType: UploadedByType?
    let annotationCount: Int?
    let drawingCount: Int?
    let tags: [String]
    let drillType: String?
    let visibility: String?

    /// True iff the given coach has marked this clip reviewed (or had it
    /// auto-marked by saving a coachNote).
    func isReviewed(by coachID: String) -> Bool {
        reviewedBy?[coachID] != nil
    }

    /// True iff the given athlete (folder owner) has played this clip at
    /// least once. Drives the "Viewed" pill on the coach folder grid.
    func isViewed(by athleteID: String) -> Bool {
        viewedBy?[athleteID] != nil
    }

    var contextLabel: String? {
        if gameOpponent != nil {
            return "Game"
        } else if practiceDate != nil {
            return "Lesson"
        }
        return nil
    }

    /// Human-readable title for display instead of raw UUID filenames.
    var displayTitle: String {
        if let opponent = gameOpponent {
            return "Game vs \(opponent)"
        }
        if videoType == "instruction" || practiceDate != nil {
            return "Lesson"
        }
        return "Video Clip"
    }

    init(from metadata: FirestoreVideoMetadata) {
        self.id = metadata.id ?? metadata.fileName
        self.fileName = metadata.fileName
        self.thumbnailURL = metadata.thumbnail?.standardURL
        self.uploadedBy = metadata.uploadedBy
        self.uploadedByName = metadata.uploadedByName
        self.sharedFolderID = metadata.sharedFolderID
        self.createdAt = metadata.createdAt
        self.fileSize = metadata.fileSize
        self.duration = metadata.duration
        self.isHighlight = metadata.isHighlight ?? false

        // Extract context info from metadata
        self.videoType = metadata.videoType
        self.gameOpponent = metadata.gameOpponent
        self.gameDate = metadata.gameDate
        self.practiceDate = metadata.practiceDate
        self.notes = metadata.notes
        // Sourced from the always-String `playResultName` key (see
        // FirestoreVideoMetadata) — the `playResult` key is mixed Int/String.
        self.playResult = metadata.playResultName
        self.pitchSpeed = metadata.pitchSpeed
        self.pitchType = metadata.pitchType
        self.seasonName = metadata.seasonName
        self.club = metadata.club
        self.holeNumber = metadata.holeNumber
        self.coachNote = metadata.coachNote
        self.coachNoteAuthorID = metadata.coachNoteAuthorID
        self.coachNoteAuthorName = metadata.coachNoteAuthorName
        self.coachNoteUpdatedAt = metadata.coachNoteUpdatedAt
        self.reviewedBy = metadata.reviewedBy
        self.viewedBy = metadata.viewedBy
        self.uploadedByType = metadata.uploadedByType
        self.annotationCount = metadata.annotationCount
        self.drawingCount = metadata.drawingCount
        self.tags = metadata.tags ?? []
        self.drillType = metadata.drillType
        self.visibility = metadata.visibility
    }
}
