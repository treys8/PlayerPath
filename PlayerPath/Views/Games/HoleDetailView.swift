//
//  HoleDetailView.swift
//  PlayerPath
//
//  Per-hole clip review for a golf round. Groups one hole's clips behind the
//  round's hole list so a 50-clip round stays browsable hole-by-hole instead of
//  collapsing into one flat dump. Shows the hole's score (if entered), its
//  clips, and a Plus-gated "Generate Highlight Reel" scoped to just this hole.
//
//  Serves both a competition/standalone round (`Game`) and a golf practice
//  round (`Practice`) via `GolfRoundRef`. Reached from GameDetailView and
//  PracticeDetailView. `holeNumber == nil` is the "Unassigned" bucket — clips
//  recorded before the hole was scored or imported without a hole. (The batch
//  hole/club editor lands here in a later phase; for now the bucket is
//  review-only.)
//

import SwiftUI
import SwiftData

/// The golf round a hole belongs to — a tournament/standalone round (`Game`) or
/// a practice round (`Practice`). Lets HoleDetailView serve both without
/// duplicating the per-hole view.
enum GolfRoundRef {
    case game(Game)
    case practice(Practice)

    var videoClips: [VideoClip] {
        switch self {
        case .game(let g):     return g.videoClips ?? []
        case .practice(let p): return p.videoClips ?? []
        }
    }

    var holeScores: [HoleScore] {
        switch self {
        case .game(let g):     return g.holeScores ?? []
        case .practice(let p): return p.holeScores ?? []
        }
    }

    /// Identity for the reel cache scope — distinct per round.
    var scopeID: UUID {
        switch self {
        case .game(let g):     return g.id
        case .practice(let p): return p.id
        }
    }

    /// Label base for the reel title — course/opponent for a game, course (or
    /// "Practice Round") for a practice.
    var titleBase: String {
        switch self {
        case .game(let g):
            return g.opponent
        case .practice(let p):
            let course = p.course?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (course?.isEmpty == false) ? course! : "Practice Round"
        }
    }

    /// Hole count for this round — bounds the batch hole editor's picker.
    var holeCount: Int {
        switch self {
        case .game(let g):     return g.holes ?? 18
        case .practice(let p): return p.holes ?? 18
        }
    }
}

struct HoleDetailView: View {
    let round: GolfRoundRef
    /// The hole this view scopes to. `nil` = the Unassigned bucket.
    let holeNumber: Int?

    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @State private var showingReel = false
    @State private var showingReelPaywall = false
    @State private var showingBatchEditor = false

    /// True when this is the Unassigned bucket (clips with no hole) — where the
    /// batch hole editor is offered.
    private var isUnassignedBucket: Bool { holeNumber == nil }

    /// Clips on this hole (or unassigned), newest first for the list.
    private var clips: [VideoClip] {
        round.videoClips
            .filter { $0.holeNumber == holeNumber }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    /// Clips in chronological (playback) order for the reel. A hole reel uses
    /// ALL of the hole's clips — matching the auto-reel built on a birdie — not
    /// only starred ones, since a single hole rarely has two-plus stars.
    private var reelClips: [VideoClip] {
        clips.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    /// A reel needs at least two clips — one clip is just a clip.
    private var reelEligible: Bool { reelClips.count >= 2 }

    /// The score row for this hole, if one was entered. Nil for the Unassigned
    /// bucket and for holes filmed but never scored.
    private var holeScore: HoleScore? {
        guard let holeNumber else { return nil }
        return round.holeScores.first { $0.holeNumber == holeNumber }
    }

    private var navTitle: String {
        guard let holeNumber else { return "Unassigned" }
        return "Hole \(holeNumber)"
    }

    private var reelTitle: String {
        guard let holeNumber else { return round.titleBase }
        return "\(round.titleBase) · Hole \(holeNumber)"
    }

    /// Cache scope distinct from the round-level reel so a hole reel and the
    /// full-round reel don't collide in StitchedReelCache.
    private var reelScopeKey: String {
        "hole_\(round.scopeID.uuidString)_\(holeNumber.map(String.init) ?? "none")"
    }

    var body: some View {
        List {
            if let score = holeScore {
                Section(header: Text("Score").smallCapsLabel()) {
                    HStack {
                        Text("Par \(score.par)")
                            .font(.headingMedium)
                        Spacer()
                        Text("\(score.score)")
                            .font(.headingMedium)
                            .monospacedDigit()
                            .foregroundColor(.parRelative(score.diff))
                        Text(score.diffLabel)
                            .font(.labelSmall)
                            .foregroundColor(.secondary)
                    }
                    if let putts = score.putts {
                        HStack {
                            Text("Putts")
                                .font(.headingMedium)
                            Spacer()
                            Text("\(putts)")
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section(header: Text("Clips (\(clips.count))").smallCapsLabel()) {
                if clips.isEmpty {
                    Text(isUnassignedBucket ? "No unassigned clips." : "No clips on this hole.")
                        .font(.bodyMedium)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    if isUnassignedBucket {
                        Button(action: { showingBatchEditor = true }) {
                            Label("Assign hole to clips", systemImage: "flag")
                        }
                        .labelStyle(ActionRowLabelStyle())
                    }
                    if reelEligible {
                        Button(action: { generateReelTapped() }) {
                            Label("Generate Highlight Reel", systemImage: "film.stack")
                        }
                        .labelStyle(ActionRowLabelStyle())
                    }
                    ForEach(clips) { clip in
                        VideoClipRow(clip: clip)
                    }
                }
            }
        }
        .ppDetailBackground()
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showingReel) {
            GenerateReelView(clips: reelClips, scopeKey: reelScopeKey, title: reelTitle)
        }
        .sheet(isPresented: $showingReelPaywall) {
            if let user = authManager.localUser {
                ImprovedPaywallView(user: user, requiredTier: .plus)
            }
        }
        .sheet(isPresented: $showingBatchEditor) {
            BatchClipTagEditor(clips: clips, mode: .hole(maxHoles: round.holeCount))
        }
    }

    /// Plus-gated: open the generator, or route free users to the paywall.
    /// Mirrors GameDetailView.generateReelTapped so both surfaces gate alike.
    private func generateReelTapped() {
        Haptics.light()
        if SubscriptionGate.effectiveAthleteTier.hasAutoHighlights {
            showingReel = true
        } else {
            showingReelPaywall = true
        }
    }
}
