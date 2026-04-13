//
//  FirestoreModels.swift
//  PlayerPath
//
//  Data models for Firestore documents
//

import Foundation

// MARK: - Supporting Types

/// User role in the app
enum UserRole: String, Codable {
    case athlete
    case coach
}

/// Permissions a coach has for a specific folder
struct FolderPermissions: Codable, Equatable {
    var canUpload: Bool
    var canComment: Bool
    var canDelete: Bool

    func toDictionary() -> [String: Bool] {
        return [
            "canUpload": canUpload,
            "canComment": canComment,
            "canDelete": canDelete
        ]
    }

    static nonisolated let `default` = FolderPermissions(canUpload: true, canComment: true, canDelete: false)
    static nonisolated let viewOnly = FolderPermissions(canUpload: false, canComment: true, canDelete: false)
}

// MARK: - Firestore Models

/// Shared folder model
struct SharedFolder: Codable, Identifiable, Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: SharedFolder, rhs: SharedFolder) -> Bool { lhs.id == rhs.id }
    var id: String?
    let name: String
    let ownerAthleteID: String
    let ownerAthleteName: String?  // Name of the athlete who owns this folder
    let sharedWithCoachIDs: [String]
    var sharedWithCoachNames: [String: String]? = nil
    let permissions: [String: [String: Bool]]
    let createdAt: Date?
    let updatedAt: Date?
    let videoCount: Int?
    var tags: [String]? = nil
    var folderType: String? = nil  // "games", "lessons", or nil for legacy folders

    /// Helper to get typed permissions for a coach
    func getPermissions(for coachID: String) -> FolderPermissions? {
        guard let permDict = permissions[coachID] else { return nil }
        return FolderPermissions(
            canUpload: permDict["canUpload"] ?? false,
            canComment: permDict["canComment"] ?? true,
            canDelete: permDict["canDelete"] ?? false
        )
    }
}

/// Thumbnail metadata with support for multiple quality levels
struct ThumbnailMetadata: Codable, Equatable {
    let standardURL: String         // Standard quality (480x270, 16:9)
    let highQualityURL: String?     // High quality - for highlights
    let timestamp: Double?          // Time in video (seconds) where thumbnail was captured
    let width: Int?
    let height: Int?

    init(standardURL: String, highQualityURL: String? = nil, timestamp: Double? = nil, width: Int? = nil, height: Int? = nil) {
        self.standardURL = standardURL
        self.highQualityURL = highQualityURL
        self.timestamp = timestamp
        self.width = width
        self.height = height
    }
}

/// Video metadata model
struct FirestoreVideoMetadata: Codable, Identifiable {
    var id: String?
    let fileName: String
    let firebaseStorageURL: String

    // IMPROVED: Structured thumbnail metadata instead of single URL
    let thumbnail: ThumbnailMetadata?

    // DEPRECATED: Use thumbnail.standardURL instead
    @available(*, deprecated, message: "Use thumbnail.standardURL instead")
    var thumbnailURL: String? {
        thumbnail?.standardURL
    }

    let uploadedBy: String
    let uploadedByName: String
    let sharedFolderID: String
    let createdAt: Date?
    let fileSize: Int64?
    let duration: Double?
    let isHighlight: Bool?

    // ENHANCED: Upload source tracking
    let uploadedByType: UploadedByType? // "athlete" or "coach"
    let isOrphaned: Bool? // True if uploader deleted their account
    let orphanedAt: Date? // When uploader account was deleted

    // Annotation count (incremented/decremented atomically via FieldValue.increment)
    let annotationCount: Int?

    // Game/Practice context
    let videoType: String? // "game", "practice", or "highlight"
    let gameOpponent: String?
    let gameDate: Date?
    let practiceDate: Date?
    let notes: String? // Athlete-authored context attached at share time

    // Coach-authored plain note (separate from athlete `notes`)
    var coachNote: String? = nil
    var coachNoteAuthorID: String? = nil
    var coachNoteAuthorName: String? = nil
    var coachNoteUpdatedAt: Date? = nil

    // Per-coach review state. Presence of a coach UID in this map means
    // "this coach has marked the clip reviewed" — set implicitly when the
    // coach saves a coachNote, or explicitly via the Mark as Reviewed button.
    var reviewedBy: [String: Date]? = nil

    // Tags and categorization
    var tags: [String]? = nil
    var drillType: String? = nil
    var sessionID: String? = nil

    // Visibility (coach private vs shared)
    var visibility: String? = nil
    var instructionDate: Date? = nil

    // Upload lifecycle tracking (metadata-first pattern)
    var uploadStatus: String? = nil // "pending", "completed", "failed" — nil for legacy
    var uploadStartedAt: Date? = nil

    // View tracking
    var viewCount: Int? = nil
    var lastViewedAt: Date? = nil

    /// Display name for uploader (handles orphaned accounts)
    var uploaderDisplayName: String {
        if isOrphaned == true {
            return "\(uploadedByName) (Former Coach)"
        }
        return uploadedByName
    }

    /// Whether this video was uploaded by a coach
    var wasUploadedByCoach: Bool {
        uploadedByType == .coach
    }
}

/// Type of user who uploaded a video
enum UploadedByType: String, Codable {
    case athlete
    case coach

    var displayName: String {
        switch self {
        case .athlete: return "Athlete"
        case .coach: return "Coach"
        }
    }
}

/// Video annotation/comment model
struct VideoAnnotation: Codable, Identifiable {
    var id: String?
    let userID: String
    let userName: String
    let timestamp: Double // Seconds into video
    let text: String
    let createdAt: Date?
    let isCoachComment: Bool
    var category: String? = nil
    var templateID: String? = nil
    var type: String? = nil // "note" (default), "drill_card", "drawing"
    var drawingData: String? = nil // base64-encoded PKDrawing data (telestration)

    var annotationCategory: AnnotationCategory? {
        guard let category else { return nil }
        return AnnotationCategory(rawValue: category)
    }
}

/// Coach invitation model
struct CoachInvitation: Codable, Identifiable {
    var id: String?
    var folderID: String?
    var folderName: String?
    var athleteID: String
    var athleteName: String
    var coachEmail: String
    var permissions: FolderPermissions?
    var createdAt: Date?
    var sentAt: Date?
    var expiresAt: Date?
    var status: InvitationStatus
    var acceptedByCoachID: String?
    var acceptedAt: Date?
    var declinedAt: Date?
    var cancelledAt: Date?
    var rejectedReason: String?

    enum InvitationStatus: String, Codable {
        case pending
        case accepted
        case declined
        case cancelled
        case rejectedLimit = "rejected_limit"
    }
}

/// Coach-to-Athlete invitation (when coach initiates the connection)
struct CoachToAthleteInvitation: Codable, Identifiable {
    var id: String?
    let coachID: String
    let coachEmail: String
    let coachName: String
    let athleteEmail: String
    let athleteName: String
    let message: String?
    let status: CoachInvitation.InvitationStatus
    let sentAt: Date?
    let expiresAt: Date?
    let folderID: String?
    let folderName: String?
    let athleteUserID: String?
    var acceptedAt: Date?
    var declinedAt: Date?
    var cancelledAt: Date?
    var rejectedReason: String?
}

/// Instruction session for coaches (scheduled or live)
struct CoachSession: Codable, Identifiable, Hashable {
    static func == (lhs: CoachSession, rhs: CoachSession) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    var id: String?
    let coachID: String
    let coachName: String
    var athleteIDs: [String]
    var athleteNames: [String: String]
    var folderIDs: [String: String]
    var status: SessionStatus
    let startedAt: Date?
    var endedAt: Date?
    var clipCount: Int
    var title: String?
    var scheduledDate: Date?
    var notes: String?

    var athleteNamesSummary: String {
        let names = athleteNames.values.sorted()
        if names.isEmpty { return "No athletes" }
        guard names.count > 2 else {
            return names.joined(separator: " & ")
        }
        return "\(names[0]), \(names[1]) +\(names.count - 2)"
    }
}

/// User profile model
struct UserProfile: Codable, Identifiable {
    var id: String?
    let email: String
    let displayName: String?
    let role: String
    let subscriptionTier: String?
    let coachSubscriptionTier: String?
    let createdAt: Date?
    let updatedAt: Date?

    // Role-specific profiles would be nested objects in Firestore

    var userRole: UserRole {
        UserRole(rawValue: role) ?? .athlete
    }

    var tier: SubscriptionTier {
        SubscriptionTier(rawValue: subscriptionTier ?? "free") ?? .free
    }
}

/// Athlete model for Firestore sync
struct FirestoreAthlete: Codable, Identifiable {
    var id: String?           // Firestore document ID (auto-generated, not encoded)
    let swiftDataId: String   // Original SwiftData UUID
    let name: String
    let primaryRole: String?
    let userId: String
    let createdAt: Date?
    let updatedAt: Date?
    let version: Int
    let isDeleted: Bool

    enum CodingKeys: String, CodingKey {
        case swiftDataId = "id"  // Maps to "id" field in Firestore document
        case name
        case primaryRole
        case userId
        case createdAt
        case updatedAt
        case version
        case isDeleted
    }
}

/// Season model for Firestore sync
struct FirestoreSeason: Codable, Identifiable {
    var id: String?           // Firestore document ID (auto-generated, not encoded)
    let swiftDataId: String   // Original SwiftData UUID
    let name: String
    let athleteId: String
    let startDate: Date?
    let endDate: Date?
    let isActive: Bool
    let sport: String
    var notes: String = ""
    let createdAt: Date?
    let updatedAt: Date?
    let version: Int
    let isDeleted: Bool

    enum CodingKeys: String, CodingKey {
        case swiftDataId = "id"  // Maps to "id" field in Firestore document
        case name
        case athleteId
        case startDate
        case endDate
        case isActive
        case sport
        case notes
        case createdAt
        case updatedAt
        case version
        case isDeleted
    }
}

/// Game model for Firestore sync
struct FirestoreGame: Codable, Identifiable {
    var id: String?           // Firestore document ID (auto-generated, not encoded)
    let swiftDataId: String   // Original SwiftData UUID
    let athleteId: String
    let seasonId: String?
    let tournamentId: String?
    let opponent: String
    let date: Date?
    let year: Int
    let isLive: Bool
    let isComplete: Bool
    let location: String?
    let notes: String?
    let createdAt: Date?
    let updatedAt: Date?
    let version: Int
    let isDeleted: Bool

    enum CodingKeys: String, CodingKey {
        case swiftDataId = "id"  // Maps to "id" field in Firestore document
        case athleteId
        case seasonId
        case tournamentId
        case opponent
        case date
        case year
        case isLive
        case isComplete
        case location
        case notes
        case createdAt
        case updatedAt
        case version
        case isDeleted
    }
}

struct FirestorePractice: Codable, Identifiable {
    var id: String?           // Firestore document ID (auto-generated, not encoded)
    let swiftDataId: String   // Original SwiftData UUID
    let athleteId: String
    let seasonId: String?
    let practiceType: String? // Optional so old docs without the field decode fine
    let date: Date?
    let createdAt: Date?
    let updatedAt: Date?
    let version: Int
    let isDeleted: Bool

    enum CodingKeys: String, CodingKey {
        case swiftDataId = "id"
        case athleteId
        case seasonId
        case practiceType
        case date
        case createdAt
        case updatedAt
        case version
        case isDeleted
    }
}

struct FirestorePracticeNote: Codable, Identifiable {
    var id: String?
    var swiftDataId: String?
    let practiceId: String
    let content: String
    let createdAt: Date?
    let updatedAt: Date?
    let isDeleted: Bool

    enum CodingKeys: String, CodingKey {
        case swiftDataId = "id"
        case practiceId
        case content
        case createdAt
        case updatedAt
        case isDeleted
    }
}

struct FirestorePhoto: Codable, Identifiable {
    var id: String?
    let swiftDataId: String
    let fileName: String
    let athleteId: String
    let uploadedBy: String
    let downloadURL: String?
    let caption: String?
    let gameId: String?
    let practiceId: String?
    let seasonId: String?
    let createdAt: Date?
    let updatedAt: Date?
    let isDeleted: Bool

    enum CodingKeys: String, CodingKey {
        case swiftDataId = "id"
        case fileName
        case athleteId
        case uploadedBy
        case downloadURL
        case caption
        case gameId
        case practiceId
        case seasonId
        case createdAt
        case updatedAt
        case isDeleted
    }
}

struct FirestoreCoach: Codable, Identifiable {
    var id: String?
    let swiftDataId: String
    let athleteId: String
    let name: String
    var role: String = "coach"
    let email: String
    let phone: String?
    let notes: String?
    let firebaseCoachID: String?
    let invitationStatus: String?
    let createdAt: Date?
    let updatedAt: Date?
    let isDeleted: Bool

    enum CodingKeys: String, CodingKey {
        case swiftDataId = "id"
        case athleteId
        case name
        case role
        case email
        case phone
        case notes
        case firebaseCoachID
        case invitationStatus
        case createdAt
        case updatedAt
        case isDeleted
    }
}

// MARK: - Video Context Models

/// Context metadata for game videos
struct GameContext {
    let opponent: String
    let date: Date
    let notes: String?

    init(opponent: String, date: Date, notes: String? = nil) {
        self.opponent = opponent
        self.date = date
        self.notes = notes
    }
}

/// Context metadata for practice videos
struct PracticeContext {
    let date: Date
    let notes: String?
    let drillType: String?

    init(date: Date, notes: String? = nil, drillType: String? = nil) {
        self.date = date
        self.notes = notes
        self.drillType = drillType
    }
}
