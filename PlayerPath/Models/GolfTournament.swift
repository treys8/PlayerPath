//
//  GolfTournament.swift
//  PlayerPath
//
//  Multi-round golf tournament (SchemaV27). A grouping entity that sits ABOVE
//  Game — the same way Season sits above Game — so several golf rounds roll up
//  into one tournament with an aggregate stroke-play score.
//
//  Optional container: a golf Game (a "round") may belong to a tournament OR
//  stand alone. Deleting a tournament UNLINKS its rounds (they survive as
//  standalone rounds), it does NOT cascade-delete them. Per-athlete top-level
//  entity; sync mirrors Season (see SyncCoordinator+GolfTournaments).
//

import Foundation
import SwiftData

@Model
final class GolfTournament {
    var id: UUID = UUID()
    var name: String = ""
    var location: String?
    var startDate: Date?
    var endDate: Date?
    var notes: String?
    var createdAt: Date?

    var athlete: Athlete?
    /// Rounds belonging to this tournament. The owning side is `Game.tournament`.
    @Relationship(inverse: \Game.tournament) var rounds: [Game]?

    // MARK: - Firestore Sync Metadata

    /// Firestore document ID (maps to `users/{uid}/golfTournaments/{id}`).
    var firestoreId: String?
    /// Last successful sync timestamp.
    var lastSyncDate: Date?
    /// Dirty flag — true when local changes need uploading.
    var needsSync: Bool = false
    /// Soft delete flag — true when deleted on another device.
    var isDeletedRemotely: Bool = false
    /// Version number for conflict resolution.
    var version: Int = 0

    init(name: String, startDate: Date? = nil) {
        self.id = UUID()
        self.name = name
        self.startDate = startDate
        self.createdAt = Date()
    }

    // MARK: - Aggregate scoring (stroke play)

    /// Rounds ordered for display — by `roundNumber` first, then date. Rounds
    /// without a number (legacy / not-yet-numbered) sort last.
    var sortedRounds: [Game] {
        (rounds ?? []).sorted { lhs, rhs in
            let l = lhs.roundNumber ?? Int.max
            let r = rhs.roundNumber ?? Int.max
            if l != r { return l < r }
            return (lhs.date ?? .distantPast) < (rhs.date ?? .distantPast)
        }
    }

    /// Rounds with a complete, stats-eligible score (reuses Game.isGolfRoundScored).
    /// Live rounds are excluded — an in-progress round must not pollute the
    /// aggregate (mirrors GolfStatsSection, which also gates on `!isLive`).
    var scoredRounds: [Game] {
        (rounds ?? []).filter { !$0.isLive && $0.isGolfRoundScored }
    }

    /// Aggregate stroke total across scored rounds, or nil when none are scored.
    var totalStrokes: Int? {
        let strokes = scoredRounds.compactMap { $0.effectiveTotalScore }
        return strokes.isEmpty ? nil : strokes.reduce(0, +)
    }

    /// Combined score-to-par across scored rounds. Each round is compared against
    /// its own par (mirrors Game.effectivePar) so a mix of 9- and 18-hole rounds
    /// totals correctly. Returns nil unless EVERY scored round has a par — so the
    /// to-par figure always covers the same round set as `totalStrokes` and the
    /// two can never silently disagree.
    var totalToPar: Int? {
        let scored = scoredRounds
        guard !scored.isEmpty else { return nil }
        var sum = 0
        for round in scored {
            guard let strokes = round.effectiveTotalScore,
                  let par = round.effectivePar else { return nil }
            sum += strokes - par
        }
        return sum
    }

    /// "E" / "+3" / "-2" for the aggregate to-par, or nil when not yet scoreable.
    var displayToPar: String? {
        guard let toPar = totalToPar else { return nil }
        if toPar == 0 { return "E" }
        return toPar > 0 ? "+\(toPar)" : "\(toPar)"
    }

    // MARK: - Deletion

    /// Deletes the tournament locally, UNLINKING its rounds so they survive as
    /// standalone rounds (optional-container semantics). Each unlinked round is
    /// re-dirtied so the cleared `tournamentId` re-syncs to Firestore.
    ///
    /// Firestore soft-delete is the caller's responsibility (mirrors
    /// SeasonService.deleteSeason) — call FirestoreManager.deleteGolfTournament
    /// before this, then sync rounds.
    @MainActor func delete(in context: ModelContext) {
        for round in rounds ?? [] {
            round.tournament = nil
            round.roundNumber = nil
            round.needsSync = true
        }
        rounds = nil
        context.delete(self)
    }

    // MARK: - Firestore Conversion

    func toFirestoreData() -> [String: Any] {
        // Prefer firestoreId for the athlete reference so it survives reinstalls;
        // fall back to local UUID for athletes that haven't synced yet.
        let athleteRef = athlete?.firestoreId ?? athlete?.id.uuidString ?? ""
        return [
            "id": id.uuidString,
            "name": name,
            "athleteId": athleteRef,
            "location": location as Any,
            "startDate": startDate as Any,
            "endDate": endDate as Any,
            "notes": notes as Any,
            "createdAt": createdAt ?? Date(),
            "updatedAt": Date(),
            "version": version,
            "isDeleted": false
        ]
    }
}
