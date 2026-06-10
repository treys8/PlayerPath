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

    /// Re-entrancy guard. A rapid double-tap of Save would otherwise re-enter
    /// before dismiss propagates and insert a second HoleScore (and reel) for
    /// the same hole, corrupting totals.
    @State private var isSaving: Bool = false

    /// Opt-in detailed tracking — reveals fairway / green / penalty inputs.
    @AppStorage(GolfPrefs.trackDetailedStats) private var trackDetailed = false
    @State private var fairwayHit: Bool? = nil
    @State private var greenInRegulation: Bool? = nil
    @State private var penalties: Int? = nil

    private var penaltyBinding: Binding<Int> {
        Binding(get: { penalties ?? 0 }, set: { penalties = $0 > 0 ? $0 : nil })
    }

    // MARK: - Parent accessors

    private var parentHoles: [HoleScore] {
        switch parent {
        case .game(let g):     return g.holeScores ?? []
        case .practice(let p): return p.holeScores ?? []
        }
    }

    /// Bridges the sheet's private `Parent` to the shared `GolfRoundRef` the
    /// writer and scorecard operate on, so all three share one save path.
    private var roundRef: GolfRoundRef {
        switch parent {
        case .game(let g):     return .game(g)
        case .practice(let p): return .practice(p)
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
                            ForEach(3...6, id: \.self) { Text("\($0)").tag($0) }
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

                    // Detailed — fairway / green / penalties, opt-in (SchemaV29).
                    if trackDetailed {
                        VStack(alignment: .leading, spacing: .spacingSmall) {
                            if par >= 4 {
                                HitMissControl(label: "Fairway", systemImage: "arrow.up.forward", value: $fairwayHit)
                            }
                            HitMissControl(label: "Green in Reg.", systemImage: "flag.fill", value: $greenInRegulation)
                            Stepper(value: penaltyBinding, in: 0...10) {
                                HStack {
                                    Text("Penalties").font(.bodyLarge)
                                    Spacer()
                                    Text("\(penalties ?? 0)")
                                        .monospacedDigit()
                                        .foregroundColor(.secondary)
                                }
                            }
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
            par = existing.par
            score = existing.score
            // Already a real score — par tweaks shouldn't drag it along.
            scoreManuallySet = true
            if let p = existing.putts {
                putts = p
                includePutts = true
            }
            fairwayHit = existing.fairwayHit
            greenInRegulation = existing.greenInRegulation
            penalties = existing.penalties
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
        GolfScoreWriter.priorRoundPar(forHole: hole, in: roundRef)
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true

        // Putts can never exceed strokes; clamp defensively in case state was
        // seeded above the score before the grid re-rendered. Preserve the
        // original nil-when-unset semantics (don't coerce a missing value to 0).
        let savedPutts: Int? = includePutts ? putts.map { min($0, score) } : nil

        let input = GolfScoreWriter.HoleInput(
            holeNumber: holeNumber,
            par: par,
            score: score,
            putts: savedPutts,
            fairwayHit: par >= 4 ? fairwayHit : nil,
            greenInRegulation: greenInRegulation,
            penalties: penalties
        )

        // One shared write path (also used by GolfScorecardView): upsert the
        // hole, mirror the running total onto Game.totalScore, and create/demote
        // the birdie auto-highlight reel — all staged into the single save below.
        GolfScoreWriter.upsertHole(input, in: roundRef, context: modelContext)
        GolfScoreWriter.mirrorTotalScore(in: roundRef, justWrote: [input])
        GolfScoreWriter.upsertReelIfNeeded(holeNumber: holeNumber, par: par, score: score, in: roundRef, context: modelContext)

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

}
