# PlayerPath Documentation

**Last Updated:** March 27, 2026

---

## Architecture

System design, data models, and architectural decisions.

- **[ARCHITECTURE_OVERVIEW.md](./architecture/ARCHITECTURE_OVERVIEW.md)** -- Comprehensive reference: app entry, navigation, data layer, 51 services, video pipeline, subscriptions, view organization
- **[COACH_SESSION_ARCHITECTURE.md](./architecture/COACH_SESSION_ARCHITECTURE.md)** -- Live instruction session lifecycle, clip capture, review flow, dashboard integration
- **[FIREBASE_ARCHITECTURE_DIAGRAM.md](./architecture/FIREBASE_ARCHITECTURE_DIAGRAM.md)** -- Firestore collections (9 top-level + subcollections), Storage structure, 14 Cloud Functions, security rules
- **[COACH_SHARING_ARCHITECTURE.md](./architecture/COACH_SHARING_ARCHITECTURE.md)** -- Coach sharing system: folders, permissions, bidirectional invitations
- **[SEASON_DATA_MODEL_DIAGRAM.md](./architecture/SEASON_DATA_MODEL_DIAGRAM.md)** -- Season, Game, Practice data relationships
- **[GAMES_PRACTICES_STRUCTURE_GUIDE.md](./architecture/GAMES_PRACTICES_STRUCTURE_GUIDE.md)** -- Game and practice management architecture

---

## Quick Reference

Concise reference cards for common tasks.

- **[SERVICES_QUICK_REFERENCE.md](./quick-reference/SERVICES_QUICK_REFERENCE.md)** -- Complete catalog of all 51 services with isolation, singleton status, responsibilities
- **[VIDEO_UPLOAD_QUICK_REFERENCE.md](./quick-reference/VIDEO_UPLOAD_QUICK_REFERENCE.md)** -- Upload pipelines (athlete + coach), compression, secure URLs, storage paths
- **[SUBSCRIPTION_QUICK_REFERENCE.md](./quick-reference/SUBSCRIPTION_QUICK_REFERENCE.md)** -- Tier structure, gate APIs, downgrade handling, sync flow
- **[NAVIGATION_QUICK_REFERENCE.md](./quick-reference/NAVIGATION_QUICK_REFERENCE.md)** -- Tab structure, navigation helpers, programmatic navigation, coordinators

---

## Implementation Summaries

Feature implementations and fix summaries (chronological).

- **[IMPLEMENTATION_SUMMARY_12_21_25.md](./implementation/IMPLEMENTATION_SUMMARY_12_21_25.md)** -- Dec 2025: video trimming, editable play results, annotations, stats export, search
- **[COACH_DASHBOARD_SUMMARY.md](./implementation/COACH_DASHBOARD_SUMMARY.md)** -- Coach dashboard implementation
- **[STOREKIT_IMPLEMENTATION_SUMMARY.md](./implementation/STOREKIT_IMPLEMENTATION_SUMMARY.md)** -- StoreKit 2 subscriptions
- **[EMAIL_NOTIFICATIONS_IMPLEMENTATION_SUMMARY.md](./implementation/EMAIL_NOTIFICATIONS_IMPLEMENTATION_SUMMARY.md)** -- SendGrid email notifications
- **[HIGHLIGHTS_GROUPING_IMPLEMENTATION.md](./implementation/HIGHLIGHTS_GROUPING_IMPLEMENTATION.md)** -- Video highlights grouping
- **[SEASON_MANAGEMENT_IMPLEMENTATION.md](./implementation/SEASON_MANAGEMENT_IMPLEMENTATION.md)** -- Season management
- **[IMPLEMENTATION_COMPLETE_SUMMARY.md](./implementation/IMPLEMENTATION_COMPLETE_SUMMARY.md)** -- Nov 2025 major features
- **[ISSUE_FIXES_12_7_25.md](./implementation/ISSUE_FIXES_12_7_25.md)** -- Dec 7 bug fixes

---

## Setup Guides

Step-by-step configuration guides.

**Firebase:**
- **[FIREBASE_SETUP_GUIDE.md](./setup-guides/FIREBASE_SETUP_GUIDE.md)** -- Auth, Firestore, Storage
- **[FIREBASE_EMAIL_SETUP_GUIDE.md](./setup-guides/FIREBASE_EMAIL_SETUP_GUIDE.md)** -- Cloud Functions + SendGrid

**StoreKit:**
- **[STOREKIT_SETUP_GUIDE.md](./setup-guides/STOREKIT_SETUP_GUIDE.md)** -- In-app purchases

**iOS:**
- **[INFO_PLIST_GUIDE.md](./setup-guides/INFO_PLIST_GUIDE.md)** -- Info.plist configuration
- **[BUILD_NUMBER_SETUP.md](./setup-guides/BUILD_NUMBER_SETUP.md)** -- Build versioning

**Deployment:**
- **[iOS_SANDBOX_GUIDE.md](./setup-guides/iOS_SANDBOX_GUIDE.md)** -- Sandbox permissions
- **[SANDBOX_FIX_GUIDE.md](./setup-guides/SANDBOX_FIX_GUIDE.md)** -- Sandbox troubleshooting
- **[TESTFLIGHT_ARCHIVE_FIX.md](./setup-guides/TESTFLIGHT_ARCHIVE_FIX.md)** -- TestFlight builds

---

## Archive

Historical documentation, old fixes, and deprecated guides. See [archive/](./archive/).

---

## Finding What You Need

| Question | Start Here |
|----------|-----------|
| Understand the full architecture | [ARCHITECTURE_OVERVIEW.md](./architecture/ARCHITECTURE_OVERVIEW.md) |
| How do coach sessions work? | [COACH_SESSION_ARCHITECTURE.md](./architecture/COACH_SESSION_ARCHITECTURE.md) |
| Firebase collections and rules | [FIREBASE_ARCHITECTURE_DIAGRAM.md](./architecture/FIREBASE_ARCHITECTURE_DIAGRAM.md) |
| What services exist? | [SERVICES_QUICK_REFERENCE.md](./quick-reference/SERVICES_QUICK_REFERENCE.md) |
| How does video upload work? | [VIDEO_UPLOAD_QUICK_REFERENCE.md](./quick-reference/VIDEO_UPLOAD_QUICK_REFERENCE.md) |
| Subscription tiers and gating | [SUBSCRIPTION_QUICK_REFERENCE.md](./quick-reference/SUBSCRIPTION_QUICK_REFERENCE.md) |
| Navigation patterns | [NAVIGATION_QUICK_REFERENCE.md](./quick-reference/NAVIGATION_QUICK_REFERENCE.md) |
| Set up Firebase | [FIREBASE_SETUP_GUIDE.md](./setup-guides/FIREBASE_SETUP_GUIDE.md) |
| Configure subscriptions | [STOREKIT_SETUP_GUIDE.md](./setup-guides/STOREKIT_SETUP_GUIDE.md) |
| Fix a TestFlight build | [TESTFLIGHT_ARCHIVE_FIX.md](./setup-guides/TESTFLIGHT_ARCHIVE_FIX.md) |

---

## Project Status

**Version:** V1 submitted March 25, 2026. Coach role launch pending.
**Schema:** V14 (14 lightweight migrations)
**Services:** 51 total
**Views:** 173 files (140 in Views/ + 33 top-level)
**Firestore Collections:** 9 top-level + 12 subcollection types
**Cloud Functions:** 14 (10 triggers + 4 callable)

### Core Features
- Athlete profile management with multi-athlete support
- Game and practice tracking with live game detection
- Video recording with play-by-play tagging and pitch types
- Pre-upload video trimming and HEVC compression
- Coach sharing system with bidirectional invitations
- Live instruction sessions with clip capture and review
- Statistics tracking (batting + pitching) with CSV/PDF export
- Tiered subscriptions (3 athlete + 4 coach tiers)
- SwiftData <-> Firestore bidirectional sync
- Push notifications, biometric auth, offline support

---

**Last Documentation Refresh:** March 27, 2026
**Active Documents:** 22
**Archived Documents:** 41
