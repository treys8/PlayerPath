//
//  HoleScore.swift
//  PlayerPath
//
//  Per-hole scoring entity for golf rounds (SchemaV25).
//  Attaches to either a Game (tournament) OR a Practice (practice round) — XOR
//  enforced at save sites, not at the schema level. The (parent, holeNumber)
//  pair is the natural primary key; firestoreId is stored as the holeNumber
//  string so re-scoring the same hole upserts rather than duplicating.
//

import Foundation
import SwiftData

@Model
final class HoleScore {
    var id: UUID = UUID()
    var holeNumber: Int = 0
    var par: Int = 4
    var score: Int = 0
    var putts: Int? = nil

    // XOR — exactly one of `game` and `practice` is non-nil. The reverse
    // relationships are declared on Game / Practice with @Relationship(inverse:).
    var game: Game?
    var practice: Practice?

    var createdAt: Date? = nil
    var updatedAt: Date? = nil

    // Firestore sync metadata
    var firestoreId: String? = nil
    var needsSync: Bool = false
    var version: Int = 0
    var isDeletedRemotely: Bool = false
    var lastSyncDate: Date? = nil

    /// Score relative to par (negative = under par).
    var diff: Int { score - par }

    /// True for any score that triggers a v6.1 auto-highlight reel (PR2).
    var isBirdieOrBetter: Bool { diff <= -1 && score > 0 }

    /// "Eagle" / "Birdie" / "Par" / "Bogey" etc. Score-relative label for cards.
    var diffLabel: String { HoleScore.diffLabel(score: score, par: par) }

    /// Same label set, computed from loose values so `ScoreHoleSheet` can label
    /// its in-flight `@State` score/par before any `HoleScore` instance exists.
    static func diffLabel(score: Int, par: Int) -> String {
        if score == 1 { return "Hole-in-One" }
        let diff = score - par
        switch diff {
        case ...(-3): return "Albatross"
        case -2:      return "Eagle"
        case -1:      return "Birdie"
        case 0:       return "Par"
        case 1:       return "Bogey"
        case 2:       return "Double Bogey"
        default:      return diff > 0 ? "+\(diff)" : "\(diff)"
        }
    }

    init(holeNumber: Int, par: Int = 4, score: Int = 0, putts: Int? = nil) {
        self.id = UUID()
        self.holeNumber = holeNumber
        self.par = par
        self.score = score
        self.putts = putts
        self.createdAt = Date()
        self.updatedAt = Date()
        self.needsSync = true
    }

    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "id": id.uuidString,
            "holeNumber": holeNumber,
            "par": par,
            "score": score,
            "createdAt": createdAt ?? Date(),
            "updatedAt": Date(),
            "version": version,
            "isDeleted": isDeletedRemotely
        ]
        if let putts = putts {
            data["putts"] = putts
        }
        return data
    }
}
