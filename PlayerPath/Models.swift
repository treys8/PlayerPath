//
//  Models.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import Foundation
import SwiftData


/*
 Inverse relationships mapping for CloudKit/SwiftData:

 User.athletes <-> Athlete.user
 Athlete.seasons <-> Season.athlete
 Athlete.games <-> Game.athlete
 Athlete.practices <-> Practice.athlete
 Athlete.videoClips <-> VideoClip.athlete
 Athlete.statistics <-> AthleteStatistics.athlete (to-one)
 Athlete.coaches <-> Coach.athlete
 Athlete.photos <-> Photo.athlete

 Season.games <-> Game.season
 Season.practices <-> Practice.season
 Season.videoClips <-> VideoClip.season
 Season.seasonStatistics <-> AthleteStatistics (to-one)
 Season.photos <-> Photo.season

 Game.videoClips <-> VideoClip.game
 Game.photos <-> Photo.game
 Game.gameStats <-> GameStatistics.game (to-one)
 Game.season <-> Season.games

 Practice.videoClips <-> VideoClip.practice
 Practice.notes <-> PracticeNote.practice
 Practice.photos <-> Photo.practice
 Practice.season <-> Season.practices

 VideoClip.season <-> Season.videoClips
 PlayResult.videoClip <-> VideoClip.playResult (to-one)
*/

// MARK: - User and Athlete Models
@Model
final class User {
    var id: UUID = UUID()
    var username: String = ""
    var email: String = ""
    var role: String = "athlete" // "athlete" or "coach"
    var profileImagePath: String?
    var createdAt: Date?
    var subscriptionTier: String = "free"
    /// Firebase Auth UID — used as the Firestore document key for all user data
    var firebaseAuthUid: String?
    /// Running total of bytes stored in Firebase Storage (videos + photos).
    /// Updated after each successful upload/delete. Used to enforce tier storage limits.
    var cloudStorageUsedBytes: Int64 = 0

    /// Computed tier from stored string — not persisted by SwiftData
    var tier: SubscriptionTier {
        SubscriptionTier(rawValue: subscriptionTier) ?? .free
    }
    @Relationship(inverse: \Athlete.user) var athletes: [Athlete]?

    init(username: String, email: String, role: String = "athlete") {
        self.id = UUID()
        self.username = username
        self.email = email
        self.role = role
        self.createdAt = Date()
    }
}

enum AthleteRole: String, Codable, CaseIterable {
    case batter
    case pitcher
    case both

    var displayName: String {
        switch self {
        case .batter: return "Batter"
        case .pitcher: return "Pitcher"
        case .both: return "Both"
        }
    }
}

@Model
final class Athlete {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date?
    var user: User?
    var primaryRole: AthleteRole = AthleteRole.batter
    @Relationship(inverse: \Season.athlete) var seasons: [Season]?
    @Relationship(inverse: \Game.athlete) var games: [Game]?
    @Relationship(inverse: \Practice.athlete) var practices: [Practice]?
    @Relationship(inverse: \VideoClip.athlete) var videoClips: [VideoClip]?
    @Relationship(inverse: \AthleteStatistics.athlete) var statistics: AthleteStatistics?
    @Relationship(inverse: \Coach.athlete) var coaches: [Coach]?
    @Relationship(inverse: \Photo.athlete) var photos: [Photo]?

    // MARK: - Firestore Sync Metadata
    var firestoreId: String?        // Maps to Firestore document ID
    var lastSyncDate: Date?         // Last successful sync timestamp
    var needsSync: Bool = false     // Dirty flag - needs upload to Firestore
    var isDeletedRemotely: Bool = false  // Soft delete from another device
    var version: Int = 0            // Version number for conflict resolution

    /// The currently active season for this athlete (only one can be active at a time)
    var activeSeason: Season? {
        seasons?.first(where: { $0.isActive })
    }

    /// Whether this athlete is synced to Firestore
    var isSynced: Bool {
        needsSync == false && firestoreId != nil
    }

    /// All archived (completed) seasons, sorted by start date descending
    var archivedSeasons: [Season] {
        (seasons ?? [])
            .filter { !$0.isActive }
            .sorted { ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast) }
    }

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
    }

    // MARK: - Deep Deletion

    /// Properly delete athlete with all associated files and data.
    /// Use this instead of modelContext.delete(athlete) to avoid orphaning children.
    func delete(in context: ModelContext) {
        // Track which clips are owned by a game or practice so we don't double-delete
        var deletedClipIDs = Set<UUID>()

        // Delete all games (and their video clips, stats)
        for game in games ?? [] {
            for clip in game.videoClips ?? [] {
                clip.delete(in: context)
                deletedClipIDs.insert(clip.id)
            }
            if let gameStats = game.gameStats {
                context.delete(gameStats)
            }
            context.delete(game)
        }

        // Delete all practices (and their video clips, notes)
        for practice in practices ?? [] {
            for clip in practice.videoClips ?? [] where !deletedClipIDs.contains(clip.id) {
                clip.delete(in: context)
                deletedClipIDs.insert(clip.id)
            }
            for note in practice.notes ?? [] {
                context.delete(note)
            }
            context.delete(practice)
        }

        // Delete remaining standalone video clips (not attached to a game or practice)
        for clip in videoClips ?? [] where !deletedClipIDs.contains(clip.id) {
            clip.delete(in: context)
        }

        // Delete all photos (handles local files and cloud)
        for photo in photos ?? [] {
            photo.delete(in: context)
        }

        // Delete seasons and their statistics
        for season in seasons ?? [] {
            if let seasonStats = season.seasonStatistics {
                context.delete(seasonStats)
            }
            context.delete(season)
        }

        // Delete coaches
        for coach in coaches ?? [] {
            context.delete(coach)
        }

        // Delete athlete statistics
        if let stats = statistics {
            context.delete(stats)
        }

        context.delete(self)
    }

    // MARK: - Firestore Conversion
    func toFirestoreData() -> [String: Any] {
        return [
            "id": id.uuidString,
            "name": name,
            "userId": user?.id.uuidString ?? "",
            "primaryRole": primaryRole.rawValue,
            "createdAt": createdAt ?? Date(),
            "updatedAt": Date(),
            "version": version,
            "isDeleted": false
        ]
    }
}

// MARK: - Season Model
@Model
final class Season {
    var id: UUID = UUID()
    var name: String = ""
    var startDate: Date?
    var endDate: Date?
    var isActive: Bool = false
    var createdAt: Date?
    var athlete: Athlete?
    @Relationship(inverse: \Game.season) var games: [Game]?
    @Relationship(inverse: \Practice.season) var practices: [Practice]?
    @Relationship(inverse: \VideoClip.season) var videoClips: [VideoClip]?
    @Relationship(inverse: \Photo.season) var photos: [Photo]?

    /// Season-specific statistics (calculated when season is archived)
    @Relationship(inverse: \AthleteStatistics.season) var seasonStatistics: AthleteStatistics?
    
    /// Notes about the season (goals, achievements, etc.)
    var notes: String = ""
    
    /// Sport for this season (baseball or softball)
    var sport: SportType = SportType.baseball

    // MARK: - Firestore Sync Metadata (Phase 2)

    /// Firestore document ID (maps to cloud storage)
    var firestoreId: String?

    /// Last successful sync timestamp
    var lastSyncDate: Date?

    /// Dirty flag - true when local changes need uploading
    var needsSync: Bool = false

    /// Soft delete flag - true when deleted on another device
    var isDeletedRemotely: Bool = false

    /// Version number for conflict resolution
    var version: Int = 0

    /// Computed sync status
    var isSynced: Bool {
        needsSync == false && firestoreId != nil
    }

    private static let yearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        return f
    }()
    private static let yearPattern: NSRegularExpression? = try? NSRegularExpression(pattern: #"\b\d{4}\b"#)

    /// Computed display name with year range
    var displayName: String {
        // If name already contains a year (4 digits), just return it
        let range = NSRange(name.startIndex..., in: name)
        if let pattern = Self.yearPattern, pattern.firstMatch(in: name, range: range) != nil {
            return name
        }

        // Otherwise, append year from dates
        if let start = startDate, let end = endDate {
            let startYear = Self.yearFormatter.string(from: start)
            let endYear = Self.yearFormatter.string(from: end)

            if startYear == endYear {
                return "\(name) \(startYear)"
            } else {
                return "\(name) \(startYear)-\(endYear)"
            }
        } else if let start = startDate {
            return "\(name) \(Self.yearFormatter.string(from: start))"
        }
        return name
    }
    
    /// Is this season archived (ended)?
    var isArchived: Bool {
        return !isActive && endDate != nil
    }

    /// Current status of the season
    var status: SeasonStatus {
        if isActive {
            return .active
        } else if isArchived {
            return .ended
        } else {
            return .inactive
        }
    }

    enum SeasonStatus: String {
        case active = "Active"
        case ended = "Ended"
        case inactive = "Inactive"

        var displayName: String { rawValue }

        var color: String {
            switch self {
            case .active: return "blue"
            case .ended: return "gray"
            case .inactive: return "orange"
            }
        }

        var icon: String {
            switch self {
            case .active: return "calendar.circle.fill"
            case .ended: return "calendar.badge.checkmark"
            case .inactive: return "calendar"
            }
        }
    }
    
    /// Total number of games played in this season
    var totalGames: Int {
        (games ?? []).filter { $0.isComplete }.count
    }
    
    /// Total videos recorded during this season
    var totalVideos: Int {
        (videoClips ?? []).count
    }
    
    /// All highlight videos from this season
    var highlights: [VideoClip] {
        (videoClips ?? []).filter { $0.isHighlight }
    }
    
    enum SportType: String, Codable, CaseIterable {
        case baseball = "Baseball"
        case softball = "Softball"
        
        var displayName: String { rawValue }
        
        var icon: String {
            switch self {
            case .baseball: return "figure.baseball"
            case .softball: return "figure.softball"
            }
        }
    }
    
    init(name: String, startDate: Date, sport: SportType = .baseball) {
        self.id = UUID()
        self.name = name
        self.startDate = startDate
        self.sport = sport
        self.isActive = false
        self.createdAt = Date()
    }
    
    /// End this season and archive it
    func archive(endDate: Date? = nil) {
        self.endDate = endDate ?? Date()
        self.isActive = false

        // Calculate and save season statistics
        let stats = seasonStatistics ?? AthleteStatistics()
        if seasonStatistics == nil {
            seasonStatistics = stats
        }

        // Reset before aggregating so re-archiving doesn't double-count
        stats.singles = 0
        stats.doubles = 0
        stats.triples = 0
        stats.homeRuns = 0
        stats.runs = 0
        stats.rbis = 0
        stats.walks = 0
        stats.strikeouts = 0
        stats.atBats = 0
        stats.hits = 0
        stats.hitByPitches = 0

        // Aggregate all game stats into season stats
        for game in (games ?? []) where game.isComplete {
            if let gameStats = game.gameStats {
                stats.singles += gameStats.singles
                stats.doubles += gameStats.doubles
                stats.triples += gameStats.triples
                stats.homeRuns += gameStats.homeRuns
                stats.runs += gameStats.runs
                stats.rbis += gameStats.rbis
                stats.walks += gameStats.walks
                stats.strikeouts += gameStats.strikeouts
                stats.atBats += gameStats.atBats
                stats.hits += gameStats.hits
                stats.hitByPitches += gameStats.hitByPitches
            }
        }

        stats.totalGames = totalGames
        stats.updatedAt = Date()
    }
    
    /// Activate this season (deactivates other seasons for this athlete)
    func activate() {
        // Deactivate all other seasons for this athlete and stamp their end date
        if let athlete = self.athlete {
            for season in (athlete.seasons ?? []) where season.id != self.id {
                if season.isActive && season.endDate == nil {
                    season.endDate = Date()
                }
                season.isActive = false
            }
        }

        self.isActive = true
        self.endDate = nil
    }

    // MARK: - Firestore Conversion

    func toFirestoreData() -> [String: Any] {
        // Prefer firestoreId for the athlete reference so it survives reinstalls.
        // Fall back to local UUID for athletes that haven't synced yet.
        let athleteRef = athlete?.firestoreId ?? athlete?.id.uuidString ?? ""
        return [
            "id": id.uuidString,
            "name": name,
            "athleteId": athleteRef,
            "startDate": startDate ?? Date(),
            "endDate": endDate as Any,
            "isActive": isActive,
            "sport": sport.rawValue,
            "notes": notes,
            "createdAt": createdAt ?? Date(),
            "updatedAt": Date(),
            "version": version,
            "isDeleted": false
        ]
    }
}

// MARK: - Game Model
@Model
final class Game {
    var id: UUID = UUID()
    var date: Date?
    var opponent: String = ""
    var location: String?
    var notes: String?
    var isLive: Bool = false
    var isComplete: Bool = false
    var liveStartDate: Date? // Set when game becomes live; used for stale-game alerts
    var createdAt: Date?
    var year: Int? // Year for tracking when no season is active
    var athlete: Athlete?
    var season: Season?
    @Relationship(inverse: \VideoClip.game) var videoClips: [VideoClip]?
    @Relationship(inverse: \GameStatistics.game) var gameStats: GameStatistics?
    @Relationship(inverse: \Photo.game) var photos: [Photo]?

    // MARK: - Firestore Sync Metadata (Phase 2)

    /// Firestore document ID (maps to cloud storage)
    var firestoreId: String?

    /// Last successful sync timestamp
    var lastSyncDate: Date?

    /// Dirty flag - true when local changes need uploading
    var needsSync: Bool = false

    /// Soft delete flag - true when deleted on another device
    var isDeletedRemotely: Bool = false

    /// Version number for conflict resolution
    var version: Int = 0

    /// Computed sync status
    var isSynced: Bool {
        needsSync == false && firestoreId != nil
    }

    init(date: Date, opponent: String) {
        self.id = UUID()
        self.date = date
        self.opponent = opponent
        self.createdAt = Date()
        // Auto-set year from date
        let calendar = Calendar.current
        self.year = calendar.component(.year, from: date)
    }

    // MARK: - Firestore Conversion

    func toFirestoreData() -> [String: Any] {
        let athleteRef = athlete?.firestoreId ?? athlete?.id.uuidString ?? ""
        let seasonRef = season?.firestoreId ?? season?.id.uuidString
        var data: [String: Any] = [
            "id": id.uuidString,
            "athleteId": athleteRef,
            "seasonId": seasonRef as Any,
            "opponent": opponent,
            "date": date ?? Date(),
            "year": year ?? Calendar.current.component(.year, from: date ?? Date()),
            "isLive": isLive,
            "isComplete": isComplete,
            "createdAt": createdAt ?? Date(),
            "updatedAt": Date(),
            "version": version,
            "isDeleted": false
        ]
        // Optional fields
        if let location = location { data["location"] = location }
        if let notes = notes { data["notes"] = notes }
        return data
    }
}

// MARK: - Practice Models
@Model
final class Practice {
    var id: UUID = UUID()
    var date: Date?
    var createdAt: Date?
    var athlete: Athlete?
    var season: Season?
    @Relationship(inverse: \VideoClip.practice) var videoClips: [VideoClip]?
    @Relationship(inverse: \PracticeNote.practice) var notes: [PracticeNote]?
    @Relationship(inverse: \Photo.practice) var photos: [Photo]?

    /// Practice type — "general", "batting", "fielding", "bullpen", or "team"
    var practiceType: String = "general"

    // MARK: - Firestore Sync Metadata (Phase 3)

    /// Firestore document ID (maps to cloud storage)
    var firestoreId: String?

    /// Last successful sync timestamp
    var lastSyncDate: Date?

    /// Dirty flag - true when local changes need uploading
    var needsSync: Bool = false

    /// Soft delete flag - true when deleted on another device
    var isDeletedRemotely: Bool = false

    /// Version number for conflict resolution
    var version: Int = 0

    /// Computed sync status
    var isSynced: Bool {
        needsSync == false && firestoreId != nil
    }

    init(date: Date) {
        self.id = UUID()
        self.date = date
        self.createdAt = Date()
    }

    // MARK: - Firestore Conversion

    func toFirestoreData() -> [String: Any] {
        let athleteRef = athlete?.firestoreId ?? athlete?.id.uuidString ?? ""
        let seasonRef = season?.firestoreId ?? season?.id.uuidString
        return [
            "id": id.uuidString,
            "athleteId": athleteRef,
            "seasonId": seasonRef as Any,
            "practiceType": practiceType,
            "date": date ?? Date(),
            "createdAt": createdAt ?? Date(),
            "updatedAt": Date(),
            "version": version,
            "isDeleted": false
        ]
    }

    /// Properly delete practice with all associated files and data
    func delete(in context: ModelContext) {
        // Delete video clips using their delete method for proper cleanup
        for videoClip in (self.videoClips ?? []) {
            videoClip.delete(in: context)
        }

        // Delete notes
        for note in (self.notes ?? []) {
            context.delete(note)
        }

        // SwiftData handles relationship cleanup automatically
        context.delete(self)
    }
}

// MARK: - Practice Type (display helper — not stored directly)

enum PracticeType: String, CaseIterable, Identifiable {
    case general
    case batting
    case fielding
    case bullpen
    case team

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .general:  return "General"
        case .batting:  return "Batting"
        case .fielding: return "Fielding"
        case .bullpen:  return "Bullpen"
        case .team:     return "Team"
        }
    }

    var icon: String {
        switch self {
        case .general:  return "figure.baseball"
        case .batting:  return "baseball.fill"
        case .fielding: return "hand.raised.fill"
        case .bullpen:  return "flame.fill"
        case .team:     return "person.3.fill"
        }
    }
}

@Model
final class PracticeNote {
    var id: UUID = UUID()
    var content: String = ""
    var createdAt: Date?
    var practice: Practice?

    // MARK: - Firestore Sync Metadata
    var firestoreId: String?
    var needsSync: Bool = false

    init(content: String) {
        self.id = UUID()
        self.content = content
        self.createdAt = Date()
    }

    func toFirestoreData(practiceFirestoreId: String) -> [String: Any] {
        return [
            "id": id.uuidString,
            "practiceId": practiceFirestoreId,
            "content": content,
            "createdAt": createdAt ?? Date(),
            "updatedAt": Date(),
            "isDeleted": false
        ]
    }
}

// MARK: - Video and Play Result Models
@Model
final class VideoClip {
    var id: UUID = UUID()
    var fileName: String = ""
    var filePath: String = ""
    var thumbnailPath: String?     // Path to thumbnail image
    var cloudURL: String?          // Firebase Storage URL
    var isUploaded: Bool = false           // Sync status
    var lastSyncDate: Date?        // Last successful sync
    var createdAt: Date?
    var duration: Double?          // Video duration in seconds
    var pitchSpeed: Double?        // Pitch speed in MPH (optional, radar gun input)
    @Relationship(inverse: \PlayResult.videoClip) var playResult: PlayResult?
    var isHighlight: Bool = false
    var note: String? = nil
    // Denormalized display fields — copied at save time so data survives cross-device sync
    // even if the game/season relationship cannot be re-linked on a new device.
    var gameOpponent: String?
    var gameDate: Date?
    var practiceDate: Date?
    var seasonName: String?
    var game: Game?
    var practice: Practice?
    var athlete: Athlete?
    var season: Season?

    // MARK: - Firestore Sync Metadata (Phase 3)

    /// Firestore document ID for video metadata (not the video file itself)
    var firestoreId: String?

    /// Dirty flag - true when metadata needs uploading to Firestore
    var needsSync: Bool = false

    /// Soft delete flag - true when deleted on another device
    var isDeletedRemotely: Bool = false

    /// Version number for conflict resolution
    var version: Int = 0

    /// Computed sync status for metadata
    var isSynced: Bool {
        needsSync == false && firestoreId != nil
    }

    init(fileName: String, filePath: String) {
        self.id = UUID()
        self.fileName = fileName
        self.filePath = filePath
        self.createdAt = Date()
    }

    /// Converts an absolute path to a path relative to the Documents directory.
    /// If the path is already relative or not under Documents, returns it unchanged.
    static func toRelativePath(_ absolutePath: String) -> String {
        guard absolutePath.hasPrefix("/"),
              let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return absolutePath
        }
        let docsPath = docs.path
        if absolutePath.hasPrefix(docsPath) {
            let relative = String(absolutePath.dropFirst(docsPath.count))
            return relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
        }
        return absolutePath
    }

    // Computed properties for sync status
    var needsUpload: Bool {
        return !isUploaded && cloudURL == nil
    }

    /// Cached result of path resolution. Stable within a single app launch since the
    /// Documents directory URL doesn't change. Eliminates repeated `fileExists` syscalls
    /// that otherwise fire on every cell render in video lists.
    @Transient private var _cachedResolvedPath: String?

    /// Resolves `filePath` to an absolute path, handling both legacy absolute paths
    /// and relative paths (relative to Documents directory). Absolute paths break
    /// when iOS relocates the app sandbox (reinstall, backup restore), so new clips
    /// store relative paths and this property resolves them at read time.
    var resolvedFilePath: String {
        if let cached = _cachedResolvedPath { return cached }
        let resolved = _resolveFilePath()
        _cachedResolvedPath = resolved
        return resolved
    }

    private func _resolveFilePath() -> String {
        // Relative path — resolve against Documents
        if !filePath.hasPrefix("/") {
            guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return filePath
            }
            return docs.appendingPathComponent(filePath).path
        }
        // Legacy absolute path — use as-is if file exists
        if FileManager.default.fileExists(atPath: filePath) {
            return filePath
        }
        // Absolute path but file missing (sandbox moved) — try resolving from fileName
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return filePath
        }
        let recovered = docs.appendingPathComponent("Clips").appendingPathComponent(fileName).path
        if FileManager.default.fileExists(atPath: recovered) {
            return recovered
        }
        // Return original — caller will handle the missing-file case
        return filePath
    }

    var resolvedFileURL: URL {
        URL(fileURLWithPath: resolvedFilePath)
    }

    var isAvailableOffline: Bool {
        return FileManager.default.fileExists(atPath: resolvedFilePath)
    }

    // MARK: - Firestore Conversion

    /// Converts video metadata to Firestore document
    /// Note: This syncs metadata only - actual video files are in Firebase Storage
    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "id": id.uuidString,
            "athleteId": athlete?.id.uuidString ?? "",
            "fileName": fileName,
            "isHighlight": isHighlight,
            "isUploaded": isUploaded,
            "createdAt": createdAt ?? Date(),
            "updatedAt": Date(),
            "version": version,
            "isDeleted": false
        ]

        // Optional fields
        if let gameId = game?.id.uuidString {
            data["gameId"] = gameId
        }
        if let practiceId = practice?.id.uuidString {
            data["practiceId"] = practiceId
        }
        if let practiceDate = practiceDate ?? practice?.date {
            data["practiceDate"] = practiceDate
        }
        if let seasonId = season?.id.uuidString {
            data["seasonId"] = seasonId
        }
        if let cloudURL = cloudURL {
            data["cloudURL"] = cloudURL
        }
        if let playResult = playResult {
            data["playResultType"] = playResult.type.rawValue
        }

        return data
    }

    /// Properly delete video clip with all associated files and data
    func delete(in context: ModelContext) {
        // Capture paths before context.delete to avoid accessing deleted SwiftData object
        let absolutePath = resolvedFilePath
        let capturedThumbPath = thumbnailPath

        // Dispatch file I/O to background — removeItem can take 10-50ms for large videos
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.removeItem(atPath: absolutePath)
            if let thumbPath = capturedThumbPath {
                try? FileManager.default.removeItem(atPath: thumbPath)
            }
        }

        // Remove thumbnail from in-memory cache on main actor
        if let thumbPath = capturedThumbPath {
            Task { @MainActor in
                ThumbnailCache.shared.removeThumbnail(at: thumbPath)
            }
        }

        // Delete from cloud storage if uploaded.
        // Capture values before context.delete(self) to avoid accessing a deleted SwiftData object.
        if isUploaded {
            let capturedFileName = self.fileName
            let capturedClipId = self.id
            let capturedUser = athlete?.user
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: resolvedFilePath)[.size] as? Int64) ?? 0
            Task { @MainActor in
                let cloudManager = VideoCloudManager.shared
                for attempt in 1...3 {
                    do {
                        try await cloudManager.deleteAthleteVideo(fileName: capturedFileName)
                        // Only decrement quota after the Storage file is actually deleted
                        if let user = capturedUser {
                            user.cloudStorageUsedBytes = max(0, user.cloudStorageUsedBytes - fileSize)
                        }
                        return
                    } catch {
                        if attempt < 3 {
                            try? await Task.sleep(for: .seconds(2))
                        }
                    }
                }
                // All retries exhausted — record as pending deletion so the server-side
                // cleanup function can remove the orphaned Storage file later.
                // Quota is NOT freed — the dailyStorageCleanup function will handle it.
                try? await cloudManager.recordPendingDeletion(clipId: capturedClipId, fileName: capturedFileName)
            }
        }

        // Soft-delete Firestore metadata if previously synced
        if let capturedFirestoreId = firestoreId {
            Task {
                for attempt in 1...3 {
                    do {
                        try await FirestoreManager.shared.deleteVideoClip(videoClipId: capturedFirestoreId)
                        return
                    } catch {
                        #if DEBUG
                        print("⚠️ Failed to delete video clip metadata from Firestore (attempt \(attempt)/3): \(error)")
                        #endif
                        if attempt < 3 {
                            try? await Task.sleep(for: .seconds(2))
                        }
                    }
                }
            }
        }

        // Delete associated play result
        if let playResult = playResult {
            context.delete(playResult)
        }

        // Delete video clip database record
        context.delete(self)
    }
}

enum PlayResultType: Int, CaseIterable, Codable {
    // Batting results
    case single = 0
    case double = 1
    case triple = 2
    case homeRun = 3
    case walk = 4
    case strikeout = 5
    case groundOut = 6
    case flyOut = 7

    // Pitching results
    case ball = 10
    case strike = 11
    case hitByPitch = 12
    case wildPitch = 13

    var isPitchingResult: Bool {
        rawValue >= 10
    }

    var isBattingResult: Bool {
        rawValue < 10
    }

    var isHit: Bool {
        switch self {
        case .single, .double, .triple, .homeRun:
            return true
        default:
            return false
        }
    }

    /// Determines if this result counts as an official at-bat
    /// Baseball rules: Walks, HBP, sac flies, and sac bunts do NOT count as at-bats
    var countsAsAtBat: Bool {
        switch self {
        case .walk, .hitByPitch:
            return false // Walks and HBP don't count as at-bats
        case .single, .double, .triple, .homeRun, .strikeout, .groundOut, .flyOut:
            return true // Hits and outs count as at-bats
        default:
            return false // Pitching results don't count as at-bats
        }
    }

    var isHighlight: Bool {
        switch self {
        case .single, .double, .triple, .homeRun:
            return true
        default:
            return false
        }
    }

    var bases: Int {
        switch self {
        case .single: return 1
        case .double: return 2
        case .triple: return 3
        case .homeRun: return 4
        default: return 0
        }
    }

    var displayName: String {
        switch self {
        case .single: return "Single"
        case .double: return "Double"
        case .triple: return "Triple"
        case .homeRun: return "Home Run"
        case .walk: return "Walk"
        case .strikeout: return "Strikeout"
        case .groundOut: return "Ground Out"
        case .flyOut: return "Fly Out"
        case .ball: return "Ball"
        case .strike: return "Strike"
        case .hitByPitch: return "Hit By Pitch"
        case .wildPitch: return "Wild Pitch"
        }
    }

    /// Returns only batting result types for filtering in UI
    static var battingCases: [PlayResultType] {
        allCases.filter { $0.isBattingResult }
    }

    /// Returns only pitching result types for filtering in UI
    static var pitchingCases: [PlayResultType] {
        allCases.filter { $0.isPitchingResult }
    }
}

@Model
final class PlayResult {
    var id: UUID = UUID()
    var type: PlayResultType = PlayResultType.single
    var createdAt: Date?
    var videoClip: VideoClip?

    init(type: PlayResultType) {
        self.id = UUID()
        self.type = type
        self.createdAt = Date()
    }
}

// MARK: - Statistics Models
@Model
final class AthleteStatistics {
    var id: UUID = UUID()
    var athlete: Athlete?
    var season: Season?  // Inverse relationship for Season.seasonStatistics
    var totalGames: Int = 0
    var atBats: Int = 0
    var hits: Int = 0
    var singles: Int = 0
    var doubles: Int = 0
    var triples: Int = 0
    var homeRuns: Int = 0
    var runs: Int = 0
    var rbis: Int = 0
    var walks: Int = 0
    var strikeouts: Int = 0
    var groundOuts: Int = 0
    var flyOuts: Int = 0

    // Pitching statistics
    var totalPitches: Int = 0
    var balls: Int = 0
    var strikes: Int = 0
    var hitByPitches: Int = 0
    var wildPitches: Int = 0
    var updatedAt: Date?

    var battingAverage: Double {
        return atBats > 0 ? Double(hits) / Double(atBats) : 0.0
    }
    
    var onBasePercentage: Double {
        // Fix Q: Include HBP in both numerator and denominator per official OBP formula:
        // OBP = (H + BB + HBP) / (AB + BB + HBP)
        let totalPlateAppearances = atBats + walks + hitByPitches
        return totalPlateAppearances > 0 ? Double(hits + walks + hitByPitches) / Double(totalPlateAppearances) : 0.0
    }

    var sluggingPercentage: Double {
        guard atBats > 0 else { return 0.0 }
        let totalBases = singles + (doubles * 2) + (triples * 3) + (homeRuns * 4)
        return Double(totalBases) / Double(atBats)
    }

    var ops: Double {
        return onBasePercentage + sluggingPercentage
    }

    var strikePercentage: Double {
        guard totalPitches > 0 else { return 0.0 }
        return Double(strikes) / Double(totalPitches)
    }

    var hasPitchingData: Bool {
        totalPitches > 0
    }

    init() {
        self.id = UUID()
        self.updatedAt = Date()
    }

    func addPlayResult(_ playResult: PlayResultType) {
        // Update at-bats (only if this result counts as an at-bat)
        if playResult.countsAsAtBat {
            self.atBats += 1
        }
        
        // Update specific result counts
        switch playResult {
        case .single:
            self.hits += 1
            self.singles += 1
        case .double:
            self.hits += 1
            self.doubles += 1
        case .triple:
            self.hits += 1
            self.triples += 1
        case .homeRun:
            self.hits += 1
            self.homeRuns += 1
        case .walk:
            self.walks += 1
        case .strikeout:
            self.strikeouts += 1
        case .groundOut:
            self.groundOuts += 1
        case .flyOut:
            self.flyOuts += 1
        case .ball:
            self.totalPitches += 1
            self.balls += 1
        case .strike:
            self.totalPitches += 1
            self.strikes += 1
        case .hitByPitch:
            self.totalPitches += 1
            self.hitByPitches += 1
        case .wildPitch:
            self.totalPitches += 1
            self.wildPitches += 1
        }
        self.updatedAt = Date()
    }

    func addCompletedGame() {
        self.totalGames += 1
        self.updatedAt = Date()
    }
    
    func addManualStatistic(singles: Int = 0, doubles: Int = 0, triples: Int = 0, homeRuns: Int = 0,
                           runs: Int = 0, rbis: Int = 0, strikeouts: Int = 0, walks: Int = 0,
                           groundOuts: Int = 0, flyOuts: Int = 0) {
        // Add hits and at bats
        let totalHits = singles + doubles + triples + homeRuns
        let totalAtBats = singles + doubles + triples + homeRuns + strikeouts + groundOuts + flyOuts

        self.singles += singles
        self.doubles += doubles
        self.triples += triples
        self.homeRuns += homeRuns
        self.hits += totalHits
        self.atBats += totalAtBats
        self.runs += runs
        self.rbis += rbis
        self.strikeouts += strikeouts
        self.walks += walks
        self.groundOuts += groundOuts
        self.flyOuts += flyOuts

        self.updatedAt = Date()
    }
}

@Model
final class GameStatistics {
    var id: UUID = UUID()
    var game: Game?
    var atBats: Int = 0
    var hits: Int = 0
    var runs: Int = 0
    var singles: Int = 0
    var doubles: Int = 0
    var triples: Int = 0
    var homeRuns: Int = 0
    var rbis: Int = 0
    var strikeouts: Int = 0
    var walks: Int = 0
    var groundOuts: Int = 0
    var flyOuts: Int = 0
    var hitByPitches: Int = 0
    var createdAt: Date?

    // MARK: - Computed Statistics

    var battingAverage: Double {
        return atBats > 0 ? Double(hits) / Double(atBats) : 0.0
    }

    var onBasePercentage: Double {
        let totalPlateAppearances = atBats + walks + hitByPitches
        return totalPlateAppearances > 0 ? Double(hits + walks + hitByPitches) / Double(totalPlateAppearances) : 0.0
    }

    var sluggingPercentage: Double {
        guard atBats > 0 else { return 0.0 }
        let totalBases = singles + (doubles * 2) + (triples * 3) + (homeRuns * 4)
        return Double(totalBases) / Double(atBats)
    }

    var ops: Double {
        return onBasePercentage + sluggingPercentage
    }

    init() {
        self.id = UUID()
        self.createdAt = Date()
    }

    func addPlayResult(_ playResult: PlayResultType) {
        // Update at-bats (only if this result counts as an at-bat)
        if playResult.countsAsAtBat {
            self.atBats += 1
        }
        
        // Update specific result counts
        switch playResult {
        case .single:
            self.hits += 1
            self.singles += 1
        case .double:
            self.hits += 1
            self.doubles += 1
        case .triple:
            self.hits += 1
            self.triples += 1
        case .homeRun:
            self.hits += 1
            self.homeRuns += 1
        case .walk:
            self.walks += 1
        case .strikeout:
            self.strikeouts += 1
        case .groundOut:
            self.groundOuts += 1
        case .flyOut:
            self.flyOuts += 1
        case .hitByPitch:
            self.hitByPitches += 1
        case .ball, .strike, .wildPitch:
            // Pitching stats are not tracked in GameStatistics - only in AthleteStatistics
            break
        }
    }
    
    func addManualStatistic(singles: Int = 0, doubles: Int = 0, triples: Int = 0, homeRuns: Int = 0,
                           runs: Int = 0, rbis: Int = 0, strikeouts: Int = 0, walks: Int = 0,
                           groundOuts: Int = 0, flyOuts: Int = 0) {
        // Add hits and at bats
        let totalHits = singles + doubles + triples + homeRuns
        let totalAtBats = singles + doubles + triples + homeRuns + strikeouts + groundOuts + flyOuts

        self.singles += singles
        self.doubles += doubles
        self.triples += triples
        self.homeRuns += homeRuns
        self.hits += totalHits
        self.atBats += totalAtBats
        self.runs += runs
        self.rbis += rbis
        self.strikeouts += strikeouts
        self.walks += walks
        self.groundOuts += groundOuts
        self.flyOuts += flyOuts
    }
}

// MARK: - Onboarding Models
@Model
final class OnboardingProgress {
    var id: UUID = UUID()
    var hasCompletedOnboarding: Bool = false
    var completedAt: Date?
    var createdAt: Date?
    /// Firebase Auth UID that owns this record. Prevents cross-account leakage
    /// when multiple accounts are used on the same device.
    var firebaseAuthUid: String?

    init() {
        self.id = UUID()
        self.createdAt = Date()
    }

    init(firebaseAuthUid: String) {
        self.id = UUID()
        self.createdAt = Date()
        self.firebaseAuthUid = firebaseAuthUid
    }

    func markCompleted() {
        self.hasCompletedOnboarding = true
        self.completedAt = Date()
    }
}

// MARK: - Coach Model
@Model
final class Coach {
    var id: UUID = UUID()
    var name: String = ""
    var role: String = ""
    var phone: String = ""
    var email: String = ""
    var notes: String = ""
    var createdAt: Date?
    var athlete: Athlete?

    // MARK: - Firebase Integration

    /// Firebase user ID if this coach has accepted an invitation and has an account
    var firebaseCoachID: String?

    /// Firebase folder IDs that this coach has access to
    var sharedFolderIDs: [String] = []

    /// Invitation tracking
    var invitationSentAt: Date?
    var invitationAcceptedAt: Date?
    var lastInvitationStatus: String? // "pending", "accepted", "declined"

    // MARK: - Computed Properties

    /// Whether this coach has an active Firebase account linked
    var hasFirebaseAccount: Bool {
        firebaseCoachID != nil
    }

    /// Whether this coach has access to any shared folders
    var hasFolderAccess: Bool {
        !sharedFolderIDs.isEmpty
    }

    /// True when 30 days have passed since the invitation was sent and it hasn't been accepted
    var isInvitationExpired: Bool {
        guard lastInvitationStatus == "pending",
              let sentAt = invitationSentAt else { return false }
        return sentAt.addingTimeInterval(30 * 24 * 60 * 60) < Date()
    }

    /// Status badge text for UI
    var connectionStatus: String {
        if hasFirebaseAccount && hasFolderAccess {
            return "Connected"
        } else if isInvitationExpired {
            return "Invitation Expired"
        } else if invitationSentAt != nil && lastInvitationStatus == "pending" {
            return "Invitation Pending"
        } else if lastInvitationStatus == "declined" {
            return "Invitation Declined"
        } else {
            return "Not Connected"
        }
    }

    /// Status color for UI
    var connectionStatusColor: String {
        if hasFirebaseAccount && hasFolderAccess {
            return "green"
        } else if isInvitationExpired {
            return "red"
        } else if invitationSentAt != nil && lastInvitationStatus == "pending" {
            return "orange"
        } else if lastInvitationStatus == "declined" {
            return "red"
        } else {
            return "gray"
        }
    }

    // MARK: - Firestore Sync Metadata
    var firestoreId: String?
    var needsSync: Bool = false

    init(name: String, role: String = "", phone: String = "", email: String = "", notes: String = "") {
        self.id = UUID()
        self.name = name
        self.role = role
        self.phone = phone
        self.email = email
        self.notes = notes
        self.createdAt = Date()
    }

    func toFirestoreData(athleteFirestoreId: String) -> [String: Any] {
        var data: [String: Any] = [
            "id": id.uuidString,
            "athleteId": athleteFirestoreId,
            "name": name,
            "role": role,
            "email": email,
            "createdAt": createdAt ?? Date(),
            "updatedAt": Date(),
            "isDeleted": false
        ]
        if !phone.isEmpty { data["phone"] = phone }
        if !notes.isEmpty { data["notes"] = notes }
        if let firebaseCoachID = firebaseCoachID { data["firebaseCoachID"] = firebaseCoachID }
        if let status = lastInvitationStatus { data["invitationStatus"] = status }
        return data
    }

    // MARK: - Firebase Sync Methods

    /// Updates Firebase connection status when coach accepts invitation
    func markInvitationAccepted(firebaseCoachID: String, folderID: String) {
        self.firebaseCoachID = firebaseCoachID
        self.invitationAcceptedAt = Date()
        self.lastInvitationStatus = "accepted"
        if !sharedFolderIDs.contains(folderID) {
            sharedFolderIDs.append(folderID)
        }
    }

    /// Removes folder access when athlete revokes permissions
    func removeFolderAccess(folderID: String) {
        sharedFolderIDs.removeAll { $0 == folderID }
        // Note: firebaseCoachID is intentionally preserved — it is a permanent identity
        // link and must survive losing folder access so re-sharing works without a new invite.
    }
}

// MARK: - Photo Model
@Model
final class Photo {
    var id: UUID = UUID()
    var fileName: String = ""
    var filePath: String = ""
    var thumbnailPath: String?
    var caption: String?
    var createdAt: Date?
    var athlete: Athlete?
    var game: Game?
    var practice: Practice?
    var season: Season?

    // MARK: - Firestore / Storage Sync Metadata
    var cloudURL: String?
    var firestoreId: String?
    var needsSync: Bool = false

    init(fileName: String, filePath: String) {
        self.id = UUID()
        self.fileName = fileName
        self.filePath = filePath
        self.createdAt = Date()
    }

    func toFirestoreData(ownerUID: String) -> [String: Any] {
        var data: [String: Any] = [
            "id": id.uuidString,
            "fileName": fileName,
            "athleteId": athlete?.id.uuidString ?? "",
            "uploadedBy": ownerUID,
            "createdAt": createdAt ?? Date(),
            "updatedAt": Date(),
            "isDeleted": false
        ]
        if let caption = caption { data["caption"] = caption }
        if let gameId = game?.id.uuidString { data["gameId"] = gameId }
        if let practiceId = practice?.id.uuidString { data["practiceId"] = practiceId }
        if let seasonId = season?.id.uuidString { data["seasonId"] = seasonId }
        if let cloudURL = cloudURL { data["downloadURL"] = cloudURL }
        return data
    }

    /// Full-size image URL derived from filePath
    var fileURL: URL? {
        URL(fileURLWithPath: filePath)
    }

    /// Thumbnail image URL derived from thumbnailPath
    var thumbnailURL: URL? {
        guard let thumbnailPath else { return nil }
        return URL(fileURLWithPath: thumbnailPath)
    }

    /// Delete photo with all associated files
    func delete(in context: ModelContext) {
        // Capture paths before context.delete to avoid accessing deleted SwiftData object
        let capturedFilePath = filePath
        let capturedThumbPath = thumbnailPath

        // Dispatch file I/O to background
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.removeItem(atPath: capturedFilePath)
            if let thumbPath = capturedThumbPath {
                try? FileManager.default.removeItem(atPath: thumbPath)
            }
        }
        // Delete from cloud storage if uploaded.
        // Capture fileName before context.delete(self) to avoid accessing a deleted SwiftData object.
        if cloudURL != nil {
            let capturedFileName = self.fileName
            Task { @MainActor in
                for attempt in 1...3 {
                    do {
                        try await VideoCloudManager.shared.deleteAthletePhoto(fileName: capturedFileName)
                        return
                    } catch {
                        if attempt < 3 {
                            try? await Task.sleep(for: .seconds(2))
                        }
                    }
                }
            }
        }
        context.delete(self)
    }
}

