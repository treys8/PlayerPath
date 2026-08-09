# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PlayerPath is an iOS **dual-sport** performance tracking app (SwiftUI, iOS 17+): baseball/softball (record game videos with play-by-play tagging, track stats across seasons) and **golf** (round/tournament scoring, per-hole + opt-in shot-by-shot stats, birdie-or-better auto-highlight reels). Athletes share clips with coaches for annotated feedback, and Pro athletes publish a **recruiting profile** — a public web page for college coaches. A person who plays two sports is modeled as **two `Athlete` rows linked by `personGroupID`** = one subscription slot. Monetized via StoreKit 2 subscriptions.

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

**Tests:** the iOS app has **no test target** — `PlayerPath` is the only native target, so there is nothing to run for Swift code. The **security rules do** have a suite:

```bash
cd firebase/rules-tests && npm test   # boots the Firestore emulator, runs *.test.mjs
```

Currently `sharedFolders.test.mjs` and `recruitingProfiles.test.mjs`. Run it after any `firestore.rules` edit — the null-`resource` and subset-check invariants below are exactly what it guards.

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

- **SwiftData** for local persistence. Schema is versioned (V1–V37; currently `SchemaV37`) in `PlayerPathSchema.swift` with lightweight migrations only. The live container binds `Schema(SchemaV37.models)` in `PlayerPathApp.swift` — bump the **bound schema** (both call sites), not the `MigrationPlan` (which is documentation only). Read the current value fresh before bumping; this line goes stale.
- **Firebase Firestore** for cloud sync and shared data (coach folders, invitations, clip metadata).
- **Local-first architecture**: `SyncCoordinator` handles bidirectional sync between SwiftData and Firestore using dirty flags and version numbers for conflict resolution.

### Core Model Hierarchy

`User → Athlete → Season → Game/Practice → VideoClip → PlayResult`

**Golf** extends this: `GolfTournament` sits above `Game` (a golf `Game` = a "Round"; deleting a tournament UNLINKS rounds, never cascades), `HoleScore` hangs off Game/Practice (with child `Shot` for shot-by-shot), and birdie-or-better rounds bundle clips into a virtual `HighlightReel`.

Core models are defined in `Models.swift` with additional model files in `PlayerPath/Models/`: core entities (`Athlete`, `Season`, `VideoClip`, `Coach`, `Photo`, `AthleteStatistics`, `PlayResultType`, `AnnotationModels`), golf (`GolfTournament`, `HoleScore`, `Shot`, `ShotEnums`, `HighlightReel`, `Club`), recruiting (`RecruitingInfo`, `RecruitingStatItem`, `RecruitingBlobValue`), plus milestones (`Milestone`) and drill/practice support (`DrillType`, `SavedDrillTemplate`) — `ls PlayerPath/Models/` for the full list. Firestore data types are in `FirestoreModels.swift`.

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

**In `PlayerPath/Services/`** (~70 files — `ls PlayerPath/Services/` for the full list), grouped by theme:
- **Infrastructure:** `UploadQueueManager` (background uploads, exponential backoff), `ErrorHandlerService` (centralized errors — see Error Handling below), `RetryHelpers` (`withRetry()`/`retryAsync()`), `ConnectivityMonitor`, `AnalyticsService`
- **Coach suite:** `CoachSessionManager` (live sessions), `CoachInvitationManager`/`AthleteInvitationManager` (both invitation flows), `CoachDowngradeManager`/`CoachRemovalService` (seat enforcement), `CoachVideoProcessingService`, `CoachVideoCacheService`, `CoachFolderArchiveManager`, `CoachTemplateService` (quick cues), `ClipCommentService`
- **Stats & milestones:** `StatisticsService` (batting/pitching), `MilestoneEngine` + `MilestoneCelebrationService`/`MilestoneReminderService`, `CSVExportService`, `PDFReportGenerator`
- **Golf:** `GolfScoreWriter` (single write path for scores), `ScorecardOCR` (scan flow), `HandicapEstimator`, `ShotStats`/`ShotStrokesGained`/`ShotRollup`/`ShotClubRecommender`, `LiveHoleTracker`, `GolfCaptureSession`
- **Media:** `VideoStitchingService` (reel stitching + title card/watermark), `VideoCompressionService`, `VideoTrimExporter`/`ClipTrimService`, `PhotoThumbnailLoader`, `VideoOrientationDetector`
- **Engagement:** `SubscriptionGateService` (tier gates), `OnboardingManager`, `ReviewPromptManager`, `ActivityNotificationService`, `InactivityReminderService`, `WeeklySummaryScheduler`, `HighlightReelBannerService`
- **Recruiting:** `RecruitingProfileService` (publish/unpublish/reset-link — see Recruiting Profile below), `RecruitingWebRenditionService` (H.264 web copies), `RecruitingGolfStats`

### FirestoreManager

`FirestoreManager` is a `@MainActor` singleton split into domain-specific `FirestoreManager+*.swift` extension files (`ls PlayerPath/FirestoreManager*.swift`). All Firestore data types live in `FirestoreModels.swift`.

### Video Pipeline

Recording: `DirectCameraRecorderView.swift` → `CameraViewModel.swift` → `ModernCameraView.swift` (AVFoundation). One view serves both roles via its initializer — athletes pass `athlete:/game:/practice:`, coaches pass `coachContext:` for session clip capture. Optional `PreUploadTrimmerView` + `PlayResultOverlayView` for tagging.
Import (athlete): `BulkVideoImportSheet` / `BulkVideoImportViewModel` — multi-select from Photos, untagged, season auto-matched by capture date (or inherited from game/practice context)
Upload: `ClipPersistenceService` → `UploadQueueManager` → `VideoCloudManager` → Firebase Storage
Playback: `VideoPlayerView.swift` with `PlayResultOverlayView` for tagging and coach annotations

### Recruiting Profile

A Pro-gated athlete feature: publishes a shareable public web page for college coaches at `profiles.playerpath.net/p/{shareToken}`, served by the `serveRecruitingProfile` Cloud Function off Firebase Hosting.

- **Entry point:** More tab → Profile → "Recruiting Profile" (`ProfileView.swift`) → `RecruitingProfileEditorView`. UI lives in `Views/Recruiting/` (editor sections, highlight picker, readiness checklist, publish view, QR/share tools).
- **Publish path:** `RecruitingProfileService` upserts `recruitingProfiles/{athleteUUID}` — doc ID is the athlete's canonical UUID, so publish is an idempotent upsert with no lookup query. The share token lives in `recruitingTokens/{shareToken}` and is claimed once, then reused across republishes.
- **Invariants (violate these and the page leaks or breaks):**
  - The doc stores Storage **paths, never URLs**. `serveRecruitingProfile` signs them per request with a short expiry, so nothing durable in Firestore is fetchable.
  - PII keys are **omitted** unless their opt-in flag is on — never written as `null`.
  - Display strings are built client-side by the same helpers the in-app preview uses; the CF is a dumb renderer so the page can never word something differently from the preview.
  - Highlights are served as separate H.264/AAC `.mp4` renditions (`RecruitingWebRenditionService`), never the HEVC/QuickTime master — the master silently fails to play on Firefox and on Windows without the paid HEVC extensions.
  - The `recruitingProfiles` rule guards `resource == null` **first**; without it the first publish always fails (publish reads the doc before writing). See the rules comment at `firestore.rules:1199`.
- **Server side:** `recruitingProfile.ts` (serve + `recruitingViewDigest`) and `recruitingLapseNotice.ts` (throttled push when a page goes stale or dark).

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

- **Firestore collections:** `users/`, `sharedFolders/`, `videos/`, `invitations/`, `photos/`, `notifications/`, `coach_access_revocations/`, `coachTemplates/`, `coachSessions/`, `appConfig/`, `pendingDeletions/`, `athleteOwners/`, `recruitingProfiles/`, `recruitingTokens/`
- **Subcollections:** `videos/{id}/comments/`, `videos/{id}/annotations/`, `videos/{id}/drillCards/`, `users/{id}/athletes/`, `users/{id}/seasons/`, `users/{id}/games/`, `users/{id}/practices/`, `users/{id}/golfTournaments/`, `users/{id}/highlightReels/`, `users/{id}/games|practices/{id}/holes/`, `.../holes/{n}/shots/`
- **Security rules:** `firestore.rules` (~1,300 lines) with helper functions for auth/tier/permission checks. Tested by `firebase/rules-tests/` (see Build & Run).
- **Cloud Functions:** `firebase/functions/src/` (Node.js, ~8,000 lines across 5 files, all re-exported from `index.ts`):
  - `index.ts` — email notifications (SendGrid), signed-URL generation, StoreKit subscription/tier sync + App Store Server Notifications V2 webhook, coach athlete-limit enforcement transactions + downgrade audit cron, GDPR deletion, daily storage cleanup
  - `recruitingProfile.ts` — `serveRecruitingProfile` (renders the public page) + `recruitingViewDigest`
  - `athleteOwnership.ts` — `claimAthleteOwnership` / `reconcileAthleteOwners`, backing the `athleteOwners/` collection
  - `recruitingLapseNotice.ts`, `push.ts` (FCM send helpers)
- **Hosting:** `firebase/hosting-public` (`firebase.json`) — fronts the public recruiting page.
- **Config:** `GoogleService-Info.plist`

**Authorization model invariants:**
- `hasCoachTier()` in `firestore.rules` is a role/tier identity check only — it does NOT enforce the coach's athlete limit. The authoritative limit enforcement lives in the Cloud Function transactions `acceptAthleteToCoachInvitation`, `acceptCoachToAthleteInvitation`, and the `enforceCoachAthleteLimit` trigger. Rules cannot safely count via a list query.
- Coach addition to `sharedFolders.sharedWithCoachIDs` happens exclusively via Cloud Functions (Admin SDK). The owner-update branch of the sharedFolders rule allows REMOVALS only (subset check), so a direct client write cannot bypass the CF athlete-limit transaction.
- `coach_access_revocations` uses deterministic doc IDs `<folderID>_<coachID>`. `canAccessFolder()` reads this collection to deny re-added-but-since-revoked coaches. CFs delete the doc on legitimate re-accept.
- Athlete-count keying: server and client both prefer `athleteUUID` over `ownerAthleteID`. Parent accounts hosting multiple athlete profiles count as N slots, not 1.

**Calling Cloud Functions from the app — never use `HTTPSCallable`.** Every call site goes through a direct `URLSession` POST with a Bearer ID token instead (`SecureURLManager.swift`, `FirestoreManager+Invitations.swift`, `FirestoreManager+UserProfile.swift`). This works around a Firebase iOS SDK / Swift concurrency crash on iOS 26.4 (tracked upstream as firebase-ios-sdk #15974). Match the existing pattern when adding a call; revert only when that issue is fixed.

**Deploying Cloud Functions:**
- `firebase deploy --only functions` does **not** compile TypeScript — it ships whatever is in `lib/`. Always `npm run build` first. `firebase.json` now enforces this with a `predeploy` guard (`firebase/functions/check-build-fresh.sh`) that blocks the deploy when `lib/` is older than `src/`.
- The globally installed `/usr/local/bin/firebase` is an x86_64 binary and **cannot run** on this arm64 Mac. Deploy via `npx firebase-tools` on Node 20 (the repo's default `node` is currently v18).

## View Organization

Views are organized by feature in `PlayerPath/Views/` — `ls PlayerPath/Views/` for the directory list, and `ls` a directory for its filenames. Most map to their name; these are the ones that don't:

- `Views/Journal/` — **athlete Home tab**: JournalView feed (games + practices + orphan clips/photos), feed builder, coach-feedback feed items
- `Views/Athletes/` — profile selection & creation, dual-sport Person Card grouping (`AthletePersonGroup`), sport split tool, EditAthleteView
- `Views/Games/` — game/tournament CRUD **plus all golf scoring UI**: scorecard, hole scoring, shot-by-shot, scorecard OCR scan flow, manual batting/pitching entry
- `Views/Highlights/` — highlight cards **plus the reel pipeline**: generation, stitching coordinator, card/overlay renderers, export options, stitched-reel cache
- `Views/Coach/` — coach-role UI: tab bar, sessions, review queue/sequence, telestration, filmstrip scrubber, drill cards, tag editing, billing/limit banners
- `Views/Coaches/` — **athlete-side** coach management: invite, share-to-folder, coach detail, pending invitations
- `Views/Recruiting/` — recruiting profile editor, highlight picker, readiness checklist, publish/share tools, QR code (see Recruiting Profile above)
- `Views/Player/` — **not** the video player and not the athlete tab root; holds a single file, `AthleteClipReviewDetail.swift`
- `Views/Components/` — shared reusables: video player, clip cards, trimmer, play-result editor, banners, TipKit tips
- `Views/Shared/` — app-wide primitives: empty/error/skeleton states, notification inbox + banners, text fields, button styles
- `Views/Dashboard/` — **retired for athletes** (Home = Journal); some components still reused

Main tab root views remain at the top level, NOT under `Views/`: `GamesView.swift`, `PracticesView.swift`, `ProfileView.swift`, `HighlightsView.swift`, `VideoClipsView.swift`, `StatisticsView.swift` (+ their ViewModels). The top-level `Coach*.swift` files are likewise outside `Views/`.

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
- `FirestoreCollections.swift` — Collection name constants

**Design system — canonical vs legacy. The repo carries two palettes and two type scales; the post-overhaul ones are canonical but the migration is unfinished.**

Use for all new UI:
- `Theme/Theme.swift` — color (Calm Keepsake cream/terracotta, 619 refs). Accent is sport-aware via `@Environment(\.ppAccent)`; warnings use `Theme.warning`.
- `Font+PlayerPath.swift` — type (`.ppTitle`, `.ppBody`, `.ppCaption`, `.ppStatLarge`…).
- `DesignTokens.swift` for the non-color primitives that were never superseded: spacing (`.spacingSmall/Medium/Large`), corner radii (`.cornerLarge`), thumbnail sizes, animation curves, and the `Color(hex:)` initializer `Theme` itself is built on.

⚠️ **Legacy, still load-bearing — never use in new UI, do not bulk-delete:**
- Old palette: `.brandNavy` (271 uses), `.brandGold`, `.brandPrimary`, the blue/purple/green gradients.
- Old type scale: `.bodySmall` (286), `.headingMedium` (178), `.bodyMedium` (137), `.displayLarge`, `.labelSmall`… — these still outnumber the `.pp*` scale roughly 6:1 because most screens are un-migrated.
- These are **deprecated, not deleted** — they still compile and resolve, so nothing fails loudly when someone reaches for one. Treat any doc claiming the palette migration "finished" as stale; verify with a symbol-name grep.

🔍 **Grep trap:** `DesignTokens.swift` defines *extensions on system types*, so call sites read `.bodySmall` with no prefix. Grepping `DesignTokens.` returns ~3 comment hits and makes the file look dead. It has ~1,500 usages. Search by symbol name, never by prefix.

## Repo Tooling (`.claude/`)

- **`/review`** — the thorough code review. Runs the `playerpath-reviewer` agent (project footguns) *and* the generic `code-review` pass, merged into one severity-ordered list. Defaults to the uncommitted diff; also takes a branch, PR number, or path. Use `/code-review` alone for a faster generic-only pass.
- **`/audit`** — repo-wide code quality against a tracked baseline (8 live categories + a Closed list). Baseline last refreshed 2026-08-09; **re-record it in the file whenever you run it**, or the next run compares against stale numbers.
- **`/preflight`** — ship-state dashboard (git, iOS build, functions tsc, deploy drift, build number, device-test backlog). User-invoked only.
- **`/sync-field-check`** — verifies a synced field is wired through all sync sites. Run after adding or changing any field on a synced model.
- **`agents/playerpath-reviewer.md`** — the footgun list (SwiftData traps, sync parity, Firebase invariants, and a do-NOT-flag list). Single source of truth; `/review` dispatches it rather than restating it.
- **`hooks/swift-footgun-check.sh`** — PostToolUse check on every Swift edit: transforms inside a `#Predicate` body, `try? context.save()`, `httpsCallable`. Warning-only (exit 2). Comment lines and string literals are excluded, so a hit is real — investigate rather than dismiss.

## Documentation

Extensive docs live in `/docs/` — subdirectories `architecture/`, `quick-reference/`, `setup-guides/`, `archive/`, plus product/planning and review docs at the `docs/` root. Start with `docs/README.md` for navigation, or `docs/PRODUCT_OVERVIEW.md` for what the app is and who it's for.
