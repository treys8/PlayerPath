//
//  VideoClipFilter.swift
//  PlayerPath
//
//  Combinable, multi-dimensional filter for the Videos-tab clip grid. Replaces
//  the old single-select `VideoLibraryFilter`. Every dimension ANDs together
//  (matches Photos/Fitness filter behavior — predictable). Season scoping and
//  free-text search are applied separately by `VideoClipsViewModel`; this struct
//  owns the clip-attribute predicates and their human labels.
//

import Foundation

struct VideoClipFilter: Equatable {
    var highlightsOnly = false
    var coachFeedbackOnly = false
    var untaggedOnly = false
    var result: ResultFilter = .any   // baseball/softball
    var club: ClubFilter = .any        // golf
    var opponent: String? = nil

    /// Play-result dimension. `.batting`/`.pitching` preserve the retired
    /// Batter/Pitcher pills; `.hits`/`.onBase`/`.outs` are cross-cutting groups;
    /// `.specific` pins one exact result ("show me all my home runs").
    enum ResultFilter: Equatable {
        case any, batting, pitching, hits, onBase, outs
        case specific(PlayResultType)

        /// Short label for the chip and the filtered-empty summary. nil = inactive.
        var label: String? {
            switch self {
            case .any:             return nil
            case .batting:         return "Batting"
            case .pitching:        return "Pitching"
            case .hits:            return "Hits"
            case .onBase:          return "On Base"
            case .outs:            return "Outs"
            case .specific(let t): return t.displayName
            }
        }
    }

    /// Golf club dimension — by category (Woods/Irons/Wedges/Putter) or a
    /// specific club.
    enum ClubFilter: Equatable {
        case any
        case category(Club.Category)
        case specific(Club)

        var label: String? {
            switch self {
            case .any:               return nil
            case .category(let c):   return c.displayName.capitalized
            case .specific(let cl):  return cl.displayName
            }
        }
    }

    var isActive: Bool {
        highlightsOnly || coachFeedbackOnly || untaggedOnly
            || result != .any || club != .any || opponent != nil
    }

    /// Opponent accessor mirrors `VideoClipsViewModel` search: prefer the live
    /// game relationship, fall back to the denormalized copy (survives a clip
    /// whose game couldn't be re-linked after cross-device sync). Trimmed so it
    /// matches the same trimming `updateAvailableOpponents()` applies when it
    /// builds the menu — otherwise a trailing space would make a clip unmatchable.
    private func opponentName(_ clip: VideoClip) -> String? {
        let raw = (clip.game?.opponent ?? clip.gameOpponent)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty == false) ? raw : nil
    }

    /// A clip carries coach feedback if the coach drew/annotated it OR left a
    /// plain note. Notes are the primary feedback channel in this app, so an
    /// annotation-count-only check would miss note-only feedback.
    private func hasCoachFeedback(_ clip: VideoClip) -> Bool {
        if clip.annotationCount > 0 || clip.drawingCount > 0 { return true }
        return clip.coachNoteSnapshot?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    func matches(_ clip: VideoClip) -> Bool {
        if highlightsOnly, !clip.isHighlight { return false }
        if coachFeedbackOnly, !hasCoachFeedback(clip) { return false }
        if untaggedOnly, clip.isTagged { return false }
        if let opponent, opponentName(clip) != opponent { return false }

        switch result {
        case .any:
            break
        case .batting:
            guard clip.playResult?.type.isBattingResult == true else { return false }
        case .pitching:
            guard clip.playResult?.type.isPitchingResult == true else { return false }
        case .hits:
            guard clip.playResult?.type.isHit == true else { return false }
        case .onBase:
            guard let t = clip.playResult?.type, t.isHit || t == .walk || t == .batterHitByPitch else { return false }
        case .outs:
            guard let t = clip.playResult?.type, t == .strikeout || t == .groundOut || t == .flyOut else { return false }
        case .specific(let t):
            guard clip.playResult?.type == t else { return false }
        }

        switch club {
        case .any:
            break
        case .category(let cat):
            guard clip.club?.category == cat else { return false }
        case .specific(let cl):
            guard clip.club == cl else { return false }
        }

        return true
    }

    /// Comma-joined description of the active dimensions, for `FilteredEmptyStateView`.
    var summary: String {
        var parts: [String] = []
        if highlightsOnly { parts.append("Highlights") }
        if coachFeedbackOnly { parts.append("Coach feedback") }
        if untaggedOnly { parts.append("Untagged") }
        if let label = result.label { parts.append(label) }
        if let label = club.label { parts.append(label) }
        if let opponent { parts.append("vs \(opponent)") }
        return parts.joined(separator: ", ")
    }
}
