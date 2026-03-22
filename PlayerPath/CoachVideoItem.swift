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
    let firebaseStorageURL: String
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
    let annotationCount: Int?
    let tags: [String]
    let drillType: String?
    let visibility: String?

    var contextLabel: String? {
        if let opponent = gameOpponent {
            return "Game vs \(opponent)"
        } else if let _ = practiceDate {
            return "Instruction"
        }
        return nil
    }

    init(from metadata: FirestoreVideoMetadata) {
        self.id = metadata.id ?? metadata.fileName
        self.fileName = metadata.fileName
        self.firebaseStorageURL = metadata.firebaseStorageURL
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
        self.annotationCount = metadata.annotationCount
        self.tags = metadata.tags ?? []
        self.drillType = metadata.drillType
        self.visibility = metadata.visibility
    }
}
