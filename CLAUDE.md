# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PlayerPath is an iOS baseball/softball performance tracking app (SwiftUI, iOS 17+). Athletes record game videos with play-by-play tagging, track statistics across seasons, and share clips with coaches for annotated feedback. Monetized via StoreKit 2 subscriptions.

## Build & Run

This is an Xcode project — there is no SPM Package.swift or Podfile. Open `PlayerPath.xcodeproj` in Xcode 15+.

```bash
# Build from command line
xcodebuild -project PlayerPath.xcodeproj -scheme PlayerPath -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Increment build number before archive
./increment_build_number.sh
```

There are **no automated tests** — no test targets exist in the project.

## Architecture

**Pattern:** MVVM + Service-Oriented, all SwiftUI.

### App Entry & Navigation

`PlayerPathApp.swift` → `ContentView.swift` → `PlayerPathMainView.swift` → `MainAppView.swift` (tab bar)

Navigation is managed by `NavigationCoordinator` (Observable class) with deep linking via `DeepLinkIntent`. The app routes to different UIs based on user role (athlete vs coach).

### Data Layer

- **SwiftData** for local persistence. Schema is versioned (V1–V9) in `PlayerPathSchema.swift` with lightweight migrations only.
- **Firebase Firestore** for cloud sync and shared data (coach folders, invitations, clip metadata).
- **Local-first architecture**: `SyncCoordinator` handles bidirectional sync between SwiftData and Firestore using dirty flags and version numbers for conflict resolution.

### Core Model Hierarchy

`User → Athlete → Season → Game/Practice → VideoClip → PlayResult`

Models are defined in `Models.swift`. Supporting types: `AthleteStatistics`, `GameStatistics`, `Coach`, `Photo`. Firestore data types are in `FirestoreModels.swift`.

### Key Services (in `PlayerPath/Services/`)

- `SyncCoordinator` — SwiftData ↔ Firestore bidirectional sync
- `VideoCloudManager` — Firebase Storage uploads with progress tracking
- `UploadQueueManager` — Background upload queue with exponential backoff retry (up to 10 retries)
- `ClipPersistenceService` — Local video file management
- `StoreKitManager` — Singleton (`StoreKitManager.shared`), `@MainActor`. Manages entitlements and subscription tiers
- `ComprehensiveAuthManager` — Firebase Auth (email/password + Apple Sign In) + biometric auth
- `ErrorHandlerService` — Centralized error handling with OSLog, error history, analytics, haptic feedback, and view helpers (`reportError`, `reportWarning`, `saveContext`)
- `AnalyticsService` — Firebase Analytics
- `StatisticsService` — Batting/pitching stats calculations
- `ConnectivityMonitor` — Network state observation
- `RetryHelpers` — `withRetry()` and `retryAsync()` for async retry-with-backoff

### FirestoreManager

`FirestoreManager` is a `@MainActor` singleton split into domain-specific extension files:

- `FirestoreManager.swift` — Shell (singleton, `db`, `errorMessage`, init)
- `FirestoreManager+SharedFolders.swift` — Folder CRUD + permissions
- `FirestoreManager+VideoMetadata.swift` — Video CRUD + thumbnails
- `FirestoreManager+Annotations.swift` — Comments + real-time listener
- `FirestoreManager+Invitations.swift` — Both invitation flows (athlete→coach, coach→athlete)
- `FirestoreManager+UserProfile.swift` — Profile CRUD + GDPR deletion + subscription sync
- `FirestoreManager+EntitySync.swift` — Athletes/Seasons/Games/Practices/Notes/Photos/Coaches CRUD
- `FirestoreModels.swift` — All Firestore data types (SharedFolder, FirestoreVideoMetadata, CoachInvitation, UserProfile, etc.)

### Video Pipeline

Recording: `VideoRecorderView_Refactored.swift` → `CameraViewModel.swift` → `ModernCameraView.swift` (AVFoundation)
Upload: `ClipPersistenceService` → `UploadQueueManager` → `VideoCloudManager` → Firebase Storage
Playback: `VideoPlayerView.swift` with `PlayResultOverlayView` for tagging and coach annotations

### Subscription Tiers

Athlete tiers: Free (1 athlete, 2GB) → Plus (3 athletes, 25GB) → Pro (5 athletes, 100GB + coach sharing)
Coach tiers: Free (2 athletes) → Instructor (10) → Pro Instructor (30) → Academy (unlimited, manual Firestore grant)

Product IDs and feature gates are in `SubscriptionModels.swift`. StoreKit configuration file: `PlayerPathStoreKit.storekit`.

### Firebase Backend

- **Firestore collections:** `users/`, `sharedFolders/`, `invitations/`, `clips/`
- **Security rules:** `firestore.rules` (~650 lines) with helper functions for auth/tier/permission checks
- **Cloud Functions:** `firebase/functions/src/index.ts` (Node.js) — email notifications via SendGrid, signed URL generation
- **Config:** `GoogleService-Info.plist`

## View Organization

Views are organized by feature in `PlayerPath/Views/`:

- `Views/Games/` — GameDetailView, GameRow, AddGameView, EditGameSheet, GameCreationView, VideoClipRow, ManualStatisticsEntryView, EmptyGamesView
- `Views/Profile/` — SettingsView, StorageSettingsView, EditAccountView, NotificationSettingsView, ChangePasswordView, AthleteManagementView, SubscriptionView, HelpSupportView, AccountDeletionView, DataExportView, StatisticsExportView
- `Views/Highlights/` — HighlightCard, SimpleCloudProgressView, SimpleCloudStorageView, AutoHighlightSettingsView, GameHighlightGroup
- `Views/Dashboard/` — DashboardView
- `Views/Navigation/` — MainTabView, AuthenticatedFlow
- `Views/Auth/` — ComprehensiveSignInView
- `Views/Onboarding/` — AthleteOnboardingFlow, CoachOnboardingFlow, OnboardingSeasonCreationView
- `Views/Components/` — EnhancedVideoPlayer, AthleteInvitationsBanner, UploadStatisticsView
- `Views/Search/` — AdvancedSearchView
- `Views/Stats/` — StatisticsChartsView
- `Views/Photos/` — PhotosView, PhotoDetailView, PhotoTagSheet
- `Views/Coach/` — InviteAthleteSheet
- `Views/Coaches/` — InviteCoachSheet

Main tab root views remain at the top level: `GamesView.swift`, `PracticesView.swift`, `ProfileView.swift`, `HighlightsView.swift`, `VideoClipsView.swift`, `StatisticsView.swift`.

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
