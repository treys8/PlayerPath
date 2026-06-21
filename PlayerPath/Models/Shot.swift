//
//  Shot.swift
//  PlayerPath
//
//  Per-shot row for shot-by-shot golf tracking (SchemaV30). Nests under a
//  `HoleScore` via the `holeScore` inverse (cascade-deleted with its hole), so
//  derivation is purely intra-hole and there are no orphan sweeps. The hole's
//  score / FIR / GIR / putts are DERIVED from its shots (see `ShotRollup`) —
//  shots are the source of truth, `HoleScore` is the rollup.
//
//  Firestore doc id is the shot UUID (NOT shotNumber) because shots reorder on
//  delete/insert; `shotNumber` is a plain sort field. Enum values are stored as
//  rawValue strings for additive wire safety (same pattern as `Club`).
//

import Foundation
import SwiftData

@Model
final class Shot {
    var id: UUID = UUID()

    /// 1-based order within the hole. Sort field only — never the doc id.
    var shotNumber: Int = 1

    /// Backing rawValue stores (typed accessors below). Optional club so a
    /// logged-but-unclubbed shot is still valid.
    var clubRaw: String? = nil
    var lieRaw: String = "tee"
    var outcomeRaw: String = "fairway"

    /// Penalty strokes incurred on this shot (usually 0; 1 for water/OB/lost,
    /// 2 for the rare double). Added to the derived hole score, never replaces
    /// a shot.
    var penaltyStrokes: Int = 0

    /// Optional yards-to-hole BEFORE the shot (rangefinder entry). Captured in
    /// v1 on approach + par-3 tee shots; consumed by v2 Strokes Gained. nil =
    /// not entered.
    var distanceBefore: Int? = nil

    /// Forward-compat scaffold for a future per-putt mode. Never set true in
    /// v1 (putts are a single count rolled into `HoleScore.putts`). Present now
    /// so adding per-putt rows later needs no schema bump.
    var isPutt: Bool = false

    /// Inverse of `HoleScore.shots`.
    var holeScore: HoleScore?

    var createdAt: Date? = nil
    var updatedAt: Date? = nil

    // Firestore sync metadata — mirrors `HoleScore`.
    var firestoreId: String? = nil
    var needsSync: Bool = false
    var version: Int = 0
    var isDeletedRemotely: Bool = false
    var lastSyncDate: Date? = nil

    // MARK: - Typed accessors (wrap the rawValue stores)

    var club: Club? {
        get { clubRaw.flatMap(Club.init(rawValue:)) }
        set { clubRaw = newValue?.rawValue }
    }

    var lie: ShotLie {
        get { ShotLie(rawValue: lieRaw) ?? .tee }
        set { lieRaw = newValue.rawValue }
    }

    var outcome: ShotOutcome {
        get { ShotOutcome(rawValue: outcomeRaw) ?? .fairway }
        set { outcomeRaw = newValue.rawValue }
    }

    init(shotNumber: Int,
         club: Club? = nil,
         lie: ShotLie = .tee,
         outcome: ShotOutcome = .fairway,
         penaltyStrokes: Int = 0,
         distanceBefore: Int? = nil,
         isPutt: Bool = false) {
        self.id = UUID()
        self.shotNumber = shotNumber
        self.clubRaw = club?.rawValue
        self.lieRaw = lie.rawValue
        self.outcomeRaw = outcome.rawValue
        self.penaltyStrokes = penaltyStrokes
        self.distanceBefore = distanceBefore
        self.isPutt = isPutt
        self.createdAt = Date()
        self.updatedAt = Date()
        self.needsSync = true
    }

    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "id": id.uuidString,
            "shotNumber": shotNumber,
            "lie": lieRaw,
            "outcome": outcomeRaw,
            "penaltyStrokes": penaltyStrokes,
            "isPutt": isPutt,
            "createdAt": createdAt ?? Date(),
            "updatedAt": Date(),
            "version": version,
            "isDeleted": isDeletedRemotely
        ]
        if let clubRaw = clubRaw {
            data["club"] = clubRaw
        }
        if let distanceBefore = distanceBefore {
            data["distanceBefore"] = distanceBefore
        }
        return data
    }
}
