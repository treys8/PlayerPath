//
//  Athlete.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import Foundation
import SwiftData
import os

enum AthleteRole: String, Codable, CaseIterable {
    case batter
    case pitcher
    case both

    var displayName: String {
        switch self {
        case .batter: return "Batter"
        case .pitcher: return "Pitcher"
        case .both: return "Both"
        }
    }
}

enum Sport: String, Codable, CaseIterable {
    case baseball
    case softball
    case golf

    var displayName: String {
        switch self {
        case .baseball: return "Baseball"
        case .softball: return "Softball"
        case .golf:     return "Golf"
        }
    }

    var icon: String {
        switch self {
        case .baseball: return "figure.baseball"
        case .softball: return "figure.softball"
        case .golf:     return "figure.golf"
        }
    }
}

@Model
final class Athlete {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date?
    var user: User?
    var primaryRole: AthleteRole = AthleteRole.batter
    /// Primary sport for this athlete. Drives the athlete card icon, default
    /// sport for new seasons, and sport attribution for seasonless legacy
    /// content. Kept in sync with the active season by `Season.activate()`,
    /// so a sport switch flips this automatically. Source of truth for a
    /// given game's sport remains `game.season?.sport` — an athlete may have
    /// seasons in multiple sports.
    ///
    /// Optional because athletes created before SchemaV21 have NULL in storage.
    /// Reading a non-Optional Sport from NULL trips SwiftData's KVC cast and
    /// hangs `modelContext.save()`. Readers must fall back to `?? .baseball`.
    var sport: Sport? = Sport.baseball
    @Relationship(inverse: \Season.athlete) var seasons: [Season]?
    @Relationship(inverse: \Game.athlete) var games: [Game]?
    @Relationship(inverse: \GolfTournament.athlete) var golfTournaments: [GolfTournament]?
    @Relationship(inverse: \Practice.athlete) var practices: [Practice]?
    @Relationship(inverse: \VideoClip.athlete) var videoClips: [VideoClip]?
    @Relationship(inverse: \AthleteStatistics.athlete) var statistics: AthleteStatistics?
    @Relationship(inverse: \Coach.athlete) var coaches: [Coach]?
    @Relationship(inverse: \Photo.athlete) var photos: [Photo]?

    // MARK: - Firestore Sync Metadata
    var firestoreId: String?        // Maps to Firestore document ID
    var lastSyncDate: Date?         // Last successful sync timestamp
    var needsSync: Bool = false     // Dirty flag - needs upload to Firestore
    var isDeletedRemotely: Bool = false  // Soft delete from another device
    var version: Int = 0            // Version number for conflict resolution

    /// When false, new clips save without the play-result tagging prompt and the
    /// Stats tab shows a disabled-tracking banner. Existing tagged clips remain
    /// and their stats stay visible. Defaults to true so existing athletes keep
    /// their current behavior after migration.
    var trackStatsEnabled: Bool = true

    /// Links sport-variant profiles for the same human (e.g. Zain-Baseball
    /// and Zain-Golf). Athletes sharing a `personGroupID` count as ONE slot
    /// against the user's subscription tier. Nil for athletes created before
    /// the spinoff feature or for solo profiles — slot dedup falls back to
    /// `id`, so nil-grouped athletes behave like singletons.
    var personGroupID: UUID?

    /// Points to one of this athlete's `Photo`s chosen as the headshot/avatar
    /// (SchemaV33). Reuses the photo sync/storage pipeline — only this pointer
    /// syncs on the athlete; the image rides the normal Photo path, so on another
    /// device the id resolves to the already-synced Photo. nil = no headshot
    /// (fall back to initials / the account photo). Feeds the recruiting profile's
    /// headshot at publish time.
    var headshotPhotoId: UUID?

    /// Recruiting-profile bio, stored as a JSON-encoded `RecruitingInfo` blob
    /// (mirrors `Game.scorecardData`). Read/write via the `recruiting` accessor
    /// (SchemaV35). One synced field instead of ~20 columns — see `RecruitingInfo.swift`.
    /// Per-field opt-in PII (GPA, contact) is governed by booleans inside the blob;
    /// nothing here is public until the Phase 2 publish flow ships.
    var recruitingProfileJSON: String?

    /// The currently active season for this athlete (only one can be active at a time)
    var activeSeason: Season? {
        seasons?.first(where: { $0.isActive })
    }

    /// All archived (completed) seasons, sorted by start date descending
    var archivedSeasons: [Season] {
        (seasons ?? [])
            .filter { !$0.isActive }
            .sorted { ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast) }
    }

    /// Athlete sport as `Season.SportType`. Bridges the two enums (`Sport`
    /// stores lowercase raw values, `SportType` stores capitalized) so callers
    /// don't repeat the conversion.
    var sportType: Season.SportType {
        Season.SportType(rawValue: (sport ?? .baseball).rawValue.capitalized) ?? .baseball
    }

    /// Distinct sports already covered by this person's linked profiles (same
    /// `personGroupID`, falling back to `id` for ungrouped singletons). Each
    /// profile is one sport, so multi-sport people are modeled as spinoff
    /// profiles — this is the canonical "what sports does this person play" set.
    var personGroupSports: Set<Season.SportType> {
        let groupID = personGroupID ?? id
        return Set((user?.athletes ?? [])
            .filter { ($0.personGroupID ?? $0.id) == groupID }
            .map(\.sportType))
    }

    /// True while the person's group is still missing at least one supported
    /// sport — gates the "Add a sport" CTA so it hides once every sport has a
    /// profile. Also the natural per-person cap on spinoff profiles.
    var canAddSportProfile: Bool {
        personGroupSports.count < Season.SportType.allCases.count
    }

    /// `"Jordan Smith"`, or `"Jordan Smith · Golf"` once this person has more
    /// than one linked profile.
    ///
    /// Same `siblings > 1` rule as `PPAthleteSwitcher.rowTitle`, so a
    /// single-sport athlete still reads as just their name. Factored out here
    /// because recruiting is where the ambiguity actually costs something: a
    /// dual-sport person is two rows with the SAME name, and each row carries its
    /// own bio, headshot, consent stamp, share link and published page. A screen
    /// that says only "Jordan Smith" gives no way to tell which of the two is
    /// about to go public — or which one a live link belongs to.
    var nameWithSportIfShared: String {
        let groupID = personGroupID ?? id
        let siblings = (user?.athletes ?? [])
            .filter { ($0.personGroupID ?? $0.id) == groupID }
            .count
        return siblings > 1 ? "\(name) · \((sport ?? .baseball).displayName)" : name
    }

    /// True when this single row tracks seasons in 2+ distinct sports — a legacy
    /// "Add a sport" profile that predates the spinoff model. Such a row can't run
    /// overlapping seasons and flips `sport` on every switch; the split tool migrates
    /// each non-primary sport onto its own `personGroupID`-linked profile. Row-local
    /// by design: a real spinoff is always one sport, so any 2-sport row is legacy
    /// regardless of how many siblings share its group. See `SportProfileSplitService`.
    var isLegacySplittable: Bool {
        Set((seasons ?? []).map { $0.sport ?? .baseball }).count >= 2
    }

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
    }

    // MARK: - Deep Deletion

    /// Properly delete athlete with all associated files and data.
    /// Use this instead of modelContext.delete(athlete) to avoid orphaning children.
    @MainActor func delete(in context: ModelContext) {
        // Cancel any pending uploads for this athlete before deleting clips
        let athleteId = id
        Task { @MainActor in
            UploadQueueManager.shared.cancelUploads(forAthleteId: athleteId)
        }

        // Best-effort: remove the recruiting headshot object from Storage so it
        // doesn't orphan (keyed by athleteId, same as upload). Idempotent. There
        // is NO server-side sweep for recruiting_headshots/ (the daily cleanup CF
        // only covers the videos collection), so this delete + the editor's
        // Remove button are the only reclaim paths. The owner segment is resolved
        // inside VideoCloudManager from the signed-in account (the cached
        // firebaseAuthUid goes along only as a fallback), which keeps FirebaseAuth
        // out of this model file and matches the path the upload wrote under.
        if recruiting.headshotCloudURL != nil {
            let ownerUID = user?.firebaseAuthUid
            Task { @MainActor in
                try? await VideoCloudManager.shared.deleteRecruitingHeadshot(athleteId: athleteId, ownerUID: ownerUID)
            }
        }

        // Best-effort: kill the published recruiting profile. This one is urgent
        // rather than merely tidy — the doc backs a PUBLIC web page, so leaving it
        // behind means a deleted athlete's photo and film stay live on the
        // internet at a URL that's already been mailed to college coaches.
        // Belt-and-braces: performDeleteAthlete retries this, and the
        // cleanupUserDataOnDelete CF sweeps it on account deletion.
        Task { @MainActor in
            try? await RecruitingProfileService.shared.deleteProfileDoc(athleteId: athleteId)
        }

        // Track which clips are owned by a game or practice so we don't double-delete
        var deletedClipIDs = Set<UUID>()

        // v6.1 PR2: hard-delete this athlete's HighlightReels locally before
        // games/practices go away. Reels carry only a denormalized athleteID
        // FK, so a single in-memory filter is enough — they don't cascade
        // via SwiftData relationships. Firestore cleanup is best-effort and
        // backstopped by the daily cleanup function.
        do {
            let allReels = try context.fetch(FetchDescriptor<HighlightReel>())
            for reel in allReels where reel.athleteID == athleteId {
                context.delete(reel)
            }
        } catch {
            modelsLog.error("Failed to fetch HighlightReels for athlete-delete cascade: \(error.localizedDescription)")
        }

        // Delete all games (and their video clips, stats)
        for game in games ?? [] {
            for clip in game.videoClips ?? [] {
                clip.delete(in: context, cleanupReels: false)
                deletedClipIDs.insert(clip.id)
            }
            if let gameStats = game.gameStats {
                context.delete(gameStats)
            }
            context.delete(game)
        }

        // Delete all practices (and their video clips, notes)
        for practice in practices ?? [] {
            for clip in practice.videoClips ?? [] where !deletedClipIDs.contains(clip.id) {
                clip.delete(in: context, cleanupReels: false)
                deletedClipIDs.insert(clip.id)
            }
            for note in practice.notes ?? [] {
                context.delete(note)
            }
            context.delete(practice)
        }

        // Delete remaining standalone video clips (not attached to a game or practice)
        for clip in videoClips ?? [] where !deletedClipIDs.contains(clip.id) {
            clip.delete(in: context, cleanupReels: false)
        }

        // Delete all photos (handles local files and cloud)
        for photo in photos ?? [] {
            photo.delete(in: context)
        }

        // Delete golf tournaments (SchemaV27). Rounds are deleted by the games
        // loop above, so a plain delete is enough here — no need to unlink.
        for tournament in golfTournaments ?? [] {
            context.delete(tournament)
        }

        // Delete seasons and their statistics
        for season in seasons ?? [] {
            if let seasonStats = season.seasonStatistics {
                context.delete(seasonStats)
            }
            context.delete(season)
        }

        // Delete coaches
        for coach in coaches ?? [] {
            context.delete(coach)
        }

        // Delete athlete statistics
        if let stats = statistics {
            context.delete(stats)
        }

        context.delete(self)
    }

    // MARK: - Firestore Conversion
    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "id": id.uuidString,
            "name": name,
            "userId": user?.id.uuidString ?? "",
            "primaryRole": primaryRole.rawValue,
            "sport": (sport ?? .baseball).rawValue,
            "trackStatsEnabled": trackStatsEnabled,
            "personGroupID": personGroupID?.uuidString ?? NSNull(),
            "headshotPhotoId": headshotPhotoId?.uuidString ?? NSNull(),
            "createdAt": createdAt ?? Date(),
            "updatedAt": Date(),
            "version": version,
            "isDeleted": false
        ]
        // Recruiting bio blob (SchemaV35). Optional — omitted when never set.
        if let recruitingProfileJSON = recruitingProfileJSON { data["recruitingProfileJSON"] = recruitingProfileJSON }
        return data
    }
}
