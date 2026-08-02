//
//  AutoHighlightSettings.swift
//  PlayerPath
//
//  UserDefaults-backed settings controlling which play results are
//  automatically marked as highlights when a clip is saved.
//  Plus tier users can configure these rules; the defaults apply to everyone
//  so clips are tagged in the background even before a user upgrades.
//

import SwiftUI
import SwiftData
import Combine

@MainActor
final class AutoHighlightSettings: ObservableObject {
    static let shared = AutoHighlightSettings()

    private let defaults = UserDefaults.standard

    private enum Key: String {
        case defaultsSet              = "autoHighlight.defaultsSet"
        case enabled                  = "autoHighlight.enabled"
        case includeSingles           = "autoHighlight.singles"
        case includeDoubles           = "autoHighlight.doubles"
        case includeTriples           = "autoHighlight.triples"
        case includeHomeRuns          = "autoHighlight.homeRuns"
        case includePitcherStrikeouts = "autoHighlight.pitcherStrikeouts"
        case includePitcherGroundOuts = "autoHighlight.pitcherGroundOuts"
        case includePitcherFlyOuts    = "autoHighlight.pitcherFlyOuts"
    }

    @Published var enabled: Bool                  { didSet { save(.enabled, enabled) } }
    @Published var includeSingles: Bool           { didSet { save(.includeSingles, includeSingles) } }
    @Published var includeDoubles: Bool           { didSet { save(.includeDoubles, includeDoubles) } }
    @Published var includeTriples: Bool           { didSet { save(.includeTriples, includeTriples) } }
    @Published var includeHomeRuns: Bool          { didSet { save(.includeHomeRuns, includeHomeRuns) } }
    @Published var includePitcherStrikeouts: Bool { didSet { save(.includePitcherStrikeouts, includePitcherStrikeouts) } }
    @Published var includePitcherGroundOuts: Bool { didSet { save(.includePitcherGroundOuts, includePitcherGroundOuts) } }
    @Published var includePitcherFlyOuts: Bool    { didSet { save(.includePitcherFlyOuts, includePitcherFlyOuts) } }

    private init() {
        // Write defaults on first launch
        if !defaults.bool(forKey: Key.defaultsSet.rawValue) {
            defaults.set(true,  forKey: Key.enabled.rawValue)
            defaults.set(true,  forKey: Key.includeSingles.rawValue)
            defaults.set(true,  forKey: Key.includeDoubles.rawValue)
            defaults.set(true,  forKey: Key.includeTriples.rawValue)
            defaults.set(true,  forKey: Key.includeHomeRuns.rawValue)
            defaults.set(true,  forKey: Key.includePitcherStrikeouts.rawValue)
            defaults.set(true,  forKey: Key.includePitcherGroundOuts.rawValue)
            defaults.set(true,  forKey: Key.includePitcherFlyOuts.rawValue)
            defaults.set(true,  forKey: Key.defaultsSet.rawValue)
        }

        enabled                  = defaults.bool(forKey: Key.enabled.rawValue)
        includeSingles           = defaults.bool(forKey: Key.includeSingles.rawValue)
        includeDoubles           = defaults.bool(forKey: Key.includeDoubles.rawValue)
        includeTriples           = defaults.bool(forKey: Key.includeTriples.rawValue)
        includeHomeRuns          = defaults.bool(forKey: Key.includeHomeRuns.rawValue)
        includePitcherStrikeouts = defaults.bool(forKey: Key.includePitcherStrikeouts.rawValue)
        includePitcherGroundOuts = defaults.bool(forKey: Key.includePitcherGroundOuts.rawValue)
        includePitcherFlyOuts    = defaults.bool(forKey: Key.includePitcherFlyOuts.rawValue)
    }

    private func save(_ key: Key, _ value: Bool) {
        defaults.set(value, forKey: key.rawValue)
    }

    // MARK: - Rule Evaluation

    /// The toggle governing this (role, play type) pair, or nil when no rule covers it.
    ///
    /// The nil case is load-bearing: `scanLibrary` must never demote a clip whose play
    /// type isn't governed by a toggle (a hand-starred walk, sac fly, wild pitch, or any
    /// `.both`-role clip), because a star there can only have been deliberate. Collapsing
    /// nil into `false` — as this switch used to — is what let a rescan wipe manual curation.
    private func rule(for playType: PlayResultType, role: AthleteRole) -> Bool? {
        switch (role, playType) {
        case (.batter, .single):     return includeSingles
        case (.batter, .double):     return includeDoubles
        case (.batter, .triple):     return includeTriples
        case (.batter, .homeRun):    return includeHomeRuns
        case (.pitcher, .strikeout), (.pitcher, .pitchingStrikeout): return includePitcherStrikeouts
        case (.pitcher, .groundOut): return includePitcherGroundOuts
        case (.pitcher, .flyOut):    return includePitcherFlyOuts
        default:                     return nil
        }
    }

    /// Whether a given play result + role should be auto-tagged as a highlight at record time.
    func shouldAutoHighlight(playType: PlayResultType, role: AthleteRole) -> Bool {
        guard enabled else { return false }
        return rule(for: playType, role: role) ?? false
    }

    /// Pitcher-mode marker for an already-saved clip. Tiered the same way
    /// `PlayResultEditorView`'s `initialMode` is, so the two agree on what a clip's role was.
    ///
    /// 1. `pitchType` is authoritative: it's set for EVERY pitcher-mode clip
    ///    (PlayResultOverlayView's `parsedPitchType` returns a value whenever
    ///    `recordingMode == .pitcher`), whereas `pitchSpeed` only lands when the user typed
    ///    a radar reading. Inferring from speed alone mislabeled every gun-less pitcher clip
    ///    as a batter, so a rescan demoted the very strikeouts the save path had just
    ///    auto-starred using the explicit role.
    /// 2. `pitchSpeed` covers clips saved before `pitchType` existed.
    /// 3. A pitcher-side play type covers the rest of those legacy clips.
    ///    `isPitchingResult` is `rawValue >= 10` — all unambiguously pitcher-perspective
    ///    (a batter's HBP is the separate `.batterHitByPitch`), so this can't mislabel a
    ///    batter. It does NOT catch a pitcher's induced groundout/flyout, which reuse the
    ///    batting cases; nothing distinguishes those on a legacy clip, and inferring
    ///    `.batter` there is the safe answer — those pairs aren't governed by any rule,
    ///    so the scan skips them rather than demoting.
    private static func inferredRole(for clip: VideoClip) -> AthleteRole {
        if clip.pitchType != nil || clip.pitchSpeed != nil { return .pitcher }
        if clip.playResult?.type.isPitchingResult == true { return .pitcher }
        return .batter
    }

    // MARK: - Library Scan

    /// Retroactively applies the current rules to the given athlete's clips.
    /// Returns the number of clips whose `isHighlight` flag was changed.
    ///
    /// Scope is the *governed set*: a clip is only touched when its own (role, play type)
    /// pair is one the toggles actually describe. Everything else — untagged clips, golf,
    /// and play types no rule covers — is left exactly as the user left it. That boundary
    /// is what reconciles this with the promote-only rule the rest of the app follows
    /// (ClipPersistenceService / PlayResultEditorView both `||=` rather than assign,
    /// because nothing distinguishes an auto-set `true` from a deliberate star). Within
    /// the governed set an assignment is safe and expected: unchecking "Singles" and
    /// scanning has to actually clear singles or the toggle means nothing.
    @MainActor
    @discardableResult
    func scanLibrary(for athlete: Athlete, context: ModelContext) throws -> Int {
        // Auto-highlight off means every rule evaluates false; scanning in that state
        // would mass-unstar the whole governed set. Treat it as a no-op instead.
        guard enabled else { return 0 }
        guard let clips = athlete.videoClips else { return 0 }
        var changed = 0
        var newlyHighlighted: [VideoClip] = []
        for clip in clips {
            // No play result → no rule to evaluate. These used to be blanket-unstarred,
            // which silently destroyed hand-starred bulk imports (which land untagged)
            // and drill footage — the same failure the golf guard below was added for.
            guard let playResult = clip.playResult else { continue }
            // Defensive: golf clips carry `club`, never `playResult`, so the guard above
            // already exempts them. Kept so the exemption survives if that ever changes.
            if Self.clipIsGolf(clip) { continue }
            // No toggle governs this play type (walk, HBP, sac fly, `.both` role...) —
            // a star here can only be deliberate, so leave the user's curation alone.
            guard let shouldTag = rule(for: playResult.type, role: Self.inferredRole(for: clip)) else { continue }
            if clip.isHighlight != shouldTag {
                clip.isHighlight = shouldTag
                clip.needsSync = true
                changed += 1
                if shouldTag { newlyHighlighted.append(clip) }
            }
        }
        if changed > 0 {
            try context.save()
            // Clips this scan flipped on may have been skipped by the save-time auto-upload
            // gate (e.g. "Highlights Only"); re-run it so their binaries upload now.
            for clip in newlyHighlighted {
                UploadQueueManager.shared.reevaluateAutoUploadAfterHighlightChange(clip, context: context)
            }
        }
        return changed
    }

    /// True when a clip belongs to golf — by club tag or by golf-season
    /// context. Used to exempt golf clips from the baseball rescan rules.
    private static func clipIsGolf(_ clip: VideoClip) -> Bool {
        if clip.club != nil { return true }
        if clip.game?.season?.sport == .golf { return true }
        if clip.practice?.season?.sport == .golf { return true }
        if clip.season?.sport == .golf { return true }
        return false
    }
}
