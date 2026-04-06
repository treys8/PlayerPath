# PlayerPath Architecture Overview

**Last Updated:** March 27, 2026

Comprehensive architecture reference for the PlayerPath iOS app. Covers app entry, navigation, data layer, services, video pipeline, and subscription system.

---

## App Entry & Bootstrap

**Entry:** `PlayerPathApp.swift` (`@main`)

Bootstrap sequence:
1. Configure SwiftData `ModelContainer` with `SchemaV14` (lightweight migrations only)
2. Initialize Firebase via `AppDelegate` (App Check enabled)
3. Inject environment objects: `ComprehensiveAuthManager`, `NavigationCoordinator`, `ThemeManager`
4. Register NotificationCenter observers for deep links and cross-feature navigation
5. Set up scene phase tracking (background sync, biometric lock)

**Root View:** `PlayerPathMainView` (in `MainAppView.swift`)

Routing logic:
```
ForceUpdateView         ← AppUpdateManager detects required update
AuthenticatedFlow       ← Signed in
EmailVerificationView   ← Email verification pending
LoadingView             ← Profile loading
WelcomeFlow             ← Not signed in
```

---

## Navigation Architecture

Three-layer model: Global Events -> Role Router -> Tab Navigation.

### Layer 1: Global Events (PlayerPathApp.swift)

`NavigationCoordinator` (`@Observable`) manages sheet/modal presentation and deep link intents (`DeepLinkIntent` enum: statistics, recordGame, recordPractice, invitation).

Cross-feature navigation uses `NotificationCenter`:
- `.switchTab` / `.switchAthlete` -- tab and athlete selection
- `.presentVideoRecorder`, `.presentSeasons`, `.presentCoaches` -- sheet triggers
- `.navigateToStatistics`, `.navigateToWeeklySummary` -- deep links
- `.showSubscriptionPaywall` -- global paywall
- `.navigateToCoachFolder`, `.openCoachInvitations` -- coach deep links

### Layer 2: Role Router (UserMainFlow.swift)

Routes based on user role and onboarding state:

| Condition | Destination |
|-----------|-------------|
| Coach role | `CoachTabView` |
| Athlete selection active | `AthleteSelectionView` |
| New user, no seasons | `OnboardingSeasonCreationView` |
| New user, has seasons | `OnboardingBackupView` |
| Resolved athlete | `MainTabView` |
| No athletes (new) | `AddAthleteView` |
| No athletes (syncing) | Loading spinner |

### Layer 3: Tab Navigation

**Athlete Tabs** (`MainTabView` -- 652 lines):

| Tab | View | Badge |
|-----|------|-------|
| Home | `DashboardView` | Pending invitations |
| Games | `GamesView` | -- |
| Videos | `VideoClipsView` | Unread activity |
| Stats | `StatisticsView` | -- |
| More | List-based nav | -- |

More tab uses `NavigationPath` for deep routing to: Practices, Highlights, Seasons, Photos, Coaches, Shared Folders.

Per-tab athlete IDs enable lazy refresh -- only the active tab updates immediately on athlete switch; inactive tabs defer via `refreshStaleTab()`.

**Coach Tabs** (`CoachTabView` -- 204 lines):

| Tab | View | Badge |
|-----|------|-------|
| Dashboard | `CoachDashboardView` | Unread notifications |
| Athletes | `CoachAthletesTab` | Unread folders + pending invitations |
| Profile | `CoachProfileView` | -- |

`CoachNavigationCoordinator` (`@Observable`) manages separate `NavigationPath` per tab, pending folder navigation with lazy resolution, and tab selection persistence.

Both tab views support iOS 18+ sidebar for regular horizontal size class.

### Key Environment Objects

- `ComprehensiveAuthManager` -- auth state, user role, profile
- `NavigationCoordinator` -- global navigation state (from PlayerPathApp)
- `CoachNavigationCoordinator` -- coach tab/path management (StateObject in CoachTabView)

---

## Data Layer

### SwiftData (Local Persistence)

**Schema:** `SchemaV14` with 14 lightweight migration stages (V1-V14). No custom migrations.

**15 SwiftData Models:**

| Model | Purpose |
|-------|---------|
| `User` | Root account with Firebase UID, subscription tier, cloud storage quota |
| `Athlete` | Athlete profile with Firestore sync metadata |
| `Season` | Seasonal grouping with sport type (baseball/softball) |
| `Game` | Game record with live tracking (`liveStartDate` for stale-game alerts) |
| `Practice` | Practice sessions with `practiceType` (general/batting/fielding/bullpen/team) |
| `PracticeNote` | Notes attached to practices |
| `VideoClip` | Video recordings with denormalized display fields, pitch type tracking |
| `PlayResult` | Single play outcome attached to a video clip |
| `Photo` | Photo records with cloud sync parity (version, isDeletedRemotely) |
| `Coach` | Coach contacts with Firebase account linking |
| `AthleteStatistics` | Career/season batting + pitching metrics |
| `GameStatistics` | Per-game stats including HBP, pitch counts |
| `UserPreferences` | Video quality, auto-upload mode, notification settings |
| `OnboardingProgress` | Per-user onboarding state |
| `PendingUpload` | Upload queue with coach-specific fields (isCoachUpload, folderID, sessionID) |

Core model hierarchy: `User -> Athlete -> Season -> Game/Practice -> VideoClip -> PlayResult`

Models defined in `Models.swift` + `PlayerPath/Models/` directory. Additional types: `PlayResultType` (16 result types), `SubscriptionTier`, `CoachSubscriptionTier`, `VideoQuality`, `AutoUploadMode`, `SessionStatus`, `AnnotationCategory`.

### Firebase Firestore (Cloud Sync)

**Local-first architecture:** `SyncCoordinator` handles bidirectional sync using dirty flags and version numbers. Extensions organized by entity: +Athletes, +Seasons, +Games, +Practices, +Videos, +PracticeNotes, +Photos, +Coaches.

See [FIREBASE_ARCHITECTURE_DIAGRAM.md](./FIREBASE_ARCHITECTURE_DIAGRAM.md) for full collection structure.

**12 Firestore Data Types** (in `FirestoreModels.swift`):
FirestoreAthlete, FirestoreSeason, FirestoreGame, FirestorePractice, FirestorePracticeNote, FirestorePhoto, FirestoreCoach, FirestoreVideoMetadata, SharedFolder, VideoAnnotation, CoachSession, UserProfile.

---

## Services Architecture

51 total services. All singletons use `static let shared`. Most are `@MainActor` isolated.

### Core Infrastructure

| Service | File | Pattern | Purpose |
|---------|------|---------|---------|
| `SyncCoordinator` | Top-level | Singleton, @Observable | SwiftData <-> Firestore bidirectional sync |
| `ComprehensiveAuthManager` | Top-level | Singleton, ObservableObject | Firebase Auth + biometric + role management |
| `FirestoreManager` | Top-level | Singleton, ObservableObject | All Firestore ops (7 extension files) |
| `StoreKitManager` | Top-level | Singleton, ObservableObject | StoreKit 2 subscriptions, entitlements |
| `ErrorHandlerService` | Services/ | Singleton, ObservableObject | OSLog, error history, analytics, haptics |
| `ConnectivityMonitor` | Services/ | Singleton, @Observable | NWPathMonitor for network state |
| `AnalyticsService` | Services/ | Singleton | Firebase Analytics + Crashlytics |
| `AppUpdateManager` | Services/ | Singleton, ObservableObject | Forced updates + "What's New" via Firestore config |

### Video Pipeline

| Service | File | Pattern | Purpose |
|---------|------|---------|---------|
| `VideoCloudManager` | Top-level | Singleton, ObservableObject | Firebase Storage uploads/downloads with progress |
| `ClipPersistenceService` | Top-level | Instantiable | Local video file management |
| `UploadQueueManager` | Services/ | Singleton, @Observable | Background upload queue (10 retries, exponential backoff) |
| `VideoCompressionService` | Top-level | Singleton | HEVC 1080p / H.264 720p compression (30-40% reduction) |
| `VideoFileManager` | Top-level | Static utility | Validation (500MB, 10min), thumbnail generation |
| `CoachVideoProcessingService` | Services/ | Singleton | Post-recording processing for coach clips |
| `CoachVideoCacheService` | Services/ | Singleton | Offline playback cache for coach shared folder videos |
| `SecureURLManager` | Top-level | Singleton | Time-limited URLs via Cloud Functions (direct HTTPS) |

### Coach System

| Service | File | Pattern | Purpose |
|---------|------|---------|---------|
| `SharedFolderManager` | Top-level | Singleton, @Observable | Folder CRUD, permissions, real-time listeners |
| `CoachSessionManager` | Services/ | Singleton, @Observable | Live instruction session lifecycle |
| `CoachInvitationManager` | Services/ | Singleton, @Observable | Real-time listener for athlete->coach invitations |
| `AthleteInvitationManager` | Services/ | Singleton, @Observable | Athlete-side invitation acceptance |
| `CoachFolderArchiveManager` | Services/ | Singleton, @Observable | Per-coach, per-device folder archiving |
| `CoachTemplateService` | Services/ | Singleton, @Observable | Quick cue and annotation templates |
| `CoachDowngradeManager` | Services/ | Singleton, @Observable | 7-day grace period, forced athlete selection |
| `AthleteDowngradeManager` | Services/ | Singleton, @Observable | Detects Pro tier loss, notifies coaches |
| `SubscriptionGateService` | Services/ | Static utility | Centralized coach tier limit checks |
| `CoachUploadableAthletesHelper` | Services/ | Static utility | Resolve uploadable athletes from folders |

### Athlete Features

| Service | File | Pattern | Purpose |
|---------|------|---------|---------|
| `StatisticsService` | Services/ | Singleton | Batting/pitching stats calculations |
| `ClipCommentService` | Services/ | Singleton | Unified video comment CRUD |
| `ActivityNotificationService` | Services/ | Singleton, ObservableObject | In-app notifications with real-time Firestore listeners |
| `OnboardingManager` | Services/ | Singleton, ObservableObject | Onboarding state and feature discovery |
| `GameService` | Top-level | Instantiable | Deep game deletion (videos, photos, stats, Firestore) |
| `SeasonManager` | Top-level | Static utility | Active season management |
| `OrphanedClipRecoveryService` | Services/ | Singleton | Recovers videos orphaned by schema changes |

### Utilities

| Service | File | Pattern | Purpose |
|---------|------|---------|---------|
| `PushNotificationService` | Top-level | Singleton, ObservableObject | FCM token, notification categories |
| `BiometricAuthenticationManager` | Top-level | Singleton, ObservableObject | Face ID / Touch ID |
| `AppleSignInManager` | Top-level | Singleton, ObservableObject | Apple Sign In with 5-min nonce expiration |
| `HapticManager` | Top-level | Singleton | Reusable UIFeedbackGenerator instances |
| `ProfileImageManager` | Top-level | Singleton | Profile image caching and storage |
| `PhotoPersistenceService` | Top-level | Instantiable | Photo saving, thumbnail generation |
| `StorageManager` | Top-level | Static utility | Device storage checks and warnings |
| `ReviewPromptManager` | Services/ | Singleton | App Store review prompt timing |
| `QuickActionsManager` | Services/ | Singleton, ObservableObject | iOS Home Screen Quick Actions |
| `RetryHelpers` | Services/ | Utility functions | `withRetry()` and `retryAsync()` |
| `PerformanceMonitor` | Services/ | Singleton, @Observable | Thumbnail cache hit/miss tracking |
| `PDFReportGenerator` | Services/ | Singleton | PDF statistics reports |
| `CSVExportService` | Services/ | Singleton | CSV statistics export |
| `StatisticsExportService` | Top-level | Static utility | Unified CSV/PDF export entry point |
| `GameAlertService` | Top-level | Singleton | Stale game local notifications |
| `VideoRecordingPermissionManager` | Top-level | Instantiable, ObservableObject | Camera/mic permissions |
| `VideoUploadService` | Top-level | Instantiable, ObservableObject | Photos picker video processing |
| `SampleDataGenerator` | Services/ | Static utility (DEBUG) | Sample data for new users |

See [SERVICES_QUICK_REFERENCE.md](../quick-reference/SERVICES_QUICK_REFERENCE.md) for the complete catalog.

---

## Video Pipeline

### Athlete Recording Flow

```
VideoRecorderView_Refactored
  -> CameraViewModel -> ModernCameraView (AVFoundation)
  -> PreUploadTrimmerView (optional)
  -> Play result tagging (PlayResultOverlayView)
  -> ClipPersistenceService (local save)
  -> UploadQueueManager (background queue)
  -> VideoCompressionService (HEVC 1080p)
  -> VideoCloudManager -> Firebase Storage
  -> FirestoreManager.uploadVideoMetadata()
```

### Coach Recording Flow (Live Sessions)

```
DirectCameraRecorderView (coachContext)
  -> ModernCameraView + "LIVE SESSION" badge
  -> PreUploadTrimmerView (skip if <15s)
  -> SessionAthletePickerOverlay (multi-athlete)
  -> CoachSessionManager.uploadClip()
  -> Copy to coach_pending_uploads/
  -> UploadQueueManager.enqueueCoachUpload()
  -> CoachVideoProcessingService (thumbnail)
  -> Firebase Storage + Firestore metadata
```

See [COACH_SESSION_ARCHITECTURE.md](./COACH_SESSION_ARCHITECTURE.md) for full session lifecycle.

### Upload Queue

`UploadQueueManager` manages retries with exponential backoff:
5s -> 15s -> 1m -> 2m -> 5m -> 10m -> 15m -> 30m -> 1hr (10 retries max).
Supports background tasks and persists queue via SwiftData `PendingUpload` model.

### Playback

- **Athlete videos:** `VideoPlayerView` with `PlayResultOverlayView` for tagging
- **Coach shared videos:** `CoachVideoPlayerView` with annotations, drill cards, comments
- **Secure URLs:** `SecureURLManager` generates time-limited URLs via Cloud Functions (24hr videos, 7-day thumbnails)

---

## Subscription System

### Athlete Tiers

| Tier | Athletes | Storage | Coach Sharing | Price |
|------|----------|---------|---------------|-------|
| Free | 1 | 2 GB | No | -- |
| Plus | 3 | 25 GB | No | $4.99/mo |
| Pro | 5 | 100 GB | Yes | $9.99/mo |

### Coach Tiers

| Tier | Athletes | Price |
|------|----------|-------|
| Free | 2 | -- |
| Instructor | 10 | $9.99/mo |
| Pro Instructor | 30 | $19.99/mo |
| Academy | Unlimited | Manual Firestore grant |

Product IDs and feature gates in `SubscriptionModels.swift`. StoreKit config: `PlayerPathStoreKit.storekit`.

### Key Implementation Details

- `StoreKitManager.shared` manages entitlements for both athlete and coach tiers
- `hasResolvedEntitlements` flag prevents stale tier syncs
- `SubscriptionGateService` (static utility) enforces coach athlete limits
- `CoachDowngradeManager` provides 7-day grace period before forced athlete selection
- `AthleteDowngradeManager` detects Pro tier loss and notifies coaches
- Tier sync to Firestore via `syncSubscriptionTier` Cloud Function

---

## View Organization

173 total view files: 140 in `PlayerPath/Views/` (19 subdirectories) + 33 at top level.

### Views/ Directory (by size)

| Directory | Files | Key Views |
|-----------|-------|-----------|
| Coach/ | 26 | CoachTabView, CoachAthletesTab, StartSessionSheet, LiveSessionCard, ClipReviewSheet, DrillCardView, tier management views |
| Stats/ | 11 | StatisticsChartsView, BattingChartSection, PitchingStatsSection, CareerSeasonComparisonSection |
| Components/ | 10 | EnhancedVideoPlayer, ClipCommentSection, VideoClipCard, GameLinkerView, RemoteThumbnailView |
| Shared/ | 11 | Design system: EmptyStateView, ErrorView, ModernTextField, SkeletonLoadingView, ScaleButtonStyle, StatusChip |
| Profile/ | 11 | SettingsView, SubscriptionView, AccountDeletionView, DataExportView, StorageSettingsView |
| Dashboard/ | 8 | DashboardView, DashboardStatCard, LiveGameCard, QuickActionButton |
| Games/ | 8 | GameDetailView, AddGameView, ManualStatisticsEntryView |
| Onboarding/ | 8 | OnboardingFlow, AthleteOnboardingFlow, CoachOnboardingFlow, CoachAnnouncementFlow |
| Auth/ | 7 | WelcomeFlow, ComprehensiveSignInView, EmailVerificationView, ForceUpdateView |
| Athletes/ | 5 | UserMainFlow, AthleteSelectionView, AthleteCard |
| Coaches/ | 5 | InviteCoachSheet, ShareToCoachFolderView, CoachDetailView |
| Help/ | 5 | HelpView, FAQView, GettingStartedView |
| Highlights/ | 5 | HighlightCard, SimpleCloudStorageView, GameHighlightGroup |
| Practices/ | 5 | PracticeDetailView, PracticeCard, AddPracticeNoteView |
| Photos/ | 4 | PhotosView, PhotoDetailView |
| Settings/ | 4 | VideoQualityPickerView (new quality tuning feature) |
| Navigation/ | 3 | MainTabView, AuthenticatedFlow, KeyboardShortcuts |
| Legal/ | 2 | PrivacyPolicyView, TermsOfServiceView |
| Search/ | 1 | AdvancedSearchView |

### Top-Level View Files (33 files)

**Tab roots:** GamesView, HighlightsView, PracticesView, ProfileView, StatisticsView, VideoClipsView

**Coach views:** CoachDashboardView, CoachFolderDetailView, CoachInvitationsView, CoachPaywallView, CoachProfileView, CoachVideoPlayerView, CoachVideoUploadView, CoachesView, DirectCameraRecorderView

**Other:** AthleteFoldersListView, BiometricSettingsView, CreateFolderView, ImprovedPaywallView, LoadingView, MainAppView, ModernCameraView, PlayResultOverlayView, PracticeVideoSaveView, SeasonComparisonView, SeasonIndicatorView, SeasonManagementView, SeasonsView, UserPreferencesView, VideoPlayerView, VideoRecordingOptionsView, VideoRecordingSettingsView, VideoThumbnailView, ViewsComponentsLoadingView

---

## Error Handling Conventions

- **Services:** OSLog `Logger` instances with subsystem `"com.playerpath.app"`
- **Views:** `ErrorHandlerService.shared.reportError()` / `reportWarning()`
- **SwiftData saves:** `ErrorHandlerService.shared.saveContext(context, caller:)`
- **Async retry:** `retryAsync { }` (fire-and-forget) or `try await withRetry { }` (with result)

---

## Key Conventions

- `@MainActor` isolation on ViewModels and services
- `@Observable` (Swift Observation) for all ViewModels
- Singletons via `static let shared`
- Bundle ID: `RZR.DT3`
- `DateFormatters.swift` for centralized date formatting
- `AppNotifications.swift` for `Notification.Name` constants
- `DesignTokens.swift` for design system constants
- `FirestoreCollections.swift` for collection name constants
