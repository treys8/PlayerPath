//
//  PlayerPathSchema.swift
//  PlayerPath
//
//  SwiftData schema versioning — locks V1 so future model changes
//  can be handled with proper migrations instead of crashing.
//

import SwiftData

// MARK: - Schema V1 (Initial Release)

/// The initial schema shipped with v1.0.
/// When you need to change models in a future update:
/// 1. Create a new `SchemaV2` with `versionIdentifier = Schema.Version(2, 0, 0)`
/// 2. Add a `MigrationStage` to `PlayerPathMigrationPlan.stages`
/// 3. Update `schemas` to include `[SchemaV1.self, SchemaV2.self]`
/// 4. In PlayerPathApp, switch to:
///    ```
///    let container = try ModelContainer(for: Schema(versionedSchema: SchemaV2.self),
///        migrationPlan: PlayerPathMigrationPlan.self)
///    ```
///    and use `.modelContainer(container)`
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

// MARK: - Migration Plan

enum PlayerPathMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        // No migrations yet — V1 is the baseline.
        // Future example:
        // .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)
        []
    }
}
