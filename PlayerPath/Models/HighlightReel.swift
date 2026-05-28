//
//  HighlightReel.swift
//  PlayerPath
//
//  Reference-based virtual reel (SchemaV25). Stores an ordered list of
//  VideoClip UUIDs that will be chained via AVQueuePlayer at playback time — no
//  re-encoding, no extra storage. Created in PR2 when a HoleScore for a golf
//  round is saved at birdie-or-better and ≥1 clip is attributed to that hole.
//
//  In PR1 the type exists in the schema only so that V25 can land without a
//  second migration when PR2 wires creation + playback.
//

import Foundation
import SwiftData

@Model
final class HighlightReel {
    var id: UUID = UUID()

    /// Ordered list of `VideoClip.id.uuidString`. SwiftData stores `[String]`
    /// natively via Codable on iOS 17+; no external storage needed for the
    /// small clip counts a single hole generates.
    var clipIDs: [String] = []

    /// Denormalized for fast lookups + cross-device merge (the @Relationship
    /// to Athlete is not stored on the reel itself to avoid an extra inverse).
    var athleteID: UUID = UUID()

    /// XOR — set exactly one of these to the parent's id.
    var gameID: UUID? = nil
    var practiceID: UUID? = nil

    var holeNumber: Int = 0
    var score: Int = 0
    var par: Int = 4

    /// Pre-rendered label ("Birdie", "Eagle", ...) — derived from score/par at
    /// creation and frozen, so card display is cheap and consistent.
    var displayName: String = "Birdie"

    /// Course (golf) or opponent (baseball, future). Denormalized so a card
    /// can render without re-fetching the parent Game/Practice.
    var courseOrOpponent: String = ""

    var date: Date = Date()
    var createdAt: Date? = nil

    // Firestore sync metadata
    var firestoreId: String? = nil
    var needsSync: Bool = false
    var version: Int = 0
    var isDeletedRemotely: Bool = false
    var lastSyncDate: Date? = nil

    init(
        clipIDs: [String],
        athleteID: UUID,
        gameID: UUID? = nil,
        practiceID: UUID? = nil,
        holeNumber: Int,
        score: Int,
        par: Int,
        displayName: String,
        courseOrOpponent: String
    ) {
        self.id = UUID()
        self.clipIDs = clipIDs
        self.athleteID = athleteID
        self.gameID = gameID
        self.practiceID = practiceID
        self.holeNumber = holeNumber
        self.score = score
        self.par = par
        self.displayName = displayName
        self.courseOrOpponent = courseOrOpponent
        self.date = Date()
        self.createdAt = Date()
        self.needsSync = true
    }

    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "id": id.uuidString,
            "athleteID": athleteID.uuidString,
            "holeNumber": holeNumber,
            "score": score,
            "par": par,
            "displayName": displayName,
            "courseOrOpponent": courseOrOpponent,
            "clipIDs": clipIDs,
            "date": date,
            "createdAt": createdAt ?? Date(),
            "updatedAt": Date(),
            "version": version,
            "isDeleted": isDeletedRemotely
        ]
        if let gameID { data["gameID"] = gameID.uuidString }
        if let practiceID { data["practiceID"] = practiceID.uuidString }
        return data
    }
}
