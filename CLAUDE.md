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

`PlayerPathApp.swift` → `PlayerPathMainView` (defined in `MainAppView.swift`)

- **Unauthenticated:** → `WelcomeFlow` (in `Views/Auth/WelcomeFlow.swift`)
- **Authenticated:** → `AuthenticatedFlow` → `UserMainFlow` (in `Views/Athletes/UserMainFlow.swift`)

Two parallel tab bars based on user role:
- **Athletes:** `MainTabView` — Home, Games, Videos, Stats, More
- **Coaches:** `CoachTabView` — Dashboard, Athletes, Profile (managed by `CoachNavigationCoordinator`)

Athlete navigation uses `NavigationCoordinator` (Observable class) with deep linking via `DeepLinkIntent`. Coach navigation uses `CoachNavigationCoordinator` (Observable class, in `Views/Coach/CoachNavigationCoordinator.swift`).

Note: `ContentView.swift` exists but is dead code — `PlayerPathApp` goes directly to `PlayerPathMainView`.

### Data Layer

- **SwiftData** for local persistence. Schema is versioned (V1–V10) in `PlayerPathSchema.swift` with lightweight migrations only.
- **Firebase Firestore** for cloud sync and shared data (coach folders, invitations, clip metadata).
- **Local-first architecture**: `SyncCoordinator` handles bidirectional sync between SwiftData and Firestore using dirty flags and version numbers for conflict resolution.

### Core Model Hierarchy

`User → Athlete → Season → Game/Practice → VideoClip → PlayResult`

Core models are defined in `Models.swift` with additional model files in `PlayerPath/Models/` (`Athlete.swift`, `Season.swift`, `VideoClip.swift`, `Coach.swift`, `Photo.swift`, `AthleteStatistics.swift`, `PlayResultType.swift`, `AnnotationModels.swift`). Firestore data types are in `FirestoreModels.swift`.

### Key Services

Some services live in `PlayerPath/Services/`, others at the `PlayerPath/` top level:

**Top-level:**
- `SyncCoordinator` — SwiftData ↔ Firestore bidirectional sync
- `VideoCloudManager` — Firebase Storage uploads with progress tracking
- `ClipPersistenceService` — Local video file management
- `StoreKitManager` — Singleton (`StoreKitManager.shared`), `@MainActor`. Manages entitlements and subscription tiers
- `ComprehensiveAuthManager` — Firebase Auth (email/password + Apple Sign In) + biometric auth
- `SharedFolderManager` — Coach shared folder management with real-time Firestore listeners
- `BiometricAuthenticationManager` — Face ID/Touch ID session locking
- `PushNotificationService` — Push notification authorization and scheduling

**In `PlayerPath/Services/`:**
- `UploadQueueManager` — Background upload queue with exponential backoff retry (up to 10 retries)
- `ErrorHandlerService` — Centralized error handling with OSLog, error history, analytics, haptic feedback, and view helpers (`reportError`, `reportWarning`, `saveContext`)
- `AnalyticsService` — Firebase Analytics
- `StatisticsService` — Batting/pitching stats calculations
- `ConnectivityMonitor` — Network state observation
- `RetryHelpers` — `withRetry()` and `retryAsync()` for async retry-with-backoff
- `CoachSessionManager` — Live instruction session lifecycle and clip capture
- `CoachVideoProcessingService` — Coach-side video processing pipeline
- `CoachFolderArchiveManager` — Archiving/unarchiving coach folders
- `CoachInvitationManager` — Coach-initiated invitation flow
- `AthleteInvitationManager` — Athlete-initiated invitation flow
- `SubscriptionGateService` — Centralized subscription tier gate checks
- `CoachTemplateService` — Quick cue templates for coaches
- `ClipCommentService` — Video comment CRUD
- `ActivityNotificationService` — In-app activity notifications
- `OnboardingManager` — Onboarding flow state management
- `ReviewPromptManager` — App Store review prompt logic

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

Recording (athlete): `VideoRecorderView_Refactored.swift` → `CameraViewModel.swift` → `ModernCameraView.swift` (AVFoundation)
Recording (coach): `DirectCameraRecorderView.swift` — Standalone camera for session clip capture
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

Pro includes coach sharing. Plus+ includes auto highlights, stats export, season comparison.

**Coach tiers:**

| | Free | Instructor | Pro Instructor | Academy |
|---|---|---|---|---|
| Athletes | 2 | 10 | 30 | Unlimited |
| Monthly | — | $9.99 | $19.99 | Contact Us |
| Annual | — | $95.99 | $191.99 | Contact Us |

Academy is manually granted via Firestore — no StoreKit product exists for it.

Product IDs and feature gates are in `SubscriptionModels.swift`. StoreKit configuration file: `PlayerPathStoreKit.storekit`.

### Firebase Backend

- **Firestore collections:** `users/`, `sharedFolders/`, `videos/`, `invitations/`, `photos/`, `notifications/`, `coach_access_revocations/`, `coachTemplates/`, `coachSessions/`
- **Subcollections:** `videos/{id}/comments/`, `videos/{id}/annotations/`, `videos/{id}/drillCards/`, `users/{id}/athletes/`, `users/{id}/seasons/`, `users/{id}/games/`, `users/{id}/practices/`
- **Security rules:** `firestore.rules` (~500 lines) with helper functions for auth/tier/permission checks
- **Cloud Functions:** `firebase/functions/src/index.ts` (Node.js) — email notifications via SendGrid, signed URL generation
- **Config:** `GoogleService-Info.plist`

## View Organization

Views are organized by feature in `PlayerPath/Views/`:

- `Views/Athletes/` — UserMainFlow, AthleteSelectionView, AthleteCard, AddAthleteView, AthleteStatBadge
- `Views/Games/` — GameDetailView, GameRow, AddGameView, EditGameSheet, GameCreationView, VideoClipRow, ManualStatisticsEntryView, EmptyGamesView
- `Views/Profile/` — SettingsView, StorageSettingsView, EditAccountView, NotificationSettingsView, ChangePasswordView, AthleteManagementView, SubscriptionView, HelpSupportView, AccountDeletionView, DataExportView, StatisticsExportView
- `Views/Highlights/` — HighlightCard, SimpleCloudProgressView, SimpleCloudStorageView, AutoHighlightSettingsView, GameHighlightGroup
- `Views/Dashboard/` — DashboardView, DashboardStatCard, DashboardFeatureCard, DashboardNextStepCard, DashboardPremiumFeatureCard, DashboardVideoThumbnail, LiveGameCard, QuickActionButton
- `Views/Navigation/` — MainTabView, AuthenticatedFlow, KeyboardShortcuts
- `Views/Auth/` — ComprehensiveSignInView, WelcomeFlow, ResetPasswordSheet, RoleSelectionButton
- `Views/Onboarding/` — OnboardingFlow, AthleteOnboardingFlow, CoachOnboardingFlow, OnboardingSeasonCreationView, OnboardingStepIndicator, WelcomeTutorialView
- `Views/Components/` — EnhancedVideoPlayer, AthleteInvitationsBanner, UploadStatisticsView, ClipCommentSection, VideoClipCard, UploadStatusBanner
- `Views/Search/` — AdvancedSearchView
- `Views/Stats/` — StatisticsChartsView, BattingChartSection, PitchingStatsSection, DetailedStatsSection, KeyStatsSection, CareerSeasonComparisonSection, PlayResultsSection, EmptyStatisticsView, QuickStatisticsEntryView, ChartsPromptCard, GameSelectionForStatsView
- `Views/Photos/` — PhotosView, PhotoDetailView, PhotoTagSheet, PhotoThumbnailCell
- `Views/Coach/` — CoachTabView, CoachNavigationCoordinator, CoachAthletesTab, CoachDashboardComponents, CoachMultiAthleteView, StartSessionSheet, SessionAthletePickerOverlay, LiveSessionCard, ClipReviewSheet, DrillCardSummaryView, EnhancedAddNoteView, QuickCueManager, InviteAthleteSheet, CoachLimitPaywallSheet, CoachOverLimitBanner, VideoTagEditor, VideoTagFilterBar, QuickCueBar
- `Views/Coaches/` — InviteCoachSheet, ShareToCoachFolderView, CoachRow, AddCoachView, CoachDetailView

Main tab root views remain at the top level: `GamesView.swift`, `PracticesView.swift`, `ProfileView.swift`, `HighlightsView.swift`, `VideoClipsView.swift`, `StatisticsView.swift`.

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
