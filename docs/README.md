# PlayerPath Documentation

**Last Updated:** June 24, 2026

PlayerPath is a **dual-sport** iOS performance-tracking app: **baseball/softball** (game/practice video, play-by-play tagging, batting/pitching stats) **and golf** (round/tournament scoring, per-hole and shot-by-shot stats, birdie auto-highlight reels). A person who plays two sports is modeled as two `Athlete` rows linked by a shared `personGroupID`, counting as **one subscription slot**.

---

## Architecture

System design, data models, and architectural decisions.

- **[ARCHITECTURE_OVERVIEW.md](./architecture/ARCHITECTURE_OVERVIEW.md)** -- Comprehensive reference: app entry, navigation, data layer, services, video pipeline, subscriptions, view organization
- **[COACH_SESSION_ARCHITECTURE.md](./architecture/COACH_SESSION_ARCHITECTURE.md)** -- Live instruction session lifecycle, clip capture, review flow, dashboard integration
- **[FIREBASE_ARCHITECTURE_DIAGRAM.md](./architecture/FIREBASE_ARCHITECTURE_DIAGRAM.md)** -- Firestore collections + subcollections, Storage structure, Cloud Functions, security rules
- **[SEASON_DATA_MODEL_DIAGRAM.md](./architecture/SEASON_DATA_MODEL_DIAGRAM.md)** -- Season, Game, Practice (and golf Round/Tournament) data relationships
- **[NOTIFICATIONS_ARCHITECTURE.md](./architecture/NOTIFICATIONS_ARCHITECTURE.md)** -- Push + in-app activity notification system

---

## Quick Reference

Concise reference cards for common tasks.

- **[SERVICES_QUICK_REFERENCE.md](./quick-reference/SERVICES_QUICK_REFERENCE.md)** -- Catalog of services with isolation, singleton status, responsibilities
- **[VIDEO_UPLOAD_QUICK_REFERENCE.md](./quick-reference/VIDEO_UPLOAD_QUICK_REFERENCE.md)** -- Upload pipelines (athlete + coach), compression, secure URLs, storage paths
- **[SUBSCRIPTION_QUICK_REFERENCE.md](./quick-reference/SUBSCRIPTION_QUICK_REFERENCE.md)** -- Tier structure, gate APIs, downgrade handling, sync flow
- **[NAVIGATION_QUICK_REFERENCE.md](./quick-reference/NAVIGATION_QUICK_REFERENCE.md)** -- Tab structure, navigation helpers, programmatic navigation, coordinators

---

## Product & Planning

Pricing, positioning, and roadmap documents (in `docs/` root).

- **[PRICING_MODEL_V2_PROPOSAL.md](./PRICING_MODEL_V2_PROPOSAL.md)** -- Pricing V2 rationale: coach pays the per-seat connection, any athlete tier can share
- **[PRICING_MODEL_V2_IMPLEMENTATION_PLAN.md](./PRICING_MODEL_V2_IMPLEMENTATION_PLAN.md)** -- Phased implementation plan for the Pricing V2 pivot
- **[MARKETING_BRIEF.md](./MARKETING_BRIEF.md)** -- Positioning, audience, and messaging brief
- **[RECRUITING_PROFILE_PLAN.md](./RECRUITING_PROFILE_PLAN.md)** -- Plan for athlete recruiting profiles
- **[web-portal-handoff.md](./web-portal-handoff.md)** -- Web portal scope and handoff notes

---

## Design Specs

- **[2026-06-21-unified-golf-hole-scoring-design.md](./superpowers/specs/2026-06-21-unified-golf-hole-scoring-design.md)** -- Unified golf hole-scoring data model and UI design

---

## Setup Guides

Step-by-step configuration guides.

**Firebase:**
- **[FIREBASE_SETUP_GUIDE.md](./setup-guides/FIREBASE_SETUP_GUIDE.md)** -- Auth, Firestore, Storage
- **[FIREBASE_EMAIL_SETUP_GUIDE.md](./setup-guides/FIREBASE_EMAIL_SETUP_GUIDE.md)** -- Cloud Functions + SendGrid

**iOS:**
- **[INFO_PLIST_GUIDE.md](./setup-guides/INFO_PLIST_GUIDE.md)** -- Info.plist configuration
- **[BUILD_NUMBER_SETUP.md](./setup-guides/BUILD_NUMBER_SETUP.md)** -- Build versioning

**Deployment:**
- **[TESTFLIGHT_ARCHIVE_FIX.md](./setup-guides/TESTFLIGHT_ARCHIVE_FIX.md)** -- TestFlight builds

---

## Archive

Historical documentation, dated implementation summaries, old fixes, and deprecated guides now live in [archive/](./archive/). This includes the former `implementation/` folder (StoreKit, coach dashboard, email notifications, highlights grouping, season management, and other chronological summaries) plus archived architecture/setup docs (COACH_SHARING_ARCHITECTURE, GAMES_PRACTICES_STRUCTURE_GUIDE, STOREKIT_SETUP_GUIDE, sandbox guides, etc.).

---

## Finding What You Need

| Question | Start Here |
|----------|-----------|
| Understand the full architecture | [ARCHITECTURE_OVERVIEW.md](./architecture/ARCHITECTURE_OVERVIEW.md) |
| How do coach sessions work? | [COACH_SESSION_ARCHITECTURE.md](./architecture/COACH_SESSION_ARCHITECTURE.md) |
| Firebase collections and rules | [FIREBASE_ARCHITECTURE_DIAGRAM.md](./architecture/FIREBASE_ARCHITECTURE_DIAGRAM.md) |
| How does golf scoring work? | [2026-06-21-unified-golf-hole-scoring-design.md](./superpowers/specs/2026-06-21-unified-golf-hole-scoring-design.md) |
| What services exist? | [SERVICES_QUICK_REFERENCE.md](./quick-reference/SERVICES_QUICK_REFERENCE.md) |
| How does video upload work? | [VIDEO_UPLOAD_QUICK_REFERENCE.md](./quick-reference/VIDEO_UPLOAD_QUICK_REFERENCE.md) |
| Subscription tiers and gating | [SUBSCRIPTION_QUICK_REFERENCE.md](./quick-reference/SUBSCRIPTION_QUICK_REFERENCE.md) |
| Why coaches pay per seat (Pricing V2) | [PRICING_MODEL_V2_PROPOSAL.md](./PRICING_MODEL_V2_PROPOSAL.md) |
| Navigation patterns | [NAVIGATION_QUICK_REFERENCE.md](./quick-reference/NAVIGATION_QUICK_REFERENCE.md) |
| Set up Firebase | [FIREBASE_SETUP_GUIDE.md](./setup-guides/FIREBASE_SETUP_GUIDE.md) |
| Fix a TestFlight build | [TESTFLIGHT_ARCHIVE_FIX.md](./setup-guides/TESTFLIGHT_ARCHIVE_FIX.md) |

---

## Project Status

**Version:** v6.1.2 (build 189), shipping. Coach role launched (v5.0); dual-sport (baseball/softball + golf) live.
**Schema:** SchemaV30 (lightweight migrations only)
**Services:** ~60 (≈58 in `Services/` + top-level managers)
**Views:** ~300 files (254 in `Views/` + ~44 top-level)
**Firestore Collections:** ~12 top-level (incl. `golfTournaments`, `highlightReels`) + subcollections (`holes`, `shots`, comments, annotations, drillCards, etc.)
**Cloud Functions:** ~32 exported (triggers + callable)
**firestore.rules:** ~950 lines

### Core Features
- Dual-sport: baseball/softball **and** golf, with two-sport persons linked by `personGroupID` (one subscription slot)
- Athlete profile management with multi-athlete support
- Game and practice tracking with live game detection
- Golf round/tournament scoring with per-hole and shot-by-shot stats
- Video recording with play-by-play tagging and pitch types
- Pre-upload video trimming and HEVC compression
- Auto-highlight reels (incl. golf birdie reels)
- Coach sharing system with bidirectional invitations and live instruction sessions
- Statistics tracking (batting + pitching) with CSV/PDF export
- Tiered subscriptions (Pricing V2: 3 athlete + 4 coach tiers; coaches pay per-seat for connections, so any athlete tier can share with a coach)
- SwiftData <-> Firestore bidirectional sync
- Push notifications and offline support

---

**Last Documentation Refresh:** June 24, 2026
**Live Documents:** 21 (everything else moved to `archive/`)
