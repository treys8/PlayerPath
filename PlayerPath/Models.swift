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

    init(date: Date, opponent: String) {
        self.id = UUID()
        self.date = date
        self.opponent = opponent
        self.createdAt = Date()
        // Auto-set year from date
        let calendar = Calendar.current
        self.year = calendar.component(.year, from: date)
    }

    /// Whether this game's stats should be rolled into career/season totals.
    /// True when explicitly completed OR when the game is in progress and already
    /// has stats recorded (so quick-entered stats during a live game show up
    /// without requiring the user to end the game first).
    ///
    /// Activity checks every counter that can move independently: plate
    /// appearances cover batter-side entries (including walks and HBP which
    /// don't increment atBats), and totalPitches covers pitcher-side entries.
    var countsTowardStats: Bool {
        if isComplete { return true }
        guard let gs = gameStats else { return false }
        let plateAppearances = gs.atBats + gs.walks + gs.hitByPitches
        return plateAppearances > 0 || gs.totalPitches > 0
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

        // Inline GameStatistics counters onto the game doc ONLY when this game
        // is in manual-entry mode. Video-derived stats are re-derivable on any
        // device from synced VideoClip play results, so uploading them would
        // just create a race: if Device A re-uploads game metadata with stale
        // stats_* values, it could overwrite fresher video-derived counters on
        // Device B. Manual-entry stats have no other transport, hence the gate.
        if let gs = gameStats, gs.hasManualEntry {
            data["stats_hasManualEntry"] = gs.hasManualEntry
            data["stats_atBats"] = gs.atBats
            data["stats_hits"] = gs.hits
            data["stats_runs"] = gs.runs
            data["stats_singles"] = gs.singles
            data["stats_doubles"] = gs.doubles
            data["stats_triples"] = gs.triples
            data["stats_homeRuns"] = gs.homeRuns
            data["stats_rbis"] = gs.rbis
            data["stats_strikeouts"] = gs.strikeouts
            data["stats_walks"] = gs.walks
            data["stats_groundOuts"] = gs.groundOuts
            data["stats_flyOuts"] = gs.flyOuts
            data["stats_hitByPitches"] = gs.hitByPitches
            data["stats_totalPitches"] = gs.totalPitches
            data["stats_balls"] = gs.balls
            data["stats_strikes"] = gs.strikes
            data["stats_wildPitches"] = gs.wildPitches
            data["stats_pitchingStrikeouts"] = gs.pitchingStrikeouts
            data["stats_pitchingWalks"] = gs.pitchingWalks
            data["stats_fastballPitchCount"] = gs.fastballPitchCount
            data["stats_fastballSpeedTotal"] = gs.fastballSpeedTotal
            data["stats_offspeedPitchCount"] = gs.offspeedPitchCount
            data["stats_offspeedSpeedTotal"] = gs.offspeedSpeedTotal
        }
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

