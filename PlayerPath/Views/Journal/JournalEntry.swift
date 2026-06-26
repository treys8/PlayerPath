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
    case photoGroup([Photo])    // 2+ standalone photos from the same calendar day

    var id: String {
        switch self {
        case .game(let g):     return "game-\(g.id.uuidString)"
        case .practice(let p): return "practice-\(p.id.uuidString)"
        case .clip(let c):     return "clip-\(c.id.uuidString)"
        case .photo(let p):    return "photo-\(p.id.uuidString)"
        case .photoGroup(let photos):
            // Day-keyed (not membership-keyed) so adding/removing a photo to the
            // same day keeps the row's SwiftUI identity stable. Every photo in the
            // group shares a calendar day, so any member yields the same key.
            let day = photos.first?.createdAt ?? .distantPast
            return "photogroup-\(Int(Calendar.current.startOfDay(for: day).timeIntervalSince1970))"
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
        case .photoGroup(let photos):
            // Newest photo of the day anchors the group's feed position.
            return photos.map { $0.createdAt ?? .distantPast }.max() ?? .distantPast
        }
    }

    var sport: Season.SportType? {
        switch self {
        case .game(let g):     return g.season?.sport
        case .practice(let p): return p.season?.sport
        case .clip(let c):     return c.season?.sport
        case .photo(let p):    return p.season?.sport
        // Orphan photos rarely carry a season; the first that does sets the
        // group's sport (nil passes the feed's seasonless sport gate through).
        case .photoGroup(let photos): return photos.compactMap { $0.season?.sport }.first
        }
    }

    var isGolf: Bool { sport == .golf }

    /// The backing game's id for a `.game` entry, else nil. Lets the feed resolve
    /// this row's milestone from a pre-built `[UUID: Milestone]` index instead of
    /// scanning the milestone array per row.
    var gameID: UUID? {
        if case .game(let g) = self { return g.id }
        return nil
    }

    // MARK: - Media

    private var clips: [VideoClip] {
        switch self {
        case .game(let g):     return g.videoClips ?? []
        case .practice(let p): return p.videoClips ?? []
        case .clip(let c):     return [c]
        case .photo:           return []
        case .photoGroup:      return []
        }
    }

    private var photos: [Photo] {
        switch self {
        case .game(let g):           return g.photos ?? []
        case .practice(let p):       return p.photos ?? []
        case .clip:                  return []
        case .photo(let p):          return [p]
        case .photoGroup(let group): return group
        }
    }

    /// True when any contained clip is starred. Cross-cuts entry type, so it's
    /// used by the feed's Highlights filter (`JournalFilter.matches`) and the
    /// row's type tag — the only media accessor the row still reads off the
    /// entry directly; counts + representatives come from `mediaSummary`.
    var containsHighlight: Bool {
        clips.contains { $0.isHighlight }
    }

    // MARK: - Per-row media summary

    /// One-pass resolution of all the media a feed row needs (counts +
    /// representatives). Reading `clips`/`photos` faults each to-many
    /// relationship exactly once and derives every value from that single walk,
    /// instead of re-walking the relationship per derived value as the card
    /// scrolls into view (a CPU spike on clip/photo-heavy events). Representative
    /// clip prefers the first highlight in relationship order, else the newest;
    /// representative photo is the newest.
    struct MediaSummary {
        var clipCount: Int
        var photoCount: Int
        var representativeClip: VideoClip?
        var representativePhoto: Photo?
    }

    var mediaSummary: MediaSummary {
        let clips = self.clips
        let photos = self.photos

        var newestClip: VideoClip?
        var highlightClip: VideoClip?
        for clip in clips {
            if highlightClip == nil, clip.isHighlight { highlightClip = clip }
            if newestClip == nil || (clip.createdAt ?? .distantPast) > (newestClip?.createdAt ?? .distantPast) {
                newestClip = clip
            }
        }

        let representativePhoto = photos.max { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }

        return MediaSummary(
            clipCount: clips.count,
            photoCount: photos.count,
            representativeClip: highlightClip ?? newestClip,
            representativePhoto: representativePhoto
        )
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
        case .photoGroup(let photos):
            // The count IS the headline for a day's set — the row suppresses the
            // redundant "N photos" counts footer so it isn't stated twice.
            return "\(photos.count) photos"
        }
    }

    /// Whether the headline carries real information worth a title line. A
    /// standalone photo with no caption has nothing to say — its image is the
    /// hero and the "Photo" type tag already names it — so the row drops the
    /// redundant literal "Photo". Every other entry (incl. a captioned photo and
    /// a group's "N photos") keeps its headline.
    var showsHeadline: Bool {
        if case .photo(let p) = self {
            let caption = p.caption?.trimmingCharacters(in: .whitespaces)
            return !(caption?.isEmpty ?? true)
        }
        return true
    }
}
