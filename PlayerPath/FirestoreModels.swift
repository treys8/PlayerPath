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
    /// Stable per-athlete UUID (`Athlete.id.uuidString`) identifying which of the owner's athletes this folder is for.
    /// Optional for legacy folders created before per-athlete scoping; migration backfills in production.
    var athleteUUID: String? = nil
    /// Person-group key (`(athlete.personGroupID ?? athlete.id).uuidString`) so a dual-sport
    /// person's two profiles collapse to ONE coach slot. Equals `athleteUUID` for solo athletes.
    /// Optional for legacy folders created before this field; backfilled server-side.
    var personGroupID: String? = nil
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

extension SharedFolder {
    /// Custom decoder so legacy folder docs missing required fields decode with
    /// safe defaults instead of throwing `keyNotFound` (synthesized Codable
    /// ignores defaults). A swallowed throw would drop the folder from fetches.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        ownerAthleteID = try c.decodeIfPresent(String.self, forKey: .ownerAthleteID) ?? ""
        ownerAthleteName = try c.decodeIfPresent(String.self, forKey: .ownerAthleteName)
        athleteUUID = try c.decodeIfPresent(String.self, forKey: .athleteUUID)
        personGroupID = try c.decodeIfPresent(String.self, forKey: .personGroupID)
        sharedWithCoachIDs = try c.decodeIfPresent([String].self, forKey: .sharedWithCoachIDs) ?? []
        sharedWithCoachNames = try c.decodeIfPresent([String: String].self, forKey: .sharedWithCoachNames)
        permissions = try c.decodeIfPresent([String: [String: Bool]].self, forKey: .permissions) ?? [:]
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        videoCount = try c.decodeIfPresent(Int.self, forKey: .videoCount)
        tags = try c.decodeIfPresent([String].self, forKey: .tags)
        folderType = try c.decodeIfPresent(String.self, forKey: .folderType)
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

    // Drawing-only count, incremented alongside annotationCount when a coach
    // saves a telestration drawing. Nil for legacy videos written before this
    // field existed — UI falls back to the lumped annotationCount badge.
    let drawingCount: Int?

    // Game/Practice context
    let videoType: String? // "game", "practice", or "highlight"
    let gameOpponent: String?
    let gameDate: Date?
    let practiceDate: Date?
    let notes: String? // Athlete-authored context attached at share time

    // Athlete-tagged play context, written at share time by
    // createPendingVideoMetadata. Typed here so the coach pipeline doesn't drop
    // them on Codable round-trip — the athlete-side parser (VideoClipMetadata)
    // already reads these; without these declarations the coach saw a bare clip.
    //
    // IMPORTANT: read `playResultName` (always a String), NOT `playResult`. The
    // `playResult` key is written as an Int rawValue by the athlete-upload path
    // and as a String by the coach-share path; declaring a String? against that
    // mixed-type key would throw DecodingError.typeMismatch and silently drop the
    // whole doc from the coach's folder list. `playResultName` is consistently a
    // String (or absent) across both writers.
    var playResultName: String? = nil  // human-readable PlayResultType.displayName
    var pitchSpeed: Double? = nil       // mph
    var pitchType: String? = nil        // "fastball" / "offspeed"
    var seasonName: String? = nil

    // Golf club tag (Club enum rawValue, e.g. "7i", "Driver", "Putter").
    // Set at recording time for clips in a golf season; nil for baseball/softball.
    // Mirrors VideoClip.club in SchemaV23 — typed here so the coach pipeline
    // doesn't drop the field on Codable round-trip.
    var club: String? = nil

    // Hole number this clip was recorded on within a live golf round
    // (SchemaV25). Set by ClipPersistenceService via LiveHoleTracker — nil for
    // baseball/softball or for golf clips recorded outside a live round.
    var holeNumber: Int? = nil

    // Coach-authored plain note (separate from athlete `notes`)
    var coachNote: String? = nil
    var coachNoteAuthorID: String? = nil
    var coachNoteAuthorName: String? = nil
    var coachNoteUpdatedAt: Date? = nil

    // Per-coach review state. Presence of a coach UID in this map means
    // "this coach has marked the clip reviewed" — set implicitly when the
    // coach saves a coachNote, or explicitly via the Mark as Reviewed button.
    var reviewedBy: [String: Date]? = nil

    // Per-athlete view receipts. Presence of an athlete UID in this map means
    // "this athlete has played the clip at least once" — written on first
    // playback so the coach folder grid can surface a "Viewed" pill.
    var viewedBy: [String: Date]? = nil

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
    var type: String? = nil // wire format; raw values map to AnnotationType
    var drawingData: String? = nil // base64-encoded PKDrawing data (telestration)
    var drawingCanvasWidth: Double? = nil // canvas size the drawing was captured on (points)
    var drawingCanvasHeight: Double? = nil
    var shapes: String? = nil // JSON-encoded [TelestrationShape] placed alongside ink strokes
    // Forward-compat for moving drawing payloads to Firebase Storage. No writer
    // sets this yet; reading code must continue to fall back to `drawingData`.
    var drawingStoragePath: String? = nil

    var annotationCategory: AnnotationCategory? {
        guard let category else { return nil }
        return AnnotationCategory(rawValue: category)
    }

    /// Typed view of `type`. Returns nil for legacy/unknown wire values so
    /// future kinds can land without crashing decode on existing clients.
    var annotationType: AnnotationType? {
        guard let type else { return nil }
        return AnnotationType(rawValue: type)
    }
}

/// Typed discriminator for `VideoAnnotation.type`. Raw values must match the
/// wire format exactly — Cloud Functions and Firestore rules read the string.
enum AnnotationType: String, Codable {
    case note
    case drillCard = "drill_card"
    case drawing
}

/// Coach invitation model
struct CoachInvitation: Codable, Identifiable {
    var id: String?
    var folderID: String?
    var folderName: String?
    var athleteID: String
    var athleteName: String
    /// Person-group key so a dual-sport person collapses to ONE coach slot.
    /// Equals `athleteUUID` for solo athletes; nil for legacy invitations.
    var personGroupID: String? = nil
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
    /// Person-group key so a dual-sport person collapses to ONE coach slot.
    /// Stamped server-side at acceptance (the coach doesn't know it at send time).
    var personGroupID: String? = nil
    var acceptedAt: Date?
    var declinedAt: Date?
    var cancelledAt: Date?
    var rejectedReason: String?
}

/// Instruction session for coaches (scheduled or live)
struct CoachSession: Codable, Identifiable, Hashable {
    /// Equality compares id plus every mutable field so SwiftUI `onChange`
    /// and `ForEach` diffing detect status/clipCount/notes transitions.
    /// id-only equality previously hid live updates from views holding a local copy.
    static func == (lhs: CoachSession, rhs: CoachSession) -> Bool {
        lhs.id == rhs.id
            && lhs.status == rhs.status
            && lhs.clipCount == rhs.clipCount
            && lhs.startedAt == rhs.startedAt
            && lhs.endedAt == rhs.endedAt
            && lhs.notes == rhs.notes
            && lhs.scheduledDate == rhs.scheduledDate
            && lhs.athleteIDs == rhs.athleteIDs
            && lhs.athleteNames == rhs.athleteNames
            && lhs.folderIDs == rhs.folderIDs
            && lhs.title == rhs.title
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    var id: String?
    let coachID: String
    let coachName: String
    var athleteIDs: [String]
    var athleteNames: [String: String]
    var folderIDs: [String: String]
    var status: SessionStatus
    var startedAt: Date?
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
    /// Authoritative cloud storage usage, written by the enforceStorageQuota
    /// Cloud Function. Used to reconcile local SwiftData User.cloudStorageUsedBytes
    /// across devices signed into the same account.
    let cloudStorageUsedBytes: Int64?

    /// Coach-downgrade backstop fields, CF-managed by `auditCoachDowngrades`.
    /// `downgradeUnresolved` is true once the server-authoritative grace expires
    /// while the coach is still over their tier's athlete limit — firestore.rules
    /// then blocks coach feedback writes until they shed. `coachDowngradeGraceStartedAt`
    /// is when that over-limit grace began (server clock, survives a reinstall —
    /// unlike the local UserDefaults fallback in CoachDowngradeManager).
    let downgradeUnresolved: Bool?
    let coachDowngradeGraceStartedAt: Date?

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
    /// "baseball", "softball", or "golf". Optional so pre-V21 docs decode cleanly.
    let sport: String?
    let userId: String
    let trackStatsEnabled: Bool?
    /// Links sport-variant profiles for the same human so they share one
    /// subscription slot. Optional — nil for pre-V24 docs and solo profiles.
    let personGroupID: String?
    let createdAt: Date?
    let updatedAt: Date?
    let version: Int
    let isDeleted: Bool

    enum CodingKeys: String, CodingKey {
        case swiftDataId = "id"  // Maps to "id" field in Firestore document
        case name
        case primaryRole
        case sport
        case userId
        case trackStatsEnabled
        case personGroupID
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

extension FirestoreSeason {
    /// Custom decoder so legacy docs missing later-added fields (e.g. `notes`)
    /// decode with sane defaults instead of throwing `keyNotFound` — synthesized
    /// Codable ignores stored-property defaults. A swallowed throw here would
    /// drop the doc from the fetch and let SyncCoordinator wipe it locally.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = nil
        swiftDataId = try c.decode(String.self, forKey: .swiftDataId)
        name = try c.decode(String.self, forKey: .name)
        athleteId = try c.decode(String.self, forKey: .athleteId)
        startDate = try c.decodeIfPresent(Date.self, forKey: .startDate)
        endDate = try c.decodeIfPresent(Date.self, forKey: .endDate)
        isActive = try c.decode(Bool.self, forKey: .isActive)
        sport = try c.decodeIfPresent(String.self, forKey: .sport) ?? Season.SportType.baseball.rawValue
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        version = try c.decode(Int.self, forKey: .version)
        isDeleted = try c.decode(Bool.self, forKey: .isDeleted)
    }
}

/// Multi-round golf tournament for Firestore sync (SchemaV27). Lives at
/// `users/{uid}/golfTournaments/{id}`. Mirrors FirestoreSeason — a per-athlete
/// top-level grouping entity. Rounds are plain games carrying `tournamentId`.
struct FirestoreGolfTournament: Codable, Identifiable {
    var id: String?           // Firestore document ID (auto-generated, not encoded)
    let swiftDataId: String   // Original SwiftData UUID
    let name: String
    let athleteId: String
    let location: String?
    let startDate: Date?
    let endDate: Date?
    var notes: String?
    let createdAt: Date?
    let updatedAt: Date?
    let version: Int
    let isDeleted: Bool

    enum CodingKeys: String, CodingKey {
        case swiftDataId = "id"  // Maps to "id" field in Firestore document
        case name
        case athleteId
        case location
        case startDate
        case endDate
        case notes
        case createdAt
        case updatedAt
        case version
        case isDeleted
    }
}

extension FirestoreGolfTournament {
    /// Custom decoder so docs missing later-added optional fields decode with
    /// sane defaults instead of throwing — a swallowed throw here would drop the
    /// doc from the fetch and let SyncCoordinator wipe it locally. Mirrors
    /// FirestoreSeason.init(from:).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = nil
        swiftDataId = try c.decode(String.self, forKey: .swiftDataId)
        name = try c.decode(String.self, forKey: .name)
        athleteId = try c.decode(String.self, forKey: .athleteId)
        location = try c.decodeIfPresent(String.self, forKey: .location)
        startDate = try c.decodeIfPresent(Date.self, forKey: .startDate)
        endDate = try c.decodeIfPresent(Date.self, forKey: .endDate)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        version = try c.decode(Int.self, forKey: .version)
        isDeleted = try c.decode(Bool.self, forKey: .isDeleted)
    }
}

/// Game model for Firestore sync
struct FirestoreGame: Codable, Identifiable {
    var id: String?           // Firestore document ID (auto-generated, not encoded)
    let swiftDataId: String   // Original SwiftData UUID
    let athleteId: String
    let seasonId: String?
    let tournamentId: String?
    let roundNumber: Int?
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

    // Golf-only fields. nil for baseball/softball games.
    let holes: Int?
    let par: Int?
    let totalScore: Int?

    // GameStatistics counters inlined onto the game doc. All optional so pre-V20
    // docs (which lack these fields) decode cleanly — nil means "remote has no
    // stats to apply; keep local as-is".
    let statsHasManualEntry: Bool?
    let statsAtBats: Int?
    let statsHits: Int?
    let statsRuns: Int?
    let statsSingles: Int?
    let statsDoubles: Int?
    let statsTriples: Int?
    let statsHomeRuns: Int?
    let statsRbis: Int?
    let statsStrikeouts: Int?
    let statsWalks: Int?
    let statsGroundOuts: Int?
    let statsFlyOuts: Int?
    let statsHitByPitches: Int?
    let statsTotalPitches: Int?
    let statsBalls: Int?
    let statsStrikes: Int?
    let statsWildPitches: Int?
    let statsPitchingStrikeouts: Int?
    let statsPitchingWalks: Int?
    let statsFastballPitchCount: Int?
    let statsFastballSpeedTotal: Double?
    let statsOffspeedPitchCount: Int?
    let statsOffspeedSpeedTotal: Double?

    enum CodingKeys: String, CodingKey {
        case swiftDataId = "id"  // Maps to "id" field in Firestore document
        case athleteId
        case seasonId
        case tournamentId
        case roundNumber
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
        case holes
        case par
        case totalScore
        case statsHasManualEntry = "stats_hasManualEntry"
        case statsAtBats = "stats_atBats"
        case statsHits = "stats_hits"
        case statsRuns = "stats_runs"
        case statsSingles = "stats_singles"
        case statsDoubles = "stats_doubles"
        case statsTriples = "stats_triples"
        case statsHomeRuns = "stats_homeRuns"
        case statsRbis = "stats_rbis"
        case statsStrikeouts = "stats_strikeouts"
        case statsWalks = "stats_walks"
        case statsGroundOuts = "stats_groundOuts"
        case statsFlyOuts = "stats_flyOuts"
        case statsHitByPitches = "stats_hitByPitches"
        case statsTotalPitches = "stats_totalPitches"
        case statsBalls = "stats_balls"
        case statsStrikes = "stats_strikes"
        case statsWildPitches = "stats_wildPitches"
        case statsPitchingStrikeouts = "stats_pitchingStrikeouts"
        case statsPitchingWalks = "stats_pitchingWalks"
        case statsFastballPitchCount = "stats_fastballPitchCount"
        case statsFastballSpeedTotal = "stats_fastballSpeedTotal"
        case statsOffspeedPitchCount = "stats_offspeedPitchCount"
        case statsOffspeedSpeedTotal = "stats_offspeedSpeedTotal"
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
    /// Golf practice-round hole count (9 or 18). Optional so pre-PR3 docs
    /// without the field decode cleanly. Nil for baseball practices and
    /// range sessions.
    let holes: Int?
    /// True while a golf practice is the live dashboard activity (SchemaV26).
    /// Optional so pre-V26 docs decode cleanly; defaults to false on decode.
    let isLive: Bool?
    /// Timestamp the practice went live (SchemaV26). Nil when not live.
    let liveStartDate: Date?
    /// Optional course / location for golf practices (SchemaV26).
    let course: String?

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
        case holes
        case isLive
        case liveStartDate
        case course
    }
}

/// Per-hole golf scoring row (SchemaV25). Doc id is the hole number as a
/// String ("1"–"18"), so re-scoring a hole upserts deterministically without
/// a separate firestoreId lookup. Lives under both
/// `users/{uid}/games/{gameId}/holes/{N}` (tournaments) and
/// `users/{uid}/practices/{practiceId}/holes/{N}` (practice rounds, PR3).
struct FirestoreHoleScore: Codable, Identifiable {
    var id: String?
    let holeNumber: Int
    let par: Int
    let score: Int
    let putts: Int?
    // Detailed tracking (SchemaV29) — optional; absent on rows scored before
    // the user enabled detailed stats, decode to nil.
    let fairwayHit: Bool?
    let greenInRegulation: Bool?
    let penalties: Int?
    let createdAt: Date?
    let updatedAt: Date?
    let version: Int?
    let isDeleted: Bool?
}

/// Virtual highlight reel (SchemaV25 / v6.1 PR2). Top-level athlete collection
/// at `users/{uid}/highlightReels/{reelId}` where the doc id is
/// `reel.id.uuidString` — distinct from `FirestoreHoleScore` which keys on
/// hole number under the parent game. Reels reference clips by UUID; the
/// referenced video docs live under the `videos` top-level collection
/// (uploaded via the same path as any other VideoClip).
struct FirestoreHighlightReel: Codable, Identifiable {
    var id: String?
    let athleteID: String
    let gameID: String?
    let practiceID: String?
    let holeNumber: Int
    let score: Int
    let par: Int
    let displayName: String
    let courseOrOpponent: String
    let clipIDs: [String]
    let date: Date
    let createdAt: Date?
    let updatedAt: Date?
    let version: Int?
    let isDeleted: Bool?
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

extension FirestoreCoach {
    /// Custom decoder so legacy coach docs missing later-added fields (e.g.
    /// `role`) decode with defaults instead of throwing `keyNotFound`. See
    /// FirestoreSeason.init(from:) for rationale.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = nil
        swiftDataId = try c.decode(String.self, forKey: .swiftDataId)
        athleteId = try c.decode(String.self, forKey: .athleteId)
        name = try c.decode(String.self, forKey: .name)
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? "coach"
        email = try c.decode(String.self, forKey: .email)
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        firebaseCoachID = try c.decodeIfPresent(String.self, forKey: .firebaseCoachID)
        invitationStatus = try c.decodeIfPresent(String.self, forKey: .invitationStatus)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        isDeleted = try c.decode(Bool.self, forKey: .isDeleted)
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
