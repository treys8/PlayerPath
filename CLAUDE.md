# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PlayerPath is an iOS baseball/softball performance tracking app (SwiftUI, iOS 17+). Athletes record game videos with play-by-play tagging, track statistics across seasons, and share clips with coaches for annotated feedback. Monetized via StoreKit 2 subscriptions.

## Build & Run

This is an Xcode project — there is no SPM Package.swift or Podfile. Open `PlayerPath.xcodeproj` in Xcode 15+.

```bash
# Build from command line
xcodebuild -project PlayerPath.xcodeproj -scheme PlayerPath -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' build

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

Models are defined in `Models.swift` (~46KB). Supporting types: `AthleteStatistics`, `GameStatistics`, `Coach`, `Photo`.

### Key Services (in `PlayerPath/Services/`)

- `SyncCoordinator` — SwiftData ↔ Firestore bidirectional sync
- `VideoCloudManager` — Firebase Storage uploads with progress tracking
- `UploadQueueManager` — Background upload queue with exponential backoff retry (up to 10 retries)
- `ClipPersistenceService` — Local video file management
- `StoreKitManager` — Singleton (`StoreKitManager.shared`), `@MainActor`. Manages entitlements and subscription tiers
- `ComprehensiveAuthManager` — Firebase Auth (email/password + Apple Sign In) + biometric auth
- `ErrorHandlerService` — Centralized error handling with OSLog
- `AnalyticsService` — Firebase Analytics
- `StatisticsService` — Batting/pitching stats calculations
- `ConnectivityMonitor` — Network state observation

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

## Key Conventions

- `@MainActor` isolation is used extensively for thread safety on ViewModels and services
- All ViewModels use `@Observable` (Swift Observation framework)
- Singletons use `static let shared` pattern (e.g., `StoreKitManager.shared`)
- Bundle ID: `RZR.DT3`

## Documentation

Extensive docs live in `/docs/` organized by: `architecture/`, `implementation/`, `setup-guides/`, `quick-reference/`. Start with `docs/README.md` for navigation.
