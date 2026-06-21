//
//  Models.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import Foundation
import SwiftData
import os

let modelsLog = Logger(subsystem: "com.playerpath.app", category: "Models")


/*
 Inverse relationships mapping for CloudKit/SwiftData:

 User.athletes <-> Athlete.user
 Athlete.seasons <-> Season.athlete
 Athlete.games <-> Game.athlete
 Athlete.practices <-> Practice.athlete
 Athlete.videoClips <-> VideoClip.athlete
 Athlete.statistics <-> AthleteStatistics.athlete (to-one)
 Athlete.coaches <-> Coach.athlete
 Athlete.photos <-> Photo.athlete

 Season.games <-> Game.season
 Season.practices <-> Practice.season
 Season.videoClips <-> VideoClip.season
 Season.seasonStatistics <-> AthleteStatistics (to-one)
 Season.photos <-> Photo.season

 Game.videoClips <-> VideoClip.game
 Game.photos <-> Photo.game
 Game.gameStats <-> GameStatistics.game (to-one)
 Game.season <-> Season.games

 Practice.videoClips <-> VideoClip.practice
 Practice.notes <-> PracticeNote.practice
 Practice.photos <-> Photo.practice
 Practice.season <-> Season.practices

 VideoClip.season <-> Season.videoClips
 PlayResult.videoClip <-> VideoClip.playResult (to-one)
*/

// MARK: - User and Athlete Models
@Model
final class User {
    var id: UUID = UUID()
    var username: String = ""
    var email: String = ""
    var role: String = "athlete" // "athlete" or "coach"
    var profileImagePath: String?
    var createdAt: Date?
    var subscriptionTier: String = "free"
    /// Firebase Auth UID — used as the Firestore document key for all user data
    var firebaseAuthUid: String?
    /// Running total of bytes stored in Firebase Storage (videos + photos).
    /// Updated after each successful upload/delete. Used to enforce tier storage limits.
    var cloudStorageUsedBytes: Int64 = 0

    /// Computed tier from stored string — not persisted by SwiftData
    var tier: SubscriptionTier {
        SubscriptionTier(rawValue: subscriptionTier) ?? .free
    }
    @Relationship(inverse: \Athlete.user) var athletes: [Athlete]?

    init(username: String, email: String, role: String = "athlete") {
        self.id = UUID()
        self.username = username
        self.email = email
        self.role = role
        self.createdAt = Date()
    }

    /// Subscription slots consumed against the tier's `athleteLimit`. Linked
    /// sport-variant profiles (same `personGroupID`) count as ONE slot;
    /// pre-V24 athletes (nil group) fall back to their `id` and behave like
    /// singletons. This is the canonical count for all tier-limit gates.
    var athleteSlotsUsed: Int {
        Set((athletes ?? []).map { $0.personGroupID ?? $0.id }).count
    }
}



// MARK: - Game Model
@Model
final class Game {
    var id: UUID = UUID()
    var date: Date?
    var opponent: String = ""
    var location: String?
    var notes: String?
    var isLive: Bool = false
    var isComplete: Bool = false
    var liveStartDate: Date? // Set when game becomes live; used for stale-game alerts
    var createdAt: Date?
    var year: Int? // Year for tracking when no season is active

    // MARK: - Golf-only fields (nil for baseball/softball)
    /// Number of holes played (9 or 18) for golf rounds.
    var holes: Int?
    /// Course par for golf rounds (e.g. 72).
    var par: Int?
    /// Persisted golf total. For per-hole-scored rounds this is a *mirror* of
    /// the live hole sum (kept current on every `ScoreHoleSheet` save); for
    /// quick-entry rounds it's typed directly. Readers should prefer
    /// `effectiveTotalScore`, which derives from `holeScores` when present and
    /// falls back to this scalar — so a round is never blank just because the
    /// per-hole rows haven't replicated to this device yet.
    var totalScore: Int?

    /// Parent multi-round tournament (SchemaV27), or nil for a standalone golf
    /// round. The inverse side is `GolfTournament.rounds`. Always nil for
    /// baseball/softball games.
    var tournament: GolfTournament?
    /// Ordering of this round within its tournament (1-based). Nil for
    /// standalone rounds and non-golf games.
    var roundNumber: Int?

    /// Per-round opt-in for shot-by-shot tracking (SchemaV30). When true, this
    /// round's holes are entered shot-by-shot (`ShotEntryView`) and the hole
    /// score / FIR / GIR / putts are derived from the shots. Defaults false so
    /// existing rounds keep the quick hole-at-a-time flow.
    var tracksShotByShot: Bool = false

    var athlete: Athlete?
    var season: Season?
    @Relationship(inverse: \VideoClip.game) var videoClips: [VideoClip]?
    @Relationship(inverse: \GameStatistics.game) var gameStats: GameStatistics?
    @Relationship(inverse: \Photo.game) var photos: [Photo]?
    /// Per-hole scoring rows for golf tournaments (SchemaV25). Nil for
    /// baseball/softball games. Entry happens via ScoreHoleSheet during a
    /// live round; sync is per-row in `users/{uid}/games/{gameId}/holes/{N}`.
    @Relationship(inverse: \HoleScore.game) var holeScores: [HoleScore]?

    // MARK: - Firestore Sync Metadata (Phase 2)

    /// Firestore document ID (maps to cloud storage)
    var firestoreId: String?

    /// Last successful sync timestamp
    var lastSyncDate: Date?

    /// Dirty flag - true when local changes need uploading
    var needsSync: Bool = false

    /// Soft delete flag - true when deleted on another device
    var isDeletedRemotely: Bool = false

    /// Version number for conflict resolution
    var version: Int = 0

    init(date: Date, opponent: String) {
        self.id = UUID()
        self.date = date
        self.opponent = opponent
        self.createdAt = Date()
        // Auto-set year from date
        let calendar = Calendar.current
        self.year = calendar.component(.year, from: date)
    }

    // MARK: - Golf derived scoring

    /// Sum of per-hole scores, or nil when no holes have been scored. The live
    /// source of truth for a per-hole-scored round.
    var holeScoreSum: Int? {
        let holes = holeScores ?? []
        return holes.isEmpty ? nil : holes.reduce(0) { $0 + $1.score }
    }

    /// Single read API for a round's total: the derived hole sum when scored
    /// per hole, otherwise the quick-entry scalar. Prefer this over reading
    /// `totalScore` directly so a device that has the per-hole rows always
    /// renders a correct total even if its `totalScore` scalar is stale.
    /// Use this for DISPLAY (it shows partial in-progress totals too).
    var effectiveTotalScore: Int? { holeScoreSum ?? totalScore }

    /// Sum of the pars of the holes actually scored, or nil when none are. The
    /// par counterpart to `holeScoreSum` — pair them so a round's to-par counts
    /// only holes that have been entered.
    var holeParSum: Int? {
        let holes = holeScores ?? []
        return holes.isEmpty ? nil : holes.reduce(0) { $0 + $1.par }
    }

    /// Single read API for a round's par: the per-hole par sum when scored per
    /// hole, otherwise the `par` scalar entered at setup. ALWAYS use this (not
    /// `par`) to compute to-par for display — it keeps the figure consistent
    /// with the per-hole grid (which colors each hole against its own par) and
    /// correct mid-round (after one hole it compares stroke-1 against par-1, not
    /// against the full course par). Quick-entry rounds fall back to the scalar.
    var effectivePar: Int? { holeParSum ?? par }

    /// Whether this golf round has a complete, stats-eligible score — used to
    /// gate inclusion in averages/best/worst so a partial round (e.g. 3 of 18
    /// holes, then ended) doesn't pollute scoring stats with a garbage-low
    /// number. A per-hole round qualifies once every hole is entered; a
    /// quick-entry round qualifies as soon as a total is typed. The
    /// cross-device fallback (`totalScore != nil` when the per-hole rows
    /// haven't synced yet) is intentionally lenient and self-heals once the
    /// rows arrive.
    var isGolfRoundScored: Bool {
        let scored = holeScores ?? []
        if !scored.isEmpty, let total = holes {
            return scored.count >= total
        }
        return totalScore != nil
    }

    /// Whether this game's stats should be rolled into career/season totals.
    /// True when explicitly completed OR when the game is in progress and already
    /// has stats recorded (so quick-entered stats during a live game show up
    /// without requiring the user to end the game first).
    ///
    /// Activity checks every counter that can move independently: plate
    /// appearances cover batter-side entries (including walks and HBP which
    /// don't increment atBats), and totalPitches covers pitcher-side entries.
    var countsTowardStats: Bool {
        if isComplete { return true }
        guard let gs = gameStats else { return false }
        let plateAppearances = gs.atBats + gs.walks + gs.hitByPitches
        return plateAppearances > 0 || gs.totalPitches > 0
    }

    enum DisplayStatus {
        case live, completed, scheduled
    }

    /// Status for badges/labels. A past-dated game shows as `.completed` even
    /// when `isComplete == false` — first-time users adding historical games
    /// for the journal/scrapbook flow shouldn't see "Scheduled" on a date
    /// that has already passed. `isComplete` itself is left untouched so
    /// `countsTowardStats` keeps gating real stat aggregation.
    var displayStatus: DisplayStatus {
        if isLive { return .live }
        if isComplete { return .completed }
        if let date, date < Date() { return .completed }
        return .scheduled
    }

    // MARK: - Firestore Conversion

    func toFirestoreData() -> [String: Any] {
        let athleteRef = athlete?.firestoreId ?? athlete?.id.uuidString ?? ""
        let seasonRef = season?.firestoreId ?? season?.id.uuidString
        var data: [String: Any] = [
            "id": id.uuidString,
            "athleteId": athleteRef,
            "seasonId": seasonRef as Any,
            "opponent": opponent,
            "date": date ?? Date(),
            "year": year ?? Calendar.current.component(.year, from: date ?? Date()),
            "isLive": isLive,
            "isComplete": isComplete,
            "createdAt": createdAt ?? Date(),
            "updatedAt": Date(),
            "version": version,
            "isDeleted": false
        ]
        // Optional fields
        if let location = location { data["location"] = location }
        if let notes = notes { data["notes"] = notes }

        // Golf-only fields
        if let holes = holes { data["holes"] = holes }
        if let par = par { data["par"] = par }
        if let totalScore = totalScore { data["totalScore"] = totalScore }
        // Per-round shot-tracking opt-in (SchemaV30). Written unconditionally so
        // toggling it mid-round replicates; false for baseball/softball.
        data["tracksShotByShot"] = tracksShotByShot

        // Multi-round tournament link (SchemaV27). Written unconditionally —
        // NSNull when standalone — so removing a round from a tournament clears
        // the server field (updateGame uses merge:true and would otherwise keep
        // a stale id). roundNumber tracks order within the tournament.
        data["tournamentId"] = tournament?.firestoreId ?? tournament?.id.uuidString ?? NSNull()
        data["roundNumber"] = roundNumber ?? NSNull()

        // Inline GameStatistics counters onto the game doc ONLY when this game
        // is in manual-entry mode. Video-derived stats are re-derivable on any
        // device from synced VideoClip play results, so uploading them would
        // just create a race: if Device A re-uploads game metadata with stale
        // stats_* values, it could overwrite fresher video-derived counters on
        // Device B. Manual-entry stats have no other transport, hence the gate.
        if let gs = gameStats, gs.hasManualEntry {
            data["stats_hasManualEntry"] = gs.hasManualEntry
            data["stats_atBats"] = gs.atBats
            data["stats_hits"] = gs.hits
            data["stats_runs"] = gs.runs
            data["stats_singles"] = gs.singles
            data["stats_doubles"] = gs.doubles
            data["stats_triples"] = gs.triples
            data["stats_homeRuns"] = gs.homeRuns
            data["stats_rbis"] = gs.rbis
            data["stats_strikeouts"] = gs.strikeouts
            data["stats_walks"] = gs.walks
            data["stats_groundOuts"] = gs.groundOuts
            data["stats_flyOuts"] = gs.flyOuts
            data["stats_hitByPitches"] = gs.hitByPitches
            data["stats_totalPitches"] = gs.totalPitches
            data["stats_balls"] = gs.balls
            data["stats_strikes"] = gs.strikes
            data["stats_wildPitches"] = gs.wildPitches
            data["stats_pitchingStrikeouts"] = gs.pitchingStrikeouts
            data["stats_pitchingWalks"] = gs.pitchingWalks
            data["stats_fastballPitchCount"] = gs.fastballPitchCount
            data["stats_fastballSpeedTotal"] = gs.fastballSpeedTotal
            data["stats_offspeedPitchCount"] = gs.offspeedPitchCount
            data["stats_offspeedSpeedTotal"] = gs.offspeedSpeedTotal
        }
        return data
    }
}

// MARK: - Practice Models
@Model
final class Practice {
    var id: UUID = UUID()
    var date: Date?
    var createdAt: Date?
    var athlete: Athlete?
    var season: Season?
    @Relationship(inverse: \VideoClip.practice) var videoClips: [VideoClip]?
    @Relationship(inverse: \PracticeNote.practice) var notes: [PracticeNote]?
    @Relationship(inverse: \Photo.practice) var photos: [Photo]?
    /// Per-hole scoring rows for golf practice rounds (SchemaV25). Populated
    /// only when `practiceType == "practice_round"` (PR3); nil otherwise.
    @Relationship(inverse: \HoleScore.practice) var holeScores: [HoleScore]?

    /// Practice type — baseball values ("general"/"batting"/"fielding"/
    /// "bullpen"/"team") or golf values ("practice_round"/"range_session",
    /// added in v6.1 PR3).
    var practiceType: String = "general"

    /// Hole count for golf practice rounds (9 or 18). Nil for baseball
    /// practices and golf range sessions. Read by LiveHoleTracker to cap
    /// the current-hole pointer.
    var holes: Int?

    /// True while a golf practice (round or range session) is the active
    /// live activity on the dashboard (SchemaV26). Mirrors `Game.isLive`.
    /// Set on creation when the practice is dated today on the active season;
    /// cleared by PracticeService.end. Only one golf activity (Game or
    /// Practice) is live at a time — see LiveActivityGuard.
    var isLive: Bool = false

    /// Timestamp the practice went live (SchemaV26). Nil when not live.
    /// Mirrors `Game.liveStartDate`; powers the range card's elapsed timer.
    var liveStartDate: Date?

    /// Optional course name for golf practice rounds (SchemaV26). Surfaced as
    /// the live card subtitle when set; nil falls back to "Practice Round".
    /// Range sessions and baseball practices leave this nil.
    var course: String?

    /// Per-round opt-in for shot-by-shot tracking (SchemaV30). Mirrors
    /// `Game.tracksShotByShot` for golf practice rounds; defaults false.
    var tracksShotByShot: Bool = false

    // MARK: - Firestore Sync Metadata (Phase 3)

    /// Firestore document ID (maps to cloud storage)
    var firestoreId: String?

    /// Last successful sync timestamp
    var lastSyncDate: Date?

    /// Dirty flag - true when local changes need uploading
    var needsSync: Bool = false

    /// Soft delete flag - true when deleted on another device
    var isDeletedRemotely: Bool = false

    /// Version number for conflict resolution
    var version: Int = 0

    init(date: Date) {
        self.id = UUID()
        self.date = date
        self.createdAt = Date()
    }

    // MARK: - Firestore Conversion

    func toFirestoreData() -> [String: Any] {
        let athleteRef = athlete?.firestoreId ?? athlete?.id.uuidString ?? ""
        let seasonRef = season?.firestoreId ?? season?.id.uuidString
        var data: [String: Any] = [
            "id": id.uuidString,
            "athleteId": athleteRef,
            "seasonId": seasonRef as Any,
            "practiceType": practiceType,
            "date": date ?? Date(),
            "createdAt": createdAt ?? Date(),
            "updatedAt": Date(),
            "version": version,
            "isDeleted": false
        ]
        // Golf practice-round hole count (v6.1 PR3). Only practice rounds set
        // this; baseball practices and range sessions stay nil and the key
        // is omitted from the doc.
        if let holes = holes { data["holes"] = holes }
        // Live-activity state (SchemaV26). Synced so a round/session started on
        // one device surfaces as live on another; cleared on End.
        data["isLive"] = isLive
        if let liveStartDate = liveStartDate { data["liveStartDate"] = liveStartDate }
        if let course = course { data["course"] = course }
        data["tracksShotByShot"] = tracksShotByShot
        return data
    }

    /// Properly delete practice with all associated files and data
    @MainActor func delete(in context: ModelContext) {
        // Drop any pending stale-session reminder (no-op when none scheduled).
        GameAlertService.shared.cancelEndPracticeReminder(forID: self.id)

        // Delete video clips using their delete method for proper cleanup.
        // cleanupReels: false — this method hard-deletes the practice's reels
        // below, so per-clip reel stripping would be wasted work.
        for videoClip in (self.videoClips ?? []) {
            videoClip.delete(in: context, cleanupReels: false)
        }

        // Delete notes
        for note in (self.notes ?? []) {
            context.delete(note)
        }

        // Delete per-hole scoring rows (golf practice rounds). Inverse on
        // HoleScore.practice would nullify by default; hard-deleting keeps
        // the table tidy and stops dead rows from leaking into sync.
        for hole in (self.holeScores ?? []) {
            context.delete(hole)
        }

        // v6.1 PR3: HighlightReels generated for practice-round birdies
        // carry a denormalized `practiceID` FK (no SwiftData relationship),
        // so they don't cascade automatically. Mirror Athlete.delete's
        // pattern: flat fetch, filter, hard-delete locally. Firestore
        // orphans are picked up by the same daily cleanup that handles the
        // Athlete-delete path.
        let practiceID = self.id
        do {
            let allReels = try context.fetch(FetchDescriptor<HighlightReel>())
            for reel in allReels where reel.practiceID == practiceID {
                context.delete(reel)
            }
        } catch {
            // Best-effort — log and continue; the practice deletion itself
            // shouldn't be blocked by an unreachable reel table.
        }

        // SwiftData handles relationship cleanup automatically
        context.delete(self)
    }
}

// MARK: - Practice Type (display helper — not stored directly)

enum PracticeType: String, CaseIterable, Identifiable {
    case general
    case batting
    case fielding
    case bullpen
    case team
    // Golf-only cases (v6.1 PR3). Raw values are wire-format and referenced
    // by SyncCoordinator+HoleScores and LiveHoleTracker — do not rename.
    case practiceRound = "practice_round"
    case rangeSession  = "range_session"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .general:        return "General"
        case .batting:        return "Batting"
        case .fielding:       return "Fielding"
        case .bullpen:        return "Bullpen"
        case .team:           return "Team"
        case .practiceRound:  return "Practice Round"
        case .rangeSession:   return "Range Session"
        }
    }

    var icon: String {
        switch self {
        case .general:        return "figure.baseball"
        case .batting:        return "baseball.fill"
        case .fielding:       return "hand.raised.fill"
        case .bullpen:        return "flame.fill"
        case .team:           return "person.3.fill"
        case .practiceRound:  return "flag.fill"
        case .rangeSession:   return "target"
        }
    }

    /// Sport-aware case list. The two golf cases are mutually exclusive with
    /// the baseball cases at the UX layer — golf athletes don't see batting
    /// drills and vice versa. Used by PracticesView, AddPracticeView, and
    /// PracticeDetailView to render the right Type picker.
    static func cases(for sport: Season.SportType) -> [PracticeType] {
        switch sport {
        case .golf:
            return [.practiceRound, .rangeSession]
        case .baseball, .softball:
            return [.general, .batting, .fielding, .bullpen, .team]
        }
    }
}

@Model
final class PracticeNote {
    var id: UUID = UUID()
    var content: String = ""
    var createdAt: Date?
    var practice: Practice?

    // MARK: - Firestore Sync Metadata
    var firestoreId: String?
    var needsSync: Bool = false

    init(content: String) {
        self.id = UUID()
        self.content = content
        self.createdAt = Date()
    }

    func toFirestoreData(practiceFirestoreId: String) -> [String: Any] {
        return [
            "id": id.uuidString,
            "practiceId": practiceFirestoreId,
            "content": content,
            "createdAt": createdAt ?? Date(),
            "updatedAt": Date(),
            "isDeleted": false
        ]
    }
}



@Model
final class PlayResult {
    var id: UUID = UUID()
    var type: PlayResultType = PlayResultType.single
    var createdAt: Date?
    var videoClip: VideoClip?

    init(type: PlayResultType) {
        self.id = UUID()
        self.type = type
        self.createdAt = Date()
    }
}


// MARK: - Onboarding Models
@Model
final class OnboardingProgress {
    var id: UUID = UUID()
    var hasCompletedOnboarding: Bool = false
    var completedAt: Date?
    var createdAt: Date?
    /// Firebase Auth UID that owns this record. Prevents cross-account leakage
    /// when multiple accounts are used on the same device.
    var firebaseAuthUid: String?

    init() {
        self.id = UUID()
        self.createdAt = Date()
    }

    init(firebaseAuthUid: String) {
        self.id = UUID()
        self.createdAt = Date()
        self.firebaseAuthUid = firebaseAuthUid
    }

    func markCompleted() {
        self.hasCompletedOnboarding = true
        self.completedAt = Date()
    }
}

