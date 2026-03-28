# Services Quick Reference

**Last Updated:** March 27, 2026

Complete catalog of all 51 services. Grouped by domain.

---

## Core Infrastructure

| Service | Location | Pattern | Purpose |
|---------|----------|---------|---------|
| `SyncCoordinator` | Top-level | Singleton, @Observable | SwiftData <-> Firestore bidirectional sync. Extensions: +Athletes, +Seasons, +Games, +Practices, +Videos, +PracticeNotes, +Photos, +Coaches |
| `ComprehensiveAuthManager` | Top-level | Singleton, ObservableObject | Firebase Auth (email + Apple Sign In), biometric auth, user role, profile. Extensions: +Auth, +Profile, +Tier |
| `FirestoreManager` | Top-level | Singleton, ObservableObject | All Firestore operations. 7 extensions: +SharedFolders, +VideoMetadata, +Annotations, +Invitations, +UserProfile, +EntitySync, +DrillCards |
| `StoreKitManager` | Top-level | Singleton, ObservableObject | StoreKit 2 subscriptions. Dual tiers (athlete + coach), entitlements, `hasResolvedEntitlements` flag |
| `ErrorHandlerService` | Services/ | Singleton, ObservableObject | OSLog, error history (50 cap), analytics, haptic feedback. Methods: `reportError()`, `reportWarning()`, `saveContext()` |
| `ConnectivityMonitor` | Services/ | Singleton, @Observable | NWPathMonitor. Properties: `isConnected`, `connectionType`, `isExpensive` |
| `AnalyticsService` | Services/ | Singleton | Firebase Analytics + Crashlytics integration |
| `AppUpdateManager` | Services/ | Singleton, ObservableObject | Forced updates + "What's New" via Firestore `appConfig/current` |

## Video Pipeline

| Service | Location | Pattern | Purpose |
|---------|----------|---------|---------|
| `VideoCloudManager` | Top-level | Singleton, ObservableObject | Firebase Storage uploads/downloads with 50ms throttled progress. Extensions: +Photos, +SharedFolders, +Metadata |
| `ClipPersistenceService` | Top-level | Instantiable | Local video file management, migration from Caches to Documents |
| `UploadQueueManager` | Services/ | Singleton, @Observable | Background upload queue. 10 retries, exponential backoff (5s->1hr). BackgroundTasks support |
| `VideoCompressionService` | Top-level | Singleton | HEVC 1080p preferred, H.264 720p fallback. 30-40% size reduction. Atomic swap via `replaceItemAt` |
| `VideoFileManager` | Top-level | Static utility | Validation: 500MB max, 10min max, 1s min. Thumbnail: 480x270 @ 0.8 quality |
| `CoachVideoProcessingService` | Services/ | Singleton | Post-recording: extract duration, generate/upload thumbnail. Non-fatal on failure |
| `CoachVideoCacheService` | Services/ | Singleton | Offline playback cache for shared folder videos in Caches directory |
| `SecureURLManager` | Top-level | Singleton | Time-limited URLs via Cloud Functions (direct HTTPS, avoids HTTPSCallable crash). URL cache with expiration |
| `VideoUploadService` | Top-level | Instantiable, ObservableObject | Photos picker video processing and validation |
| `VideoRecordingPermissionManager` | Top-level | Instantiable, ObservableObject | Camera + microphone permission checks and requests |

## Coach System

| Service | Location | Pattern | Purpose |
|---------|----------|---------|---------|
| `SharedFolderManager` | Top-level | Singleton, @Observable | Folder CRUD, permissions, real-time Firestore listeners. Properties: `athleteFolders`, `coachFolders` |
| `CoachSessionManager` | Services/ | Singleton, @Observable | Live session lifecycle: schedule, go-live, record, review, complete. One-active constraint, 24hr auto-end |
| `CoachInvitationManager` | Services/ | Singleton, @Observable | Real-time listener for athlete->coach invitations. Properties: `pendingInvitations`, `pendingInvitationsCount` |
| `AthleteInvitationManager` | Services/ | Singleton, @Observable | Athlete-side: accept/decline coach invitations. Real-time Firestore listener |
| `CoachFolderArchiveManager` | Services/ | Singleton, @Observable | Per-coach, per-device folder archiving via UserDefaults |
| `CoachTemplateService` | Services/ | Singleton, @Observable | Firestore CRUD for quick cues and annotation templates |
| `CoachDowngradeManager` | Services/ | Singleton, @Observable | 7-day grace period when over athlete limit. States: none/gracePeriod/selectionRequired |
| `AthleteDowngradeManager` | Services/ | Singleton, @Observable | Detects Pro tier loss while sharing. Notifies coaches but preserves folder access on re-sub |
| `SubscriptionGateService` | Services/ | Static utility enum | `isCoachOverLimit()`, `fullConnectedAthleteCount()`, `coachAthleteSlotsRemaining()` |
| `CoachUploadableAthletesHelper` | Services/ | Static utility enum | Resolves uploadable athletes from folders, prefers "lessons" folders |

## Athlete Features

| Service | Location | Pattern | Purpose |
|---------|----------|---------|---------|
| `StatisticsService` | Services/ | Singleton | Batting/pitching stats calculations and repairs |
| `ClipCommentService` | Services/ | Singleton | Unified comment thread CRUD in `videos/{id}/comments/`. In-memory cache |
| `ActivityNotificationService` | Services/ | Singleton, ObservableObject | In-app notifications with Firestore real-time listeners. Separate unread counts: video vs folder |
| `OnboardingManager` | Services/ | Singleton, ObservableObject | Onboarding state, feature discovery, contextual tips. Per-user scoped via UserDefaults |
| `GameService` | Top-level | Instantiable | Deep game deletion: videos, photos, stats, notifications, Firestore sync |
| `SeasonManager` | Top-level | Static utility | `ensureActiveSeason()`, `linkGameToActiveSeason()` |
| `OrphanedClipRecoveryService` | Services/ | Singleton | Recovers videos orphaned by TestFlight schema changes as untagged practice clips |
| `GameAlertService` | Top-level | Singleton | Local notifications for stale games (3.5hr threshold) |

## Auth & Identity

| Service | Location | Pattern | Purpose |
|---------|----------|---------|---------|
| `AppleSignInManager` | Top-level | Singleton, ObservableObject | Apple Sign In with Firebase Auth. 5-minute nonce expiration |
| `BiometricAuthenticationManager` | Top-level | Singleton, ObservableObject | Face ID / Touch ID session locking. No password storage |
| `PushNotificationService` | Top-level | Singleton, ObservableObject | FCM token management. Categories: CLOUD_BACKUP, GAME_REMINDER, PRACTICE_REMINDER |
| `ProfileImageManager` | Top-level | Singleton | NSCache-backed image caching, background queue file operations |

## Media & Photos

| Service | Location | Pattern | Purpose |
|---------|----------|---------|---------|
| `PhotoPersistenceService` | Top-level | Instantiable | Save to Documents, generate 300x300 thumbnails, create SwiftData records |
| `PDFReportGenerator` | Services/ | Singleton | Professional PDF statistics reports |
| `CSVExportService` | Services/ | Singleton | CSV statistics export (Plus+ tier) |
| `StatisticsExportService` | Top-level | Static utility | Unified CSV/PDF export entry point |

## Utilities

| Service | Location | Pattern | Purpose |
|---------|----------|---------|---------|
| `HapticManager` | Top-level | Singleton | Reusable UIFeedbackGenerator instances for auth, buttons, success/error/warning |
| `StorageManager` | Top-level | Static utility | Device storage checks. Levels: good/moderate/low (500MB)/critical (100MB) |
| `ReviewPromptManager` | Services/ | Singleton | App Store review prompt: session count + game milestones, 60-day minimum interval |
| `QuickActionsManager` | Services/ | Singleton, ObservableObject | iOS Home Screen Quick Actions: recordVideo, addGame, addPractice, viewStats |
| `RetryHelpers` | Services/ | Utility functions | `withRetry()` (with result) and `retryAsync()` (fire-and-forget). Configurable backoff |
| `PerformanceMonitor` | Services/ | Singleton, @Observable | Thumbnail cache hit/miss rate tracking |
| `SampleDataGenerator` | Services/ | Static (DEBUG only) | Generates realistic sample data for new users |

---

## Patterns Summary

- **51 total services** across top-level and Services/ directory
- **Singletons:** `static let shared` (most services)
- **Instantiable:** ClipPersistenceService, PhotoPersistenceService, GameService, VideoUploadService, VideoRecordingPermissionManager
- **@MainActor:** Most services (thread safety on ViewModels)
- **@Observable:** Newer services (Swift Observation)
- **ObservableObject:** Older services (Combine-based)
- **Static utility:** SubscriptionGateService, StorageManager, SeasonManager, RetryHelpers, StatisticsExportService, VideoFileManager
