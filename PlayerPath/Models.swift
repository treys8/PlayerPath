//
//  Models.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import Foundation
import SwiftData
import os

let modelsLog = Logger(subsystem: "com.playerpath.app", category: "Models")


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
    @MainActor func delete(in context: ModelContext) {
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

