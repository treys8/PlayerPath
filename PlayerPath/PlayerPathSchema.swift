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
//    • User.hasCoachingAddOn (Bool = false) added
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

// MARK: - Migration Plan

enum PlayerPathMigrationPlan: SchemaMigrationPlan {
    /// All schema versions in chronological order (oldest first).
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self]
    }

    /// Migration stages between consecutive versions.
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self),
            .lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self),
            .lightweight(fromVersion: SchemaV3.self, toVersion: SchemaV4.self)
        ]
    }
}
