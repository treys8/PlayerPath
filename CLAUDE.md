# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PlayerPath is an iOS **dual-sport** performance tracking app (SwiftUI, iOS 17+): baseball/softball (record game videos with play-by-play tagging, track stats across seasons) and **golf** (round/tournament scoring, per-hole + opt-in shot-by-shot stats, birdie-or-better auto-highlight reels). Athletes share clips with coaches for annotated feedback. A person who plays two sports is modeled as **two `Athlete` rows linked by `personGroupID`** = one subscription slot. Monetized via StoreKit 2 subscriptions.

## Build & Run

This is an Xcode project — there is no SPM Package.swift or Podfile. Open `PlayerPath.xcodeproj` in Xcode 15+.

```bash
# Build from command line
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project PlayerPath.xcodeproj -scheme PlayerPath -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Nuclear clean when the build cache is stale (deletes DerivedData/build/SwiftPM caches)
./CLEAN_BUILD.sh
```

CLI `xcodebuild` needs the `DEVELOPER_DIR` prefix; transient SourceKit errors in the output are safe to ignore — trust the final build result. Version/build numbers are bumped in Xcode target settings (there is no increment script).

There are **no automated tests** — no test targets exist in the project.

## Architecture

**Pattern:** MVVM + Service-Oriented, all SwiftUI.

### App Entry & Navigation

`PlayerPathApp.swift` → `PlayerPathMainView` (defined in `MainAppView.swift`)

- **Unauthenticated:** → `WelcomeFlow` (in `Views/Auth/WelcomeFlow.swift`)
- **Authenticated:** → `AuthenticatedFlow` → `UserMainFlow` (in `Views/Athletes/UserMainFlow.swift`)

Two parallel tab bars based on user role:
- **Athletes:** `MainTabView` — Home, Games, Videos, Stats, More. The Home tab is `JournalView` (`Views/Journal/`) — the older `Views/Dashboard/DashboardView` is retired dead code for athletes; don't extend it.
- **Coaches:** `CoachTabView` — Dashboard, Athletes, Profile (managed by `CoachNavigationCoordinator`)

Athlete navigation uses `NavigationCoordinator` (Observable class) with deep linking via `DeepLinkIntent`. Coach navigation uses `CoachNavigationCoordinator` (Observable class, in `Views/Coach/CoachNavigationCoordinator.swift`).

### Data Layer

- **SwiftData** for local persistence. Schema is versioned (V1–V34; currently `SchemaV34`) in `PlayerPathSchema.swift` with lightweight migrations only. The live container binds `Schema(SchemaV34.models)` in `PlayerPathApp.swift` — bump the **bound schema**, not the `MigrationPlan` (which is documentation only).
- **Firebase Firestore** for cloud sync and shared data (coach folders, invitations, clip metadata).
- **Local-first architecture**: `SyncCoordinator` handles bidirectional sync between SwiftData and Firestore using dirty flags and version numbers for conflict resolution.

### Core Model Hierarchy

`User → Athlete → Season → Game/Practice → VideoClip → PlayResult`

**Golf** extends this: `GolfTournament` sits above `Game` (a golf `Game` = a "Round"; deleting a tournament UNLINKS rounds, never cascades), `HoleScore` hangs off Game/Practice (with child `Shot` for shot-by-shot), and birdie-or-better rounds bundle clips into a virtual `HighlightReel`.

Core models are defined in `Models.swift` with additional model files in `PlayerPath/Models/`: core entities (`Athlete`, `Season`, `VideoClip`, `Coach`, `Photo`, `AthleteStatistics`, `PlayResultType`, `AnnotationModels`), golf (`GolfTournament`, `HoleScore`, `Shot`, `ShotEnums`, `HighlightReel`, `Club`), plus milestones (`Milestone`) and drill/practice support (`DrillType`, `SavedDrillTemplate`) — `ls PlayerPath/Models/` for the full list. Firestore data types are in `FirestoreModels.swift`.

### Key Services

Some services live in `PlayerPath/Services/`, others at the `PlayerPath/` top level:

**Top-level:**
- `SyncCoordinator` — SwiftData ↔ Firestore bidirectional sync
- `VideoCloudManager` — Firebase Storage uploads with progress tracking
- `ClipPersistenceService` — Local video file management
- `StoreKitManager` — Singleton (`StoreKitManager.shared`), `@MainActor`. Manages entitlements and subscription tiers
- `ComprehensiveAuthManager` — Firebase Auth (email/password + Apple Sign In)
- `SharedFolderManager` — Coach shared folder management with real-time Firestore listeners
- `PushNotificationService` — Push notification authorization and scheduling

**In `PlayerPath/Services/`** (~60 files — `ls PlayerPath/Services/` for the full list), grouped by theme:
- **Infrastructure:** `UploadQueueManager` (background uploads, exponential backoff), `ErrorHandlerService` (centralized errors — see Error Handling below), `RetryHelpers` (`withRetry()`/`retryAsync()`), `ConnectivityMonitor`, `AnalyticsService`
- **Coach suite:** `CoachSessionManager` (live sessions), `CoachInvitationManager`/`AthleteInvitationManager` (both invitation flows), `CoachDowngradeManager`/`CoachRemovalService` (seat enforcement), `CoachVideoProcessingService`, `CoachVideoCacheService`, `CoachFolderArchiveManager`, `CoachTemplateService` (quick cues), `ClipCommentService`
- **Stats & milestones:** `StatisticsService` (batting/pitching), `MilestoneEngine` + `MilestoneCelebrationService`/`MilestoneReminderService`, `CSVExportService`, `PDFReportGenerator`
- **Golf:** `GolfScoreWriter` (single write path for scores), `ScorecardOCR` (scan flow), `HandicapEstimator`, `ShotStats`/`ShotStrokesGained`/`ShotRollup`/`ShotClubRecommender`, `LiveHoleTracker`, `GolfCaptureSession`
- **Media:** `VideoStitchingService` (reel stitching + title card/watermark), `VideoCompressionService`, `VideoTrimExporter`/`ClipTrimService`, `PhotoThumbnailLoader`, `VideoOrientationDetector`
- **Engagement:** `SubscriptionGateService` (tier gates), `OnboardingManager`, `ReviewPromptManager`, `ActivityNotificationService`, `InactivityReminderService`, `WeeklySummaryScheduler`, `HighlightReelBannerService`

### FirestoreManager

`FirestoreManager` is a `@MainActor` singleton split into domain-specific extension files:

- `FirestoreManager.swift` — Shell (singleton, `db`, `errorMessage`, init)
- `FirestoreManager+SharedFolders.swift` — Folder CRUD + permissions
- `FirestoreManager+VideoMetadata.swift` — Video CRUD + thumbnails
- `FirestoreManager+Annotations.swift` — Comments + real-time listener
- `FirestoreManager+Invitations.swift` — Both invitation flows (athlete→coach, coach→athlete)
- `FirestoreManager+UserProfile.swift` — Profile CRUD + GDPR deletion + subscription sync
- `FirestoreManager+EntitySync.swift` — Athletes/Seasons/Games/Practices/Notes/Photos/Coaches CRUD
- `FirestoreManager+DrillCards.swift` — Drill card CRUD for videos
- `FirestoreModels.swift` — All Firestore data types (SharedFolder, FirestoreVideoMetadata, CoachInvitation, UserProfile, CoachSession, etc.)

### Video Pipeline

Recording (athlete): `DirectCameraRecorderView.swift` → `CameraViewModel.swift` → `ModernCameraView.swift` (AVFoundation). Optional `PreUploadTrimmerView` + `PlayResultOverlayView` for tagging.
Recording (coach): `DirectCameraRecorderView.swift` — Standalone camera for session clip capture
Import (athlete): `BulkVideoImportSheet` / `BulkVideoImportViewModel` — multi-select from Photos, untagged, season auto-matched by capture date (or inherited from game/practice context)
Upload: `ClipPersistenceService` → `UploadQueueManager` → `VideoCloudManager` → Firebase Storage
Playback: `VideoPlayerView.swift` with `PlayResultOverlayView` for tagging and coach annotations

### Subscription Tiers

**Player tiers:**

| | Free | Plus | Pro |
|---|---|---|---|
| Athletes | 1 | 3 | 5 |
| Storage | 2GB | 25GB | 100GB |
| Monthly | — | $5.99 | $12.99 |
| Annual | — | $57.99 | $124.99 |

Coach sharing is **not** gated by athlete tier: under Pricing Model V2 the **coach** pays for each connection via their seat, so an athlete on any tier (Free/Plus/Pro) can share with a coach. Athlete tiers re-anchor on storage + multi-athlete + Plus+ features (auto highlights, stats export, season comparison).

**Coach tiers:**

| | Free | Instructor | Pro Instructor | Academy |
|---|---|---|---|---|
| Athletes | 2 | 10 | 30 | Unlimited |
| Monthly | — | $9.99 | $19.99 | Contact Us |
| Annual | — | $95.99 | $191.99 | Contact Us |

Academy is manually granted via Firestore — no StoreKit product exists for it.

Product IDs and feature gates are in `SubscriptionModels.swift`. StoreKit configuration file: `PlayerPath/PlayerPathStoreKit.storekit`.

### Firebase Backend

- **Firestore collections:** `users/`, `sharedFolders/`, `videos/`, `invitations/`, `photos/`, `notifications/`, `coach_access_revocations/`, `coachTemplates/`, `coachSessions/`, `appConfig/`, `pendingDeletions/`
- **Subcollections:** `videos/{id}/comments/`, `videos/{id}/annotations/`, `videos/{id}/drillCards/`, `users/{id}/athletes/`, `users/{id}/seasons/`, `users/{id}/games/`, `users/{id}/practices/`, `users/{id}/golfTournaments/`, `users/{id}/highlightReels/`, `users/{id}/games|practices/{id}/holes/`, `.../holes/{n}/shots/`
- **Security rules:** `firestore.rules` (~1,000 lines) with helper functions for auth/tier/permission checks
- **Cloud Functions:** `firebase/functions/src/index.ts` (Node.js, ~5,000 lines) — email notifications (SendGrid), signed-URL generation, StoreKit subscription/tier sync + App Store Server Notifications V2 webhook, coach athlete-limit enforcement transactions + downgrade audit cron, GDPR deletion, and daily storage cleanup
- **Config:** `GoogleService-Info.plist`

**Authorization model invariants:**
- `hasCoachTier()` in `firestore.rules` is a role/tier identity check only — it does NOT enforce the coach's athlete limit. The authoritative limit enforcement lives in the Cloud Function transactions `acceptAthleteToCoachInvitation`, `acceptCoachToAthleteInvitation`, and the `enforceCoachAthleteLimit` trigger. Rules cannot safely count via a list query.
- Coach addition to `sharedFolders.sharedWithCoachIDs` happens exclusively via Cloud Functions (Admin SDK). The owner-update branch of the sharedFolders rule allows REMOVALS only (subset check), so a direct client write cannot bypass the CF athlete-limit transaction.
- `coach_access_revocations` uses deterministic doc IDs `<folderID>_<coachID>`. `canAccessFolder()` reads this collection to deny re-added-but-since-revoked coaches. CFs delete the doc on legitimate re-accept.
- Athlete-count keying: server and client both prefer `athleteUUID` over `ownerAthleteID`. Parent accounts hosting multiple athlete profiles count as N slots, not 1.

## View Organization

Views are organized by feature in `PlayerPath/Views/` — one line per directory; `ls` the directory for exact filenames:

- `Views/Journal/` — **athlete Home tab**: JournalView feed (games + practices + orphan clips/photos), feed builder, coach-feedback feed items
- `Views/Athletes/` — profile selection & creation, dual-sport Person Card grouping (`AthletePersonGroup`), sport split tool, EditAthleteView
- `Views/Games/` — game/tournament CRUD **plus all golf scoring UI**: scorecard, hole scoring, shot-by-shot, scorecard OCR scan flow, manual batting/pitching entry (~35 files)
- `Views/Practices/` — practice CRUD, practice types/focus pickers, practice clip rows
- `Views/Stats/` — batting/pitching sections, golf stats/strokes-gained/score-distribution sections, milestones list, season comparisons, hero cards
- `Views/Highlights/` — highlight cards **plus the reel pipeline**: generation, stitching coordinator, card/overlay renderers, export options, stitched-reel cache
- `Views/Photos/` — photo grid, fullscreen swipe viewer, batch event-tagging, bulk import
- `Views/Videos/` — bulk video import sheet + view model
- `Views/Coach/` — coach-role UI: tab bar, sessions, review queue/sequence, telestration, filmstrip scrubber, drill cards, tag editing, billing/limit banners (~35 files)
- `Views/Coaches/` — athlete-side coach management: invite, share-to-folder, coach detail, pending invitations
- `Views/Profile/` — settings, account management, subscription, storage, data export
- `Views/Components/` — shared reusables: video player, clip cards, trimmer, play-result editor, banners, TipKit tips
- `Views/Shared/` — app-wide primitives: empty/error/skeleton states, notification inbox + banners, text fields, button styles
- `Views/Search/` — AdvancedSearchView (single-athlete scope)
- `Views/Navigation/` — MainTabView, AuthenticatedFlow, keyboard shortcuts
- `Views/Auth/` — sign-in, welcome flow, email verification, force update, what's new
- `Views/Onboarding/` — athlete/coach onboarding flows, tutorial
- `Views/Help/` — role- and sport-aware Help/FAQ articles
- `Views/Legal/` — privacy policy, terms
- `Views/Seasons/` — season recap
- `Views/Settings/` — video quality comparison components
- `Views/Player/` — athlete clip review detail
- `Views/Dashboard/` — **retired for athletes** (Home = Journal); some components still reused

Main tab root views remain at the top level: `GamesView.swift`, `PracticesView.swift`, `ProfileView.swift`, `HighlightsView.swift`, `VideoClipsView.swift`, `StatisticsView.swift` (+ their ViewModels).

Top-level coach views: `CoachDashboardView.swift`, `CoachFolderDetailView.swift`, `CoachInvitationsView.swift`, `CoachPaywallView.swift`, `CoachProfileView.swift`, `CoachVideoPlayerView.swift`, `CoachVideoUploadView.swift`, `CoachesView.swift`, `DirectCameraRecorderView.swift`.

## Key Conventions

- `@MainActor` isolation is used extensively for thread safety on ViewModels and services
- All ViewModels use `@Observable` (Swift Observation framework)
- Singletons use `static let shared` pattern (e.g., `StoreKitManager.shared`)
- Bundle ID: `RZR.DT3`

### Error Handling

- **Services/managers:** Use OSLog `Logger` instances (e.g., `syncLog`, `uploadLog`, `firestoreLog`, `authLog`). Each service has its own logger with subsystem `"com.playerpath.app"`.
- **Views:** Use `ErrorHandlerService.shared.reportError()` for catch blocks with Error objects, `reportWarning()` for validation failures, or `handle(error, context:, showAlert: false)` for silent logging.
- **SwiftData saves:** Use `ErrorHandlerService.shared.saveContext(context, caller:)` instead of `try? context.save()`.
- **Async retry:** Use `retryAsync { }` for fire-and-forget retry or `try await withRetry { }` for retry-with-result (defined in `RetryHelpers.swift`).

### Shared Components

- `SeasonFilterMenu` — Reusable season picker used by GamesView, PracticesView, VideoClipsView, StatisticsView, HighlightsView
- `DateFormatters.swift` — Centralized `DateFormatter` extension (`.mediumDate`, `.shortDate`, `.shortTime`, `.fullDate`, `.shortDateTime`, `.monthDay`, `.compactDate`)
- `AppNotifications.swift` — Centralized `Notification.Name` constants
- `DesignTokens.swift` — Design system constants

## Documentation

Extensive docs live in `/docs/` organized by: `architecture/`, `implementation/`, `setup-guides/`, `quick-reference/`. Start with `docs/README.md` for navigation.
