//
//  JournalEntry.swift
//  PlayerPath
//
//  Visual overhaul — the Journal feed's entry value type.
//  A unified, reverse-chron entry composed from existing models (Game,
//  Practice, or an orphaned VideoClip). Read-only: it derives everything from
//  data the user already enters. No new fields, no persistence.
//
//  Headlines here are the plain MATCHUP FALLBACK only; the milestone engine and
//  auto-headline rule (added later) layer richer titles on top.
//

import Foundation

enum JournalEntry: Identifiable {
    case game(Game)
    case practice(Practice)
    case clip(VideoClip)        // standalone clip (no game/practice parent)
    case photo(Photo)           // standalone photo (no game/practice parent)

    var id: String {
        switch self {
        case .game(let g):     return "game-\(g.id.uuidString)"
        case .practice(let p): return "practice-\(p.id.uuidString)"
        case .clip(let c):     return "clip-\(c.id.uuidString)"
        case .photo(let p):    return "photo-\(p.id.uuidString)"
        }
    }

    /// Sort/display date. Falls back through createdAt so an entry never sinks
    /// to the epoch just because a date is missing.
    var date: Date {
        switch self {
        case .game(let g):     return g.date ?? g.createdAt ?? .distantPast
        case .practice(let p): return p.date ?? p.createdAt ?? .distantPast
        case .clip(let c):     return c.createdAt ?? .distantPast
        case .photo(let p):    return p.createdAt ?? .distantPast
        }
    }

    var sport: Season.SportType? {
        switch self {
        case .game(let g):     return g.season?.sport
        case .practice(let p): return p.season?.sport
        case .clip(let c):     return c.season?.sport
        case .photo(let p):    return p.season?.sport
        }
    }

    var isGolf: Bool { sport == .golf }

    // MARK: - Media

    private var clips: [VideoClip] {
        switch self {
        case .game(let g):     return g.videoClips ?? []
        case .practice(let p): return p.videoClips ?? []
        case .clip(let c):     return [c]
        case .photo:           return []
        }
    }

    var clipCount: Int { clips.count }

    var photoCount: Int {
        switch self {
        case .game(let g):     return g.photos?.count ?? 0
        case .practice(let p): return p.photos?.count ?? 0
        case .clip:            return 0
        case .photo:           return 1
        }
    }

    /// The clip used for the entry's media tile — prefer a highlight, else the
    /// most recent clip. Split into steps to keep the type-checker fast.
    var representativeClip: VideoClip? {
        let all = clips
        if let highlight = all.first(where: { $0.isHighlight }) {
            return highlight
        }
        let sorted = all.sorted { lhs, rhs in
            (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
        }
        return sorted.first
    }

    var containsHighlight: Bool {
        clips.contains { $0.isHighlight }
    }

    // MARK: - Headline (matchup fallback)

    /// Plain fallback headline composed from data the user entered.
    var fallbackHeadline: String {
        switch self {
        case .game(let g):
            return g.opponent.isEmpty ? g.eventNoun : g.opponentLabel
        case .practice(let p):
            return PracticeType(rawValue: p.practiceType)?.displayName ?? "Practice"
        case .clip(let c):
            // Never headline the literal word "Highlight" — that's the type
            // tag's job. Prefer the play outcome ("Double"), then the note,
            // then a neutral noun.
            if let outcome = c.playResult?.type.displayName, !outcome.isEmpty {
                return outcome
            }
            if let note = c.note, !note.isEmpty {
                return note
            }
            return "Clip"
        case .photo(let p):
            // A captioned photo headlines with its caption; otherwise the plain
            // noun (the date rail + "Photo" tag already carry the context).
            if let caption = p.caption?.trimmingCharacters(in: .whitespaces), !caption.isEmpty {
                return caption
            }
            return "Photo"
        }
    }
}
