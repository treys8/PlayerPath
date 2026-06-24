//
//  GolfScoreWriter.swift
//  PlayerPath
//
//  Shared write path for golf per-hole scoring. Used by BOTH ScoreHoleSheet
//  (one hole at a time) and GolfScorecardView (a whole round on one screen).
//  Centralizes the three things that must stay byte-identical across the two
//  entry points or totals/reels drift apart:
//
//    1. the HoleScore upsert (insert / update-in-place, keyed by holeNumber),
//    2. the Game.totalScore running-sum mirror (synced transport + the
//       cross-device fallback read by effectiveTotalScore), and
//    3. the birdie-or-better auto-highlight reel (idempotent on (parent,hole)).
//
//  None of these methods call `context.save()` — the caller batches a single
//  save so a multi-hole scorecard commits atomically (and a rapid re-tap can't
//  half-write). Operates on `GolfRoundRef` (defined in HoleDetailView.swift),
//  which already abstracts Game (tournament round) vs Practice (practice round).
//

import Foundation
import SwiftData

@MainActor
enum GolfScoreWriter {

    /// One hole's values to persist. Putts and the detailed fields are optional
    /// (nil = not tracked); the detailed ones stay nil unless the user has
    /// detailed tracking on and entered them.
    struct HoleInput {
        let holeNumber: Int
        let par: Int
        let score: Int
        let putts: Int?
        var fairwayHit: Bool? = nil
        var greenInRegulation: Bool? = nil
        var penalties: Int? = nil
        /// Hole length in yards (SchemaV31), as an opt-in write: `.none` (default)
        /// leaves the hole's existing yardage UNTOUCHED — so score-only writers
        /// (the scorecard grid, the shot rollup) never clobber a yardage set
        /// elsewhere. `.some(x)` sets it (x may be nil to clear). Only the
        /// yardage-aware editors (Quick / Shot-by-shot) pass a value.
        var yardage: Int?? = .none
    }

    // MARK: - Hole upsert

    /// Inserts or updates the HoleScore row for `input.holeNumber` in place.
    /// Mirrors ScoreHoleSheet's original save branch exactly (version bump +
    /// needsSync so the row re-syncs). Does NOT save the context.
    static func upsertHole(_ input: HoleInput, in ref: GolfRoundRef, context: ModelContext) {
        if let existing = ref.holeScores.first(where: { $0.holeNumber == input.holeNumber }) {
            existing.par = input.par
            existing.score = input.score
            existing.putts = input.putts
            existing.fairwayHit = input.fairwayHit
            existing.greenInRegulation = input.greenInRegulation
            existing.penalties = input.penalties
            // Opt-in: only touch yardage when the caller provided one (.some);
            // score-only writers leave `.none` and preserve any set yardage.
            if case let .some(yardage) = input.yardage { existing.yardage = yardage }
            existing.updatedAt = Date()
            existing.version += 1
            existing.needsSync = true
        } else {
            let new = HoleScore(
                holeNumber: input.holeNumber,
                par: input.par,
                score: input.score,
                putts: input.putts,
                fairwayHit: input.fairwayHit,
                greenInRegulation: input.greenInRegulation,
                penalties: input.penalties,
                yardage: input.yardage ?? nil   // .none → nil; .some(x) → x
            )
            switch ref {
            case .game(let g):     new.game = g
            case .practice(let p): new.practice = p
            }
            context.insert(new)
        }
    }

    // MARK: - Total mirror (games only)

    /// Mirrors the per-hole running sum onto `Game.totalScore`. Practices carry
    /// no totalScore scalar (they derive live), so this is a no-op for them.
    ///
    /// `justWrote` folds the in-flight inputs in by hole number so the total is
    /// correct even before SwiftData reflects freshly-inserted rows in
    /// `g.holeScores` — the same insert-timing guard ScoreHoleSheet used.
    static func mirrorTotalScore(in ref: GolfRoundRef, justWrote inputs: [HoleInput]) {
        guard case .game(let g) = ref else { return }
        var scoreByHole: [Int: Int] = [:]
        for h in (g.holeScores ?? []) { scoreByHole[h.holeNumber] = h.score }
        for input in inputs { scoreByHole[input.holeNumber] = input.score }
        let sum = scoreByHole.values.reduce(0, +)
        if g.totalScore != sum {
            g.totalScore = sum
            g.needsSync = true
        }
    }

    // MARK: - Auto-highlight reel (PR2/PR3 parity)

    /// Creates / updates / soft-deletes the HighlightReel for one hole based on
    /// the score just saved. Birdie-or-better with ≥1 attributed clip → upsert;
    /// otherwise → demote (soft-delete) any existing reel. Idempotent: a re-save
    /// with the same clip set / score / par does NOT bump version + needsSync.
    /// Does NOT save the context. Moved verbatim from ScoreHoleSheet so the
    /// scorecard and the single-hole sheet produce identical reels.
    static func upsertReelIfNeeded(holeNumber: Int, par: Int, score: Int, in ref: GolfRoundRef, context: ModelContext) {
        guard let athlete = roundAthlete(ref) else { return }
        let athleteID = athlete.id
        let course = ref.titleBase
        let isBirdieOrBetter = score > 0 && (score - par) <= -1

        // Auto-highlight curation is free (parity with baseball, whose play-result
        // tagging is ungated): every birdie-or-better hole with a clip creates a
        // reel regardless of tier. Access to play/export the reel stays Plus-gated
        // at the Highlights folder + reel CTAs, not here at curation time. A reel
        // is demoted only when its hole stops being birdie-or-better.

        let parentGameID: UUID?
        let parentPracticeID: UUID?
        switch ref {
        case .game(let g):     parentGameID = g.id;   parentPracticeID = nil
        case .practice(let p): parentGameID = nil;    parentPracticeID = p.id
        }

        let holeClips: [VideoClip] = ref.videoClips.filter { $0.holeNumber == holeNumber }
        let clipsOnHole: [VideoClip] = holeClips.sorted { lhs, rhs in
            (lhs.createdAt ?? .distantPast) < (rhs.createdAt ?? .distantPast)
        }

        // Lookup existing reel for this (parent, hole) — alive or soft-deleted.
        // SwiftData #Predicate can't equate optional UUIDs cleanly, so fetch
        // flat and filter in memory (see feedback_swiftdata_predicate_no_transforms).
        let existing: HighlightReel?
        do {
            let all = try context.fetch(FetchDescriptor<HighlightReel>())
            existing = all.first { reel in
                reel.holeNumber == holeNumber &&
                    (parentGameID.map { reel.gameID == $0 } ?? false ||
                     parentPracticeID.map { reel.practiceID == $0 } ?? false)
            }
        } catch {
            ErrorHandlerService.shared.handle(
                error,
                context: "GolfScoreWriter.upsertReelIfNeeded.fetch",
                showAlert: false
            )
            return
        }

        if isBirdieOrBetter && !clipsOnHole.isEmpty {
            let clipIDStrings = clipsOnHole.map { $0.id.uuidString }
            let displayName = reelDisplayName(score: score, par: par)

            if let existing {
                let differs = existing.clipIDs != clipIDStrings
                    || existing.score != score
                    || existing.par != par
                    || existing.displayName != displayName
                    || existing.courseOrOpponent != course
                    || existing.isDeletedRemotely
                if differs {
                    existing.clipIDs = clipIDStrings
                    existing.score = score
                    existing.par = par
                    existing.displayName = displayName
                    existing.courseOrOpponent = course
                    existing.date = Date()
                    existing.isDeletedRemotely = false
                    existing.version += 1
                    existing.needsSync = true
                }
            } else {
                let reel = HighlightReel(
                    clipIDs: clipIDStrings,
                    athleteID: athleteID,
                    gameID: parentGameID,
                    practiceID: parentPracticeID,
                    holeNumber: holeNumber,
                    score: score,
                    par: par,
                    displayName: displayName,
                    courseOrOpponent: course
                )
                context.insert(reel)
            }
        } else {
            if let existing, !existing.isDeletedRemotely {
                existing.isDeletedRemotely = true
                existing.version += 1
                existing.needsSync = true
            }
        }
    }

    // MARK: - Par seeding (shared by both entry points)

    /// Par for `hole` from the most recent *prior* round at the same course, so
    /// per-hole par carries across rounds rather than resetting each time. Games
    /// key off `opponent` (the course name for golf); practices off
    /// `Practice.course`. Returns nil when the athlete hasn't scored this hole
    /// here before — callers fall back to an in-round seed, then 4.
    static func priorRoundPar(forHole hole: Int, in ref: GolfRoundRef) -> Int? {
        switch ref {
        case .game(let current):
            guard let athlete = current.athlete, !current.opponent.isEmpty else { return nil }
            let prior = (athlete.games ?? [])
                .filter { $0.id != current.id && $0.opponent == current.opponent
                          && ($0.season?.sport ?? .baseball) == .golf }
                .max(by: { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) })
            return prior?.holeScores?.first { $0.holeNumber == hole }?.par
        case .practice(let current):
            guard let athlete = current.athlete,
                  let course = current.course, !course.isEmpty else { return nil }
            let prior = (athlete.practices ?? [])
                .filter { $0.id != current.id && $0.course == course }
                .max(by: { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) })
            return prior?.holeScores?.first { $0.holeNumber == hole }?.par
        }
    }

    /// Hole length in yards for `hole` from the most recent *prior* round at the
    /// same course, so per-hole yardage carries across rounds (mirrors
    /// `priorRoundPar`). Returns nil when unknown — unlike par's `4` there is NO
    /// sensible constant fallback for yardage, and no "previous hole" fallback
    /// (each hole has a distinct length), so the field stays empty rather than
    /// inventing a default that would mislead the derived drive distance.
    static func priorRoundYardage(forHole hole: Int, in ref: GolfRoundRef) -> Int? {
        switch ref {
        case .game(let current):
            guard let athlete = current.athlete, !current.opponent.isEmpty else { return nil }
            let prior = (athlete.games ?? [])
                .filter { $0.id != current.id && $0.opponent == current.opponent
                          && ($0.season?.sport ?? .baseball) == .golf }
                .max(by: { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) })
            return prior?.holeScores?.first { $0.holeNumber == hole }?.yardage
        case .practice(let current):
            guard let athlete = current.athlete,
                  let course = current.course, !course.isEmpty else { return nil }
            let prior = (athlete.practices ?? [])
                .filter { $0.id != current.id && $0.course == course }
                .max(by: { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) })
            return prior?.holeScores?.first { $0.holeNumber == hole }?.yardage
        }
    }

    // MARK: - Scorecard scan (SchemaV32)

    /// One hole's confirmed scan values, persisted as JSON in
    /// `Game.scorecardData` / `Practice.scorecardData`. The tee has already been
    /// collapsed to a single `yardage` column by the confirm grid.
    struct ScannedHole: Codable, Equatable {
        let hole: Int
        let par: Int
        let yardage: Int?
    }

    /// Decoded scanned card for `ref`, or `[]` when none / unparseable.
    static func scannedCard(in ref: GolfRoundRef) -> [ScannedHole] {
        guard let json = ref.scorecardData, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([ScannedHole].self, from: data)) ?? []
    }

    /// Par for `hole` from the confirmed scan of the CURRENT round (vs
    /// `priorRoundPar`, which reads other rounds). Seeds the scoring sheets
    /// BETWEEN `existing` and the prior-round fallback. nil when unscanned / not
    /// in the card.
    static func scannedPar(forHole hole: Int, in ref: GolfRoundRef) -> Int? {
        scannedCard(in: ref).first { $0.hole == hole }?.par
    }

    /// Yardage for `hole` from the confirmed scan of the CURRENT round. nil when
    /// unscanned, not in the card, or the card left it blank.
    static func scannedYardage(forHole hole: Int, in ref: GolfRoundRef) -> Int? {
        scannedCard(in: ref).first { $0.hole == hole }?.yardage
    }

    /// Persist a confirmed scorecard scan WITHOUT materializing rows for
    /// unplayed holes — this preserves the no-phantom-score-0-hole invariant.
    /// Stores the card as a JSON blob that seeds each hole lazily when it's
    /// scored; records the tee; and for the GAME case sets the par/holes scalars
    /// so the pre-play to-par display (`effectivePar` falls back to `Game.par`
    /// while no hole is scored) is correct. Holes that ALREADY have a row (were
    /// played) get par + yardage updated in place — score/putts/penalties/FIR/GIR
    /// are never touched. Does NOT call `mirrorTotalScore` (no score change) and
    /// does NOT save the context (caller batches the save).
    static func applyScannedCard(_ holes: [ScannedHole], tee: String?, to ref: GolfRoundRef, context: ModelContext) {
        // 1. Card blob + tee on the round.
        if let json = try? JSONEncoder().encode(holes), let str = String(data: json, encoding: .utf8) {
            ref.scorecardData = str
        }
        ref.selectedTee = tee

        // 2. Game par scalar: summed par so a freshly-scanned, unplayed round
        //    reads a sensible course par (effectivePar's pre-play fallback). Set
        //    it ONLY when the scan covers the whole round — a partial read (e.g.
        //    9 of 18 holes confirmed) would otherwise set par to ~36 on an
        //    18-hole round and clobber a par the user may have typed. Never touch
        //    `holes` — the hole count is the user's pick, not what the scan read.
        if case .game(let g) = ref, !holes.isEmpty {
            let roundHoles = g.holes ?? holes.count
            if holes.count >= roundHoles {
                g.par = holes.reduce(0) { $0 + $1.par }
            }
        }
        switch ref {
        case .game(let g):     g.needsSync = true
        case .practice(let p): p.needsSync = true
        }

        // 3. In-place update of already-played holes only. NO new rows, so an
        //    unplayed hole never becomes a phantom score-0 row.
        let byHole = Dictionary(holes.map { ($0.hole, $0) }, uniquingKeysWith: { first, _ in first })
        for existing in ref.holeScores {
            guard let scan = byHole[existing.holeNumber] else { continue }
            var changed = false
            if existing.par != scan.par { existing.par = scan.par; changed = true }
            if existing.yardage != scan.yardage { existing.yardage = scan.yardage; changed = true }
            if changed {
                existing.updatedAt = Date()
                existing.version += 1
                existing.needsSync = true
            }
        }
    }

    // MARK: - Helpers

    private static func roundAthlete(_ ref: GolfRoundRef) -> Athlete? {
        switch ref {
        case .game(let g):     return g.athlete
        case .practice(let p): return p.athlete
        }
    }

    /// "Hole-in-One" / "Albatross" / "Eagle" / "Birdie" — only under-par buckets
    /// are reachable here (caller already checked birdie-or-better).
    private static func reelDisplayName(score: Int, par: Int) -> String {
        if score == 1 { return "Hole-in-One" }
        let diff = score - par
        switch diff {
        case ...(-3): return "Albatross"
        case -2:      return "Eagle"
        default:      return "Birdie"
        }
    }
}
