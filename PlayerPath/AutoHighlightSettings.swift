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
            defaults.set(false, forKey: Key.includePitcherGroundOuts.rawValue)
            defaults.set(false, forKey: Key.includePitcherFlyOuts.rawValue)
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

    /// Whether a given play result + role should be auto-tagged as a highlight at record time.
    func shouldAutoHighlight(playType: PlayResultType, role: AthleteRole) -> Bool {
        guard enabled else { return false }
        switch (role, playType) {
        case (.batter, .single):     return includeSingles
        case (.batter, .double):     return includeDoubles
        case (.batter, .triple):     return includeTriples
        case (.batter, .homeRun):    return includeHomeRuns
        case (.pitcher, .strikeout): return includePitcherStrikeouts
        case (.pitcher, .groundOut): return includePitcherGroundOuts
        case (.pitcher, .flyOut):    return includePitcherFlyOuts
        default:                     return false
        }
    }

    // MARK: - Library Scan

    /// Retroactively applies current rules to every clip for the given athlete.
    /// Returns the number of clips whose `isHighlight` flag was changed.
    @MainActor
    @discardableResult
    func scanLibrary(for athlete: Athlete, context: ModelContext) throws -> Int {
        guard let clips = athlete.videoClips else { return 0 }
        var changed = 0
        for clip in clips {
            guard let playResult = clip.playResult else {
                // No play result — unmark any existing highlight flag
                if clip.isHighlight { clip.isHighlight = false; clip.needsSync = true; changed += 1 }
                continue
            }
            // Infer role: clips with a recorded pitch speed were in pitcher mode
            let inferredRole: AthleteRole = clip.pitchSpeed != nil ? .pitcher : .batter
            let shouldTag = shouldAutoHighlight(playType: playResult.type, role: inferredRole)
            if clip.isHighlight != shouldTag {
                clip.isHighlight = shouldTag
                clip.needsSync = true
                changed += 1
            }
        }
        if changed > 0 { try context.save() }
        return changed
    }
}
