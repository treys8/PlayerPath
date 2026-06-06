//
//  ScoreHoleSheet.swift
//  PlayerPath
//
//  Per-hole scoring entry for a live golf tournament (PR1) or practice round
//  (PR3). Opens with the passed `holeNumber` preselected. If a HoleScore
//  already exists for (parent, holeNumber) we pre-fill from it and save edits;
//  otherwise we insert a new row. Save → upsert HoleScore → upsert/demote
//  HighlightReel (PR2 — works for both parents) → dismiss.
//

import SwiftUI
import SwiftData

struct ScoreHoleSheet: View {
    /// XOR parent — exactly one is non-nil at construction. Internal storage
    /// lets us share all UI / save logic via small switch branches without
    /// duplicating the view body.
    private enum Parent {
        case game(Game)
        case practice(Practice)
    }
    private let parent: Parent
    let holeNumber: Int

    init(game: Game, holeNumber: Int) {
        self.parent = .game(game)
        self.holeNumber = holeNumber
    }

    init(practice: Practice, holeNumber: Int) {
        self.parent = .practice(practice)
        self.holeNumber = holeNumber
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var par: Int = 4
    @State private var score: Int = 4
    @State private var putts: Int? = nil
    @State private var includePutts: Bool = false
    @State private var didLoad: Bool = false

    /// Tracks whether the user has tapped a score chip. Until they do, changing
    /// par keeps the score even (score follows par) so a fresh hole defaults to
    /// par. Once set, par changes only recolor the hero — they don't move score.
    @State private var scoreManuallySet: Bool = false

    /// Existing row for this hole, if any. Cached so save() can update in
    /// place rather than creating a duplicate row.
    @State private var existingHole: HoleScore? = nil

    /// Re-entrancy guard. A rapid double-tap of Save would otherwise re-enter
    /// before dismiss propagates and insert a second HoleScore (and reel) for
    /// the same hole, corrupting totals.
    @State private var isSaving: Bool = false

    // MARK: - Parent accessors

    private var parentHoles: [HoleScore] {
        switch parent {
        case .game(let g):     return g.holeScores ?? []
        case .practice(let p): return p.holeScores ?? []
        }
    }

    private var parentClips: [VideoClip] {
        switch parent {
        case .game(let g):     return g.videoClips ?? []
        case .practice(let p): return p.videoClips ?? []
        }
    }

    private var parentAthlete: Athlete? {
        switch parent {
        case .game(let g):     return g.athlete
        case .practice(let p): return p.athlete
        }
    }

    /// Course / opponent label for reels. Games use the opponent field (which
    /// for golf is the course name); practice rounds don't carry one yet so
    /// the reel falls back to "Practice Round" — HighlightReelCard renders
    /// that as the location line.
    private var parentCourse: String {
        switch parent {
        case .game(let g):     return g.opponent
        case .practice:        return "Practice Round"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: .spacingLarge) {
                    ScoreHeroCard(score: score, par: par)

                    // Par — one-tap segmented control, seeds the score default.
                    VStack(alignment: .leading, spacing: .spacingSmall) {
                        Text("PAR")
                            .font(.labelMedium)
                            .foregroundColor(.secondary)
                        Picker("Par", selection: $par) {
                            ForEach(3...5, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: par) { _, newPar in
                            if !scoreManuallySet { score = newPar }
                        }
                    }

                    // Score — tap the number you shot.
                    VStack(alignment: .leading, spacing: .spacingSmall) {
                        Text("SCORE")
                            .font(.labelMedium)
                            .foregroundColor(.secondary)
                        NumberChipGrid(range: 1...15, selected: score, par: par) { value in
                            score = value
                            scoreManuallySet = true
                        }
                    }

                    // Putts — optional, behind the toggle as before.
                    VStack(alignment: .leading, spacing: .spacingSmall) {
                        Toggle("Track Putts", isOn: $includePutts.animation())
                            .font(.bodyLarge)
                            .onChange(of: includePutts) { _, on in
                                // Seed a default so the highlighted chip matches
                                // what save() will persist (save writes nil if
                                // putts is still nil, even with the toggle on).
                                if on, putts == nil { putts = 2 }
                            }
                        if includePutts {
                            // Putts can never exceed total strokes — cap the grid
                            // at the score so an impossible round can't be entered.
                            NumberChipGrid(range: 0...min(10, score), selected: min(putts ?? 2, score), par: nil) { value in
                                putts = value
                            }
                        } else {
                            Text("Putts are optional.")
                                .font(.bodySmall)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.spacingLarge)
            }
            .ppDetailBackground()
            .navigationTitle("Score Hole \(holeNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(score < 1 || isSaving)
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .onAppear { loadIfNeeded() }
        }
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        let holes = parentHoles
        if let existing = holes.first(where: { $0.holeNumber == holeNumber }) {
            existingHole = existing
            par = existing.par
            score = existing.score
            // Already a real score — par tweaks shouldn't drag it along.
            scoreManuallySet = true
            if let p = existing.putts {
                putts = p
                includePutts = true
            }
            return
        }

        // New hole — seed par. Priority:
        //  1. Same hole at the most recent prior round on this course — a strong
        //     signal (hole 7 stays a par 3 every visit), so the golfer doesn't
        //     re-enter the layout each round.
        //  2. Most recently scored prior hole in THIS round — weak fallback for
        //     a first-time course (a user who set par=5 on 3 keeps it on 4).
        //  3. 4.
        let priorHoles = holes.filter { $0.holeNumber < holeNumber }
        let inRoundPar = priorHoles.max(by: { $0.holeNumber < $1.holeNumber })?.par
        let seedPar = priorRoundPar(forHole: holeNumber) ?? inRoundPar ?? 4
        par = seedPar
        score = seedPar
    }

    /// Par for `hole` from the most recent *prior* round at the same course, so
    /// per-hole par carries across rounds rather than resetting each time.
    /// Games key off `opponent` (the course name for golf); practice rounds key
    /// off `Practice.course`. Returns nil when the athlete hasn't played here
    /// before (or never scored this hole), falling back to the in-round seed.
    private func priorRoundPar(forHole hole: Int) -> Int? {
        guard let athlete = parentAthlete else { return nil }
        switch parent {
        case .game(let current):
            guard !current.opponent.isEmpty else { return nil }
            let prior = (athlete.games ?? [])
                .filter { $0.id != current.id && $0.opponent == current.opponent
                          && ($0.season?.sport ?? .baseball) == .golf }
                .max(by: { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) })
            return prior?.holeScores?.first { $0.holeNumber == hole }?.par
        case .practice(let current):
            guard let course = current.course, !course.isEmpty else { return nil }
            let prior = (athlete.practices ?? [])
                .filter { $0.id != current.id && $0.course == course }
                .max(by: { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) })
            return prior?.holeScores?.first { $0.holeNumber == hole }?.par
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true

        // Putts can never exceed strokes; clamp defensively in case state was
        // seeded above the score before the grid re-rendered. Preserve the
        // original nil-when-unset semantics (don't coerce a missing value to 0).
        let savedPutts: Int? = includePutts ? putts.map { min($0, score) } : nil

        if let existing = existingHole {
            existing.par = par
            existing.score = score
            existing.putts = savedPutts
            existing.updatedAt = Date()
            existing.version += 1
            existing.needsSync = true
        } else {
            let new = HoleScore(
                holeNumber: holeNumber,
                par: par,
                score: score,
                putts: savedPutts
            )
            switch parent {
            case .game(let g):     new.game = g
            case .practice(let p): new.practice = p
            }
            modelContext.insert(new)
        }

        // Mirror the per-hole running sum onto Game.totalScore on EVERY save,
        // not only when all holes are entered. totalScore is the synced
        // transport and the cross-device fallback read by effectiveTotalScore,
        // so keeping it equal to the live hole sum means a second device shows a
        // correct total even before the per-hole rows replicate — and a partial
        // round is never invisible in GolfStatsSection / GameRow. Practices
        // carry no totalScore scalar (they derive live), so only games mirror.
        //
        // Build the effective hole→score map explicitly (keyed by holeNumber)
        // rather than reading `g.holeScores` alone: that collection isn't
        // guaranteed to reflect the row inserted above before save(). Folding in
        // (holeNumber, score) here is dedupe-safe and insert-timing-safe.
        if case .game(let g) = parent {
            var scoreByHole: [Int: Int] = [:]
            for h in (g.holeScores ?? []) { scoreByHole[h.holeNumber] = h.score }
            scoreByHole[holeNumber] = score
            let sum = scoreByHole.values.reduce(0, +)
            if g.totalScore != sum {
                g.totalScore = sum
                g.needsSync = true
            }
        }

        // v6.1 PR2 (game) + PR3 (practice): auto-highlight reel for birdie-
        // or-better holes with attributed clips. Idempotent on
        // (parentID, holeNumber).
        upsertReelIfNeeded(par: par, score: score)

        do {
            try modelContext.save()
        } catch {
            isSaving = false
            ErrorHandlerService.shared.handle(error, context: "ScoreHoleSheet.save", showAlert: true)
            return
        }

        Haptics.success()
        dismiss()
    }

    /// Creates / updates / soft-deletes the HighlightReel for this hole based
    /// on the score that's about to be saved. Single transaction with the
    /// HoleScore upsert — both commit together when `modelContext.save()` runs.
    ///
    /// Birdie+ semantics:
    ///   - score < par AND clips-on-hole.count >= 1 → upsert reel
    ///     (existing soft-deleted reels are undeleted + clipIDs refreshed)
    ///   - otherwise → soft-delete existing reel (or no-op if none exists)
    ///
    /// Reads `parentClips` for the clip list — those clips have `holeNumber`
    /// stamped at save time by ClipPersistenceService via LiveHoleTracker
    /// (works for both game tournaments and practice rounds).
    private func upsertReelIfNeeded(par: Int, score: Int) {
        guard let athlete = parentAthlete else { return }
        let athleteID = athlete.id
        let course = parentCourse
        let isBirdieOrBetter = score > 0 && (score - par) <= -1

        // Auto-highlights are a Plus+ feature — parity with baseball, where the
        // auto-highlight rules panel in HighlightsView is gated to `>= .plus`.
        // A free golfer scoring a birdie creates no reel. A reel that predates a
        // downgrade is demoted by the else-branch below on the next re-score of
        // its hole, so the feature stops producing highlights once the
        // entitlement lapses rather than silently continuing.
        let canAutoHighlight = SubscriptionGate.effectiveAthleteTier.hasAutoHighlights

        // Identify the parent for the reel's FK and the existing-reel lookup.
        // Exactly one of (gameID, practiceID) is set for a given reel.
        let parentGameID: UUID?
        let parentPracticeID: UUID?
        switch parent {
        case .game(let g):     parentGameID = g.id;   parentPracticeID = nil
        case .practice(let p): parentGameID = nil;    parentPracticeID = p.id
        }

        let holeClips: [VideoClip] = parentClips.filter { $0.holeNumber == holeNumber }
        let clipsOnHole: [VideoClip] = holeClips.sorted { lhs, rhs in
            (lhs.createdAt ?? .distantPast) < (rhs.createdAt ?? .distantPast)
        }

        // Lookup existing reel for this (parent, hole) — alive or soft-deleted.
        // SwiftData #Predicate can't equate optional UUIDs against literals
        // cleanly across versions, so fetch flat and filter in memory.
        let existing: HighlightReel?
        do {
            let all = try modelContext.fetch(FetchDescriptor<HighlightReel>())
            existing = all.first { reel in
                reel.holeNumber == holeNumber &&
                    (parentGameID.map { reel.gameID == $0 } ?? false ||
                     parentPracticeID.map { reel.practiceID == $0 } ?? false)
            }
        } catch {
            ErrorHandlerService.shared.handle(
                error,
                context: "ScoreHoleSheet.upsertReelIfNeeded.fetch",
                showAlert: false
            )
            return
        }

        if canAutoHighlight && isBirdieOrBetter && !clipsOnHole.isEmpty {
            let clipIDStrings = clipsOnHole.map { $0.id.uuidString }
            let displayName = reelDisplayName(score: score, par: par)

            if let existing {
                // A3.1: refresh the existing reel only when something actually
                // changed — covers alive-edit (clip list grew) and undelete
                // (was par, back to birdie). A re-save with an identical clip
                // set/score/par must NOT bump version + needsSync, or every
                // idempotent re-score emits a redundant Firestore write. The
                // soft-deleted state is part of the diff so an undelete always
                // goes through. Compatible with syncHighlightReels' reconcile,
                // which assumes version only ever increases on a real edit.
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
                modelContext.insert(reel)
            }
        } else {
            // Demotion: soft-delete an alive reel. No-op if none existed or
            // it was already soft-deleted.
            if let existing, !existing.isDeletedRemotely {
                existing.isDeletedRemotely = true
                existing.version += 1
                existing.needsSync = true
            }
        }
    }

    /// "Hole-in-One" / "Albatross" / "Eagle" / "Birdie" — same label set as
    /// HoleScore.diffLabel but only the under-par buckets are reachable here
    /// because the caller already checked `isBirdieOrBetter`.
    private func reelDisplayName(score: Int, par: Int) -> String {
        if score == 1 { return "Hole-in-One" }
        let diff = score - par
        switch diff {
        case ...(-3): return "Albatross"
        case -2:      return "Eagle"
        default:      return "Birdie"
        }
    }
}
