//
//  PlayerPathSchema.swift
//  PlayerPath
//
//  SwiftData schema versioning. Every time a @Model class changes, a new
//  SchemaV# must be added here. Skipping this step causes SwiftData to silently
//  wipe the database on the next build — destroying user and tester data.
//

import SwiftData

// MARK: - HOW TO ADD A NEW MODEL PROPERTY (read this before editing Models.swift)
//
//  ANY change to a @Model class requires a new schema version. This includes:
//    • Adding a new stored property
//    • Removing a stored property
//    • Renaming a stored property
//    • Changing a property's type
//    • Adding or removing a @Relationship
//
//  NEVER edit SchemaV1 (or any already-shipped version). It is a frozen
//  snapshot. Changing it defeats the entire purpose of versioning.
//
//  STEP-BY-STEP for adding, e.g., a new property `nickname: String?` to Athlete:
//
//  1. Make the change in Models.swift as normal.
//     (Add `var nickname: String? = nil` to the Athlete @Model class.)
//
//  2. Copy SchemaV1 below, rename it SchemaV2, bump the version number,
//     and add the new model type (or leave the list identical if the model
//     type is already listed — the version bump alone is enough):
//
//       enum SchemaV2: VersionedSchema {
//           static var versionIdentifier = Schema.Version(2, 0, 0)
//           static var models: [any PersistentModel.Type] { SchemaV1.models }
//       }
//
//  3. Add a lightweight migration stage to PlayerPathMigrationPlan:
//
//       static var stages: [MigrationStage] {
//           [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)]
//       }
//
//     Lightweight migration works for: adding an optional property, adding a
//     property with a default value, or removing a property.
//
//     If you are RENAMING a property you need a custom migration instead —
//     see Apple's docs on MigrationStage.custom.
//
//  4. Update PlayerPathMigrationPlan.schemas to include the new version:
//
//       static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }
//
//  5. Update PlayerPathApp.sharedModelContainer to use the newest version:
//
//       let schema = Schema(versionedSchema: SchemaV2.self)
//
//  6. Build and run. SwiftData will migrate existing stores automatically.
//     No data is lost.
//
//  CHEAT SHEET — what migration type to use:
//    Added optional property (var foo: String? = nil)  → .lightweight ✅
//    Added property with default value (var foo = 0)   → .lightweight ✅
//    Removed a property entirely                       → .lightweight ✅
//    Renamed a property                                → .custom      ⚠️
//    Changed a property's type                         → .custom      ⚠️
//    Changed a @Relationship                           → .custom      ⚠️

// MARK: - Schema V1 (Initial Release)

/// Frozen snapshot of the schema as of the initial TestFlight / App Store release.
/// Do not modify this enum. Add a SchemaV2 for any future changes.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            User.self,
            Athlete.self,
            Season.self,
            Game.self,
            Practice.self,
            PracticeNote.self,
            VideoClip.self,
            PlayResult.self,
            AthleteStatistics.self,
            GameStatistics.self,
            UserPreferences.self,
            OnboardingProgress.self,
            PendingUpload.self,
            Coach.self,
            Photo.self
        ]
    }
}

// MARK: - Schema V2 (2/24/26 — Subscription Tier System)
//
//  Changes from V1:
//    • User.isPremium (Bool) removed
//    • User.subscriptionTier (String = "free") added
//    • User.hasCoachingAddOn (Bool = false) added (later removed in V8)
//
//  Both additions have default values → lightweight migration is sufficient.
//  Removal of isPremium is also handled by lightweight migration.

enum SchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    // The model list is identical to V1; the version bump is what triggers migration.
    static var models: [any PersistentModel.Type] { SchemaV1.models }
}

// MARK: - Schema V3 (3/4/26 — Unified Clip Comment Thread)
//
//  Changes from V2:
//    • VideoClip.note (String? = nil) added — athlete's personal note on a clip
//
//  Optional with nil default → lightweight migration is sufficient.

enum SchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] { SchemaV1.models }
}

// MARK: - Schema V4 (3/6/26 — Cross-device sync for PracticeNotes, Photos, Coaches)
//
//  Changes from V3:
//    • PracticeNote.firestoreId (String? = nil) added
//    • PracticeNote.needsSync (Bool = false) added
//    • Photo.cloudURL (String? = nil) added
//    • Photo.firestoreId (String? = nil) added
//    • Photo.needsSync (Bool = false) added
//    • Coach.firestoreId (String? = nil) added
//    • Coach.needsSync (Bool = false) added
//
//  All additions are optional or have defaults → lightweight migration.

enum SchemaV4: VersionedSchema {
    static var versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] { SchemaV1.models }
}

// MARK: - Schema V5 (3/7/26 — GameStatistics HBP tracking)
//
//  Changes from V4:
//    • GameStatistics.hitByPitches (Int = 0) added — tracks batter HBP per game
//      so GameStatistics.onBasePercentage uses the correct OBP formula.
//
//  Default value of 0 → lightweight migration is sufficient.

enum SchemaV5: VersionedSchema {
    static var versionIdentifier = Schema.Version(5, 0, 0)
    static var models: [any PersistentModel.Type] { SchemaV1.models }
}

// MARK: - Schema V6 (3/9/26 — Stale game alerts)
//
//  Changes from V5:
//    • Game.liveStartDate (Date? = nil) added — timestamp when game went live;
//      used by GameAlertService to detect games left running too long.
//
//  Optional with nil default → lightweight migration is sufficient.

enum SchemaV6: VersionedSchema {
    static var versionIdentifier = Schema.Version(6, 0, 0)
    static var models: [any PersistentModel.Type] { SchemaV1.models }
}

// MARK: - Schema V7 (3/10/26 — Denormalized clip display data)
//
//  Changes from V6:
//    • VideoClip.gameOpponent (String? = nil) added — opponent copied from game.opponent at save time
//    • VideoClip.gameDate (Date? = nil) added — date copied from game.date at save time
//    • VideoClip.seasonName (String? = nil) added — display name copied from season at save time
//
//  All optional with nil defaults → lightweight migration is sufficient.

enum SchemaV7: VersionedSchema {
    static var versionIdentifier = Schema.Version(7, 0, 0)
    static var models: [any PersistentModel.Type] { SchemaV1.models }
}

// MARK: - Schema V8 (3/12/26 — Remove dead hasCoachingAddOn field)
//
//  Changes from V7:
//    • User.hasCoachingAddOn (Bool) removed — coaching access is now gated
//      by SubscriptionTier.pro, not a separate add-on flag.
//
//  Property removal → lightweight migration is sufficient.

enum SchemaV8: VersionedSchema {
    static var versionIdentifier = Schema.Version(8, 0, 0)
    static var models: [any PersistentModel.Type] { SchemaV1.models }
}

// MARK: - Schema V9 (3/12/26 — Cloud storage usage tracking)
//
//  Changes from V8:
//    • User.cloudStorageUsedBytes (Int64 = 0) added — running total of bytes
//      stored in Firebase Storage, used to enforce per-tier storage limits.
//
//  Default value of 0 → lightweight migration is sufficient.

enum SchemaV9: VersionedSchema {
    static var versionIdentifier = Schema.Version(9, 0, 0)
    static var models: [any PersistentModel.Type] { SchemaV1.models }
}

// MARK: - Schema V10 (3/19/26 — Practice types)
//
//  Changes from V9:
//    • Practice.practiceType (String = "general") added — categorizes practices
//      as general, batting, fielding, bullpen, or team.
//
//  Default value of "general" → lightweight migration is sufficient.

enum SchemaV10: VersionedSchema {
    static var versionIdentifier = Schema.Version(10, 0, 0)
    static var models: [any PersistentModel.Type] { SchemaV1.models }
}

// SchemaV11:
//  Added GameStatistics pitching fields: totalPitches, balls, strikes, wildPitches.
//  All default to 0 → lightweight migration is sufficient.

enum SchemaV11: VersionedSchema {
    static var versionIdentifier = Schema.Version(11, 0, 0)
    static var models: [any PersistentModel.Type] { SchemaV1.models }
}

// MARK: - Schema V12 (Pitching strikeouts/walks + pitch type)
//
//  Changes from V11:
//    • AthleteStatistics.pitchingStrikeouts (Int = 0) added
//    • AthleteStatistics.pitchingWalks (Int = 0) added
//    • GameStatistics.pitchingStrikeouts (Int = 0) added
//    • GameStatistics.pitchingWalks (Int = 0) added
//    • VideoClip.pitchType (String? = nil) added — "fastball" or "offspeed"
//
//  All additions have defaults or are optional → lightweight migration.

enum SchemaV12: VersionedSchema {
    static var versionIdentifier = Schema.Version(12, 0, 0)
    static var models: [any PersistentModel.Type] { SchemaV1.models }
}

// MARK: - Schema V13 (3/25/26 — Photo sync parity)
//
//  Changes from V12:
//    • Photo.version (Int = 0) added
//    • Photo.isDeletedRemotely (Bool = false) added
//
//  Both additions have defaults → lightweight migration.

enum SchemaV13: VersionedSchema {
    static var versionIdentifier = Schema.Version(13, 0, 0)
    static var models: [any PersistentModel.Type] { SchemaV1.models }
}

// MARK: - Schema V14 (3/25/26 — Coach upload queue fields)
//
//  Changes from V13:
//    • PendingUpload.isCoachUpload (Bool = false) added
//    • PendingUpload.folderID (String? = nil) added
//    • PendingUpload.coachID (String? = nil) added
//    • PendingUpload.coachName (String? = nil) added
//    • PendingUpload.sessionID (String? = nil) added
//
//  All additions have defaults → lightweight migration.

enum SchemaV14: VersionedSchema {
    static var versionIdentifier = Schema.Version(14, 0, 0)
    static var models: [any PersistentModel.Type] { SchemaV1.models }
}

// MARK: - Schema V15 (Fastball velocity tracking)
//
//  Changes from V14:
//    • AthleteStatistics.fastballPitchCount (Int = 0) added
//    • AthleteStatistics.fastballSpeedTotal (Double = 0) added
//    • AthleteStatistics.offspeedPitchCount (Int = 0) added
//    • AthleteStatistics.offspeedSpeedTotal (Double = 0) added
//    • GameStatistics.fastballPitchCount (Int = 0) added
//    • GameStatistics.fastballSpeedTotal (Double = 0) added
//    • GameStatistics.offspeedPitchCount (Int = 0) added
//    • GameStatistics.offspeedSpeedTotal (Double = 0) added
//
//  All additions have defaults → lightweight migration.

enum SchemaV15: VersionedSchema {
    static var versionIdentifier = Schema.Version(15, 0, 0)
    static var models: [any PersistentModel.Type] { SchemaV1.models }
}

// MARK: - Schema V16 (2026-04-17 — Per-athlete stat tracking toggle)
//
//  Changes from V15:
//    • Athlete.trackStatsEnabled (Bool = true) added — when false, new clips
//      save without play-result tagging and the Stats tab shows a disabled
//      banner. Default true preserves existing behavior for all migrated athletes.
//
//  Default value of true → lightweight migration is sufficient.

enum SchemaV16: VersionedSchema {
    static var versionIdentifier = Schema.Version(16, 0, 0)
    static var models: [any PersistentModel.Type] { SchemaV1.models }
}

// MARK: - Schema V17 (2026-04-21 — Drop unused UserPreferences fields)
//
//  Changes from V16:
//    • UserPreferences.enableHapticFeedback (Bool) removed — now read/written
//      exclusively via UserDefaults "hapticFeedbackEnabled" (Haptics.swift is
//      the sole consumer and already reads that key directly).
//    • UserPreferences.preferredTheme (AppTheme?) removed — now read/written
//      exclusively via UserDefaults "appTheme" (ThemeManager reads that key
//      directly at launch).
//
//  Both fields had zero consumers outside UserPreferencesView, so the SwiftData
//  copies were write-only dead data. Property removals → lightweight migration.

enum SchemaV17: VersionedSchema {
    static var versionIdentifier = Schema.Version(17, 0, 0)
    static var models: [any PersistentModel.Type] { SchemaV1.models }
}

// MARK: - Schema V18 (2026-04-22 — Save coach-shared clips to My Videos)
//
//  Changes from V17:
//    • VideoClip.sourceCoachVideoID (String? = nil) added — points back to the
//      Firestore video doc in the coach's shared folder when a clip was saved
//      from there, so the athlete player can load coach annotations
//      (drawings / notes) via that reference.
//
//  Optional with default nil → lightweight migration is sufficient.

enum SchemaV18: VersionedSchema {
    static var versionIdentifier = Schema.Version(18, 0, 0)
    static var models: [any PersistentModel.Type] { SchemaV1.models }
}

// MARK: - Schema V19 (2026-04-23 — Annotation counts mirrored to VideoClip)
//
//  Changes from V18:
//    • VideoClip.annotationCount (Int = 0) added — mirrors the Firestore
//      videos/{id}.annotationCount value so the athlete's local grid can
//      render coach-feedback badges without fetching annotation subcollections.
//    • VideoClip.drawingCount (Int = 0) added — subset for the pencil badge.
//
//  Both additions have default value 0 → lightweight migration.

enum SchemaV19: VersionedSchema {
    static var versionIdentifier = Schema.Version(19, 0, 0)
    static var models: [any PersistentModel.Type] { SchemaV1.models }
}

// MARK: - Schema V20 (2026-04-24 — Manual stats mode flag)
//
//  Changes from V19:
//    • GameStatistics.hasManualEntry (Bool = false) added — sticky flag that
//      marks games whose counters came from ManualStatisticsEntryView or
//      QuickStatisticsEntryView. When true, recalculateGameStatistics is a
//      no-op for that game, protecting manual entries from being overwritten
//      by video-derived rollups. Paired with a one-time backfill at launch
//      that sets the flag for existing games with stats but no tagged videos.
//
//  Default value of false → lightweight migration is sufficient.

enum SchemaV20: VersionedSchema {
    static var versionIdentifier = Schema.Version(20, 0, 0)
    static var models: [any PersistentModel.Type] { SchemaV1.models }
}

// MARK: - Schema V21 (2026-04-24 — Multi-sport athletes)
//
//  Changes from V20:
//    • Athlete.sport (Sport = .baseball) added — categorizes the athlete
//      as baseball, softball, or golf so the app can route per-sport
//      experiences. Existing athletes default to baseball.
//
//  Default value of .baseball → lightweight migration is sufficient.

enum SchemaV21: VersionedSchema {
    static var versionIdentifier = Schema.Version(21, 0, 0)
    static var models: [any PersistentModel.Type] { SchemaV1.models }
}

// MARK: - Schema V22 (2026-05-25 — Golf round fields on Game)
//
//  Changes from V21:
//    • Game.holes (Int?) added — golf round hole count (9 or 18).
//    • Game.par (Int?) added — golf course par.
//    • Game.totalScore (Int?) added — golf round total score.
//    • Season.SportType.golf case added (no schema impact; string-encoded enum).
//
//  All new properties are optional → lightweight migration.

enum SchemaV22: VersionedSchema {
    static var versionIdentifier = Schema.Version(22, 0, 0)
    static var models: [any PersistentModel.Type] { SchemaV1.models }
}

// MARK: - Schema V23 (2026-05-25 — Golf club tag on VideoClip)
//
//  Changes from V22:
//    • VideoClip.club (Club?) added — golf club tag (Driver / 3W / 5W /
//      3i…9i / PW / GW / SW / LW / Putter). Set at recording time by the
//      sport-parameterized PlayResultOverlayView for clips in a golf season.
//      Stored as a Codable enum (same pattern as Athlete.sport in V21).
//
//  Optional with nil default → lightweight migration is sufficient.

enum SchemaV23: VersionedSchema {
    static var versionIdentifier = Schema.Version(23, 0, 0)
    static var models: [any PersistentModel.Type] { SchemaV1.models }
}

// MARK: - Schema V24 (2026-05-26 — Athlete sport-variant grouping)
//
//  Changes from V23:
//    • Athlete.personGroupID (UUID?) added — links sport-variant profiles
//      (e.g. Zain-Baseball and Zain-Golf) so they share ONE subscription
//      slot. Nil for existing athletes; slot dedup falls back to `id`, so
//      pre-migration data behaves identically to today.
//
//  Optional with nil default → lightweight migration is sufficient.

enum SchemaV24: VersionedSchema {
    static var versionIdentifier = Schema.Version(24, 0, 0)
    static var models: [any PersistentModel.Type] { SchemaV1.models }
}

// MARK: - Schema V25 (2026-05-28 — Per-hole golf scoring + reel scaffold)
//
//  Changes from V24:
//    • HoleScore (new @Model) added — per-hole par/score/putts rows for golf
//      tournaments and practice rounds. XOR parent via game/practice
//      relationships.
//    • HighlightReel (new @Model) added — reference-based virtual reel
//      (clipIDs array + metadata). PR1 lands the schema; PR2 wires creation
//      and AVQueuePlayer playback.
//    • Game.holeScores ([HoleScore]?) relationship added.
//    • Practice.holeScores ([HoleScore]?) relationship added.
//    • Practice.holes (Int? = nil) added in PR3 — 9 or 18 for golf practice
//      rounds; nil for baseball practices and range sessions.
//    • VideoClip.holeNumber (Int? = nil) added — golf clips stamped with
//      their parent round's current hole at ClipPersistenceService save time.
//
//  All additions are new @Model types or new optional properties on existing
//  models → lightweight migration is sufficient.

enum SchemaV25: VersionedSchema {
    static var versionIdentifier = Schema.Version(25, 0, 0)
    static var models: [any PersistentModel.Type] {
        SchemaV1.models + [HoleScore.self, HighlightReel.self]
    }
}

// MARK: - Schema V26 (2026-05-28 — Live golf practices)
//
//  Changes from V25:
//    • Practice.isLive (Bool = false) added — golf practice rounds and range
//      sessions can now be the live dashboard activity, mirroring Game.isLive.
//    • Practice.liveStartDate (Date? = nil) added — when the practice went live.
//    • Practice.course (String? = nil) added — optional course name shown on
//      the live practice-round card.
//
//  All additions are new optional/defaulted properties on an existing model →
//  lightweight migration is sufficient.

enum SchemaV26: VersionedSchema {
    static var versionIdentifier = Schema.Version(26, 0, 0)
    static var models: [any PersistentModel.Type] {
        SchemaV1.models + [HoleScore.self, HighlightReel.self]
    }
}

// MARK: - Schema V27 (2026-05-30 — Multi-round golf tournaments)
//
//  Changes from V26:
//    • GolfTournament (new @Model) added — groups multiple golf rounds (Games)
//      into one tournament with aggregate stroke-play scoring. Per-athlete
//      top-level entity, mirrors Season.
//    • Game.tournament (GolfTournament? = nil) added — optional parent link;
//      nil for standalone rounds and non-golf games.
//    • Game.roundNumber (Int? = nil) added — order within a tournament.
//    • Athlete.golfTournaments ([GolfTournament]? ) relationship added.
//
//  New @Model type plus new optional properties / relationship on existing
//  models → lightweight migration is sufficient.

enum SchemaV27: VersionedSchema {
    static var versionIdentifier = Schema.Version(27, 0, 0)
    static var models: [any PersistentModel.Type] {
        SchemaV1.models + [HoleScore.self, HighlightReel.self, GolfTournament.self]
    }
}

// MARK: - Schema V28 (2026-06-05 — Durable coach-feedback snapshot on saved clips)
//
//  Changes from V27:
//    • VideoClip.coachNoteSnapshot (String? = nil) — local cache of the coach's
//      plain note, copied at save-to-My-Videos time so the athlete player shows
//      it immediately and offline.
//    • VideoClip.coachNoteAuthorSnapshot (String? = nil).
//    • VideoClip.coachNoteUpdatedAtSnapshot (Date? = nil).
//    • VideoClip.coachCueTagsSnapshot ([String]? = nil) — local cache of the
//      coach's quick-cue tags.
//
//  All additions are optional with nil defaults → lightweight migration is
//  sufficient. Local-only: NOT added to the Firestore sync field-lists.

enum SchemaV28: VersionedSchema {
    static var versionIdentifier = Schema.Version(28, 0, 0)
    static var models: [any PersistentModel.Type] {
        SchemaV1.models + [HoleScore.self, HighlightReel.self, GolfTournament.self]
    }
}

// MARK: - Schema V29 (2026-06-10 — Detailed golf per-hole tracking)
//
//  Changes from V28:
//    • HoleScore.fairwayHit (Bool? = nil) — fairway in regulation (par 4+ only).
//    • HoleScore.greenInRegulation (Bool? = nil) — green in regulation.
//    • HoleScore.penalties (Int? = nil) — penalty strokes on the hole.
//
//  All additions are optional with nil defaults → lightweight migration is
//  sufficient. Opt-in: rows stay score+putts unless the user enables detailed
//  stat tracking. Added to the Firestore hole-score sync field-lists.

enum SchemaV29: VersionedSchema {
    static var versionIdentifier = Schema.Version(29, 0, 0)
    static var models: [any PersistentModel.Type] {
        SchemaV1.models + [HoleScore.self, HighlightReel.self, GolfTournament.self]
    }
}

// MARK: - Schema V30 (2026-06-20 — Shot-by-shot golf tracking)
//
//  Changes from V29:
//    • Shot (new @Model) — per-shot rows (club/lie/outcome/penalty/distance)
//      nested under HoleScore via HoleScore.shots (cascade delete).
//    • HoleScore.shots ([Shot]?) relationship added.
//    • Game.tracksShotByShot (Bool = false) — per-round shot-tracking opt-in.
//    • Practice.tracksShotByShot (Bool = false) — same for practice rounds.
//    • Club.hybrid case added (rawValue enum, additive on the wire).
//
//  All additions are a new @Model, a new optional relationship to that new
//  model, defaulted Bools, and a new rawValue enum case → lightweight
//  migration is sufficient. The hole score / FIR / GIR / putts are DERIVED
//  from shots (ShotRollup) into the existing HoleScore fields, so non-shot
//  rounds are untouched.

enum SchemaV30: VersionedSchema {
    static var versionIdentifier = Schema.Version(30, 0, 0)
    static var models: [any PersistentModel.Type] {
        SchemaV1.models + [HoleScore.self, HighlightReel.self, GolfTournament.self, Shot.self]
    }
}

// MARK: - Migration Plan

enum PlayerPathMigrationPlan: SchemaMigrationPlan {
    /// All schema versions in chronological order (oldest first).
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self, SchemaV6.self, SchemaV7.self, SchemaV8.self, SchemaV9.self, SchemaV10.self, SchemaV11.self, SchemaV12.self, SchemaV13.self, SchemaV14.self, SchemaV15.self, SchemaV16.self, SchemaV17.self, SchemaV18.self, SchemaV19.self, SchemaV20.self, SchemaV21.self, SchemaV22.self, SchemaV23.self, SchemaV24.self, SchemaV25.self, SchemaV26.self, SchemaV27.self, SchemaV28.self, SchemaV29.self, SchemaV30.self]
    }

    /// Migration stages between consecutive versions.
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self),
            .lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self),
            .lightweight(fromVersion: SchemaV3.self, toVersion: SchemaV4.self),
            .lightweight(fromVersion: SchemaV4.self, toVersion: SchemaV5.self),
            .lightweight(fromVersion: SchemaV5.self, toVersion: SchemaV6.self),
            .lightweight(fromVersion: SchemaV6.self, toVersion: SchemaV7.self),
            .lightweight(fromVersion: SchemaV7.self, toVersion: SchemaV8.self),
            .lightweight(fromVersion: SchemaV8.self, toVersion: SchemaV9.self),
            .lightweight(fromVersion: SchemaV9.self, toVersion: SchemaV10.self),
            .lightweight(fromVersion: SchemaV10.self, toVersion: SchemaV11.self),
            .lightweight(fromVersion: SchemaV11.self, toVersion: SchemaV12.self),
            .lightweight(fromVersion: SchemaV12.self, toVersion: SchemaV13.self),
            .lightweight(fromVersion: SchemaV13.self, toVersion: SchemaV14.self),
            .lightweight(fromVersion: SchemaV14.self, toVersion: SchemaV15.self),
            .lightweight(fromVersion: SchemaV15.self, toVersion: SchemaV16.self),
            .lightweight(fromVersion: SchemaV16.self, toVersion: SchemaV17.self),
            .lightweight(fromVersion: SchemaV17.self, toVersion: SchemaV18.self),
            .lightweight(fromVersion: SchemaV18.self, toVersion: SchemaV19.self),
            .lightweight(fromVersion: SchemaV19.self, toVersion: SchemaV20.self),
            .lightweight(fromVersion: SchemaV20.self, toVersion: SchemaV21.self),
            .lightweight(fromVersion: SchemaV21.self, toVersion: SchemaV22.self),
            .lightweight(fromVersion: SchemaV22.self, toVersion: SchemaV23.self),
            .lightweight(fromVersion: SchemaV23.self, toVersion: SchemaV24.self),
            .lightweight(fromVersion: SchemaV24.self, toVersion: SchemaV25.self),
            .lightweight(fromVersion: SchemaV25.self, toVersion: SchemaV26.self),
            .lightweight(fromVersion: SchemaV26.self, toVersion: SchemaV27.self),
            .lightweight(fromVersion: SchemaV27.self, toVersion: SchemaV28.self),
            .lightweight(fromVersion: SchemaV28.self, toVersion: SchemaV29.self),
            .lightweight(fromVersion: SchemaV29.self, toVersion: SchemaV30.self)
        ]
    }
}
