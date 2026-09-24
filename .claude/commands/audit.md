---
description: Re-scan PlayerPath for the 8 tracked code-quality categories and report deltas against the 2026-08-09 baseline, with file:line evidence and a severity per category.
argument-hint: "[category number, or blank for all]"
allowed-tools: Read, Grep, Glob, Bash
disable-model-invocation: true
---

Re-audit the codebase against the baseline below. For each category: report the current count, the delta from baseline, specific `file:line` evidence for what remains, any new instances, and a severity (Critical / High / Medium / Low).

If `$ARGUMENTS` names a category number, audit only that one. Otherwise do all 8.

**Measure, don't assume.** Every count below was taken by running a command against source — reproduce it, don't trust the number. Where a category lists its measurement command, run that exact command so the delta is comparable.

---

## Baseline — measured 2026-08-09

Repo at that moment: **536 Swift files, 128,651 lines.**

Six of the original ten categories were substantially closed between the March 2026 baseline and this one. They are listed under "Closed" at the bottom — **do not re-raise them without new evidence.**

---

### 1. `try?` on persistence and network paths

**291 occurrences** across the codebase (`grep -rno "try?" PlayerPath --include="*.swift" | wc -l`).

Not all are defects. The breakdown:
- 52 are `try? await Task.sleep` — benign, ignore them
- 66 are `try? FileManager…` — mostly cleanup/existence checks, judge case by case
- 12 are `try? JSON…` encode/decode
- 2 are `try? context.save()` — these ARE defects; the convention is `ErrorHandlerService.shared.saveContext(context, caller:)`

**Empty `catch {}` blocks: 0.** Every catch block now has at least a comment or a log line. This was ~15 in March. Do not report "swallowed errors" generically — the remaining question is narrower: *which `try?` sites drop an error that the user needed to know about?*

Highest-density files: `VideoStitchingService.swift` (10), `BulkVideoImportViewModel.swift` (8), `RecruitingPublishView.swift` (8), `VideoPlayerView.swift` (8), `CoachVideoUploadView.swift` (8).

Severity at baseline: **Medium.**

---

### 2. God objects

**6 files over 1,000 lines; 50 over 600.** The March list is obsolete — `GamesView` went 2,348 → 747, `ProfileView` 1,799 → 1,027, `PracticesView` 1,204 → 501, `Models.swift` ~1,300 → 698. Don't re-report those as unfixed.

The current offenders, largest first:

| File | Lines | Note |
|---|---|---|
| `CoachVideoPlayerView.swift` | 1,431 | new since March |
| `Services/UploadQueueManager.swift` | 1,412 | **grew from 792** — the worst regression in the repo |
| `CoachDashboardView.swift` | 1,142 | new |
| `PushNotificationService.swift` | 1,027 | new |
| `ProfileView.swift` | 1,027 | down from 1,799, still oversized |
| `VideoPlayerView.swift` | 1,016 | new |

Next tier (850–1,000): `CoachVideoPlayerViewModel` 998, `FirestoreModels` 965, `AdvancedSearchView` 957, `RecruitingPublishView` 955, `GameDetailView` 873, `StatisticsChartsView` 872, `CameraViewModel` 858, `CoachFolderDetailView` 853.

`UploadQueueManager` is the one to flag hardest: it still owns queue persistence, network monitoring, background tasks, retry/backoff, progress reporting, and quota — and it nearly doubled.

Severity at baseline: **High.**

---

### 3. Oversized view bodies

**96 view blocks of 100+ lines** (`var body: some View`, computed `some View` properties, and `-> some View` functions, measured by brace matching).

Worst:

| Block | Lines |
|---|---|
| `Views/Games/GameDetailView.swift:179` `body` | 458 |
| `CoachProfileView.swift:30` `body` | 352 |
| `SeasonDetailView.swift:75` `body` | 347 |
| `CoachVideoUploadView.swift:36` `body` | 268 |
| `Views/Games/GameCreationView.swift:140` `body` | 263 |
| `CoachDashboardView.swift:74` `body` | 262 |
| `Views/Athletes/UserMainFlow.swift:91` `body` | 244 |
| `Views/Dashboard/LiveGameCard.swift:170` `body` | 243 |
| `Views/Navigation/AuthenticatedFlow.swift:28` `body` | 237 |

This is now the largest category by instance count and the one with the clearest mechanical fix (extract subviews). `MainTabView.moreTab` and `EnhancedVideoPlayer.body` from the March list have both been cut below the threshold.

Severity at baseline: **High.**

---

### 4. Two color palettes coexist

**Measure this category by symbol name, never by a `DesignTokens.` prefix.** `DesignTokens.swift` defines *extensions on system types* (`CGFloat`, `CGSize`, `Font`, `Color`, `LinearGradient`, `View`, `Animation`), so every call site reads `.bodySmall` / `.spacingLarge` / `Color(hex:)` — never `DesignTokens.something`. A prefix grep returns 3 comment hits and looks like dead code. It is not: **1,525 real usages** outside the file. `Color(hex:)` alone has 23 call sites and `Theme/Theme.swift` is built on it. Deleting the file breaks the build.

The actual problem is that **two palettes are live at once**:
- `DesignTokens.swift` — `.brandNavy` (**197 uses** at 2026-09-23), `.brandGold` (34). The aliases `.brandPrimary`/`.brandSecondary`/`.premium`/`.premiumBackground` and the brand/button `LinearGradient` tokens were deleted 2026-09-23 — don't measure them.
- `Theme/Theme.swift` — the Calm Keepsake tokens, 619 references

`docs/PRICING_MODEL_V2_IMPLEMENTATION_PLAN.md` used to assert `brandNavy` was "removed in the seasons pass." It was not — 271 call sites remain. Corrected 2026-08-09.

The promo-video docs (`docs/superpowers/plans/2026-08-05-promo-video-pipeline.md:16,283`, `docs/superpowers/specs/2026-08-05-promo-video-pipeline-design.md:99`) say **deprecated**, which is accurate — don't "fix" those. Deprecated ≠ removed, and the distinction is the whole point: the symbols still resolve, so nothing fails loudly when someone reaches for one.

There is a matching **type scale** split: `Font+PlayerPath.swift`'s `.pp*` scale is canonical, but `DesignTokens`' legacy scale still outnumbers it roughly 6:1 — `.bodySmall` (286), `.headingMedium` (178), `.bodyMedium` (137), `.labelSmall` (95) vs ~150 `.pp*` font uses. High usage here means *the migration stalled*, not that the legacy scale is healthy.

The genuinely un-superseded primitives in that file — spacing, corner radii, thumbnail sizes, animation curves, `Color(hex:)` — are fine. Don't propose consolidating those.

**This is a migration-progress metric, not a defect list.** Report the ratio and which screens are still un-migrated. Do not propose a bulk find-and-replace: the legacy symbols are load-bearing in un-migrated screens, and a mechanical swap produces a half-reskinned app.

Related: a spacing scale exists (`.spacingSmall` 61 uses, `.spacingMedium` 34, `.spacingLarge` 35) but is swamped by **1,273 raw `spacing: N` literals** clustered on the same values it defines — 12 (234×), 8 (172×), 4 (147×), 6 (108×), 16 (102×). That is an adoption gap, not a missing abstraction.

Byte-size constants ARE centralized in `StorageConstants.swift`. Don't re-report those.

Severity at baseline: **Medium.**

---

### 5. Residual duplication

The big March items are fixed (see Closed). What's left:

- **13 `DateFormatter()` / `ISO8601DateFormatter()` instantiations outside `DateFormatters.swift`** — `GamesView:276`, `PhotoPersistenceService:65`, `StatisticsExportService:313`, `SecureURLManager:23`, `JournalFeedSections:94`, `Models/Season:66`, `DataExportView:13,530`, `RecruitingProfileService:582`, `ActivityNotificationService:97,103`, `AnalyticsService:17`, `CoachVideoUploadView:642`. Some are legitimately local (fixed-format export/ISO parsing); the display-facing ones should route through the shared extension.
- **5 header-drawing functions in `PDFReportGenerator.swift`** (`drawSectionHeader:255`, `drawTableHeader:328`, `drawGameLogHeader:354`, `drawSeasonGamesHeader:398`, `drawGolfRoundsHeader:545`). Check how much is still copy-paste vs genuinely different layouts.

Severity at baseline: **Low.**

---

### 6. `print()` vs OSLog

**35 `print()` calls in 14 files**, down from 244 in 28.

Crucially, `DebugPrint.swift` shadows `print(_:)` with a no-op under `#if !DEBUG`, so **nothing leaks in Release builds.** This is not a production-exposure problem — treat it as consistency only. The real cost: these bypass OSLog, so they can't be filtered by subsystem in Console.app alongside the 93 `Logger(subsystem:)` instances that 126 files use.

Remaining clusters: `GamesView` (4), `ComprehensiveSignInView` (5), `ReviewPromptManager` (5), `ComprehensiveAuthManager` (+`+Tier`) (5), `MainTabView` (2), `AnalyticsService` (2), `ErrorHandlerService` (2).

Severity at baseline: **Low.**

---

### 7. `ErrorHandlerService` layering

Adoption is real: **252 call sites across 115 files**, including 70 `saveContext` uses. The "no unified strategy" claim from March no longer holds.

Two residuals:
- `Services/ErrorHandlerService.swift` still mixes UI into a service: `@Published showErrorAlert`, `@Published currentError`, and `struct ErrorAlertModifier: ViewModifier` at line 218, all inside `Services/`. The presentation layer belongs in `Views/Shared/`.
- **59 raw `.localizedDescription` uses inside `Views/`** — raw `Error` text shown to users instead of the mapped, recovery-suggesting `AppError` copy. Plus 33 bare `Haptics.error(` calls; check which fire without any accompanying user-visible explanation.

Severity at baseline: **Medium.**

---

### 8. `nonisolated(unsafe)` audit

**27 occurrences** (21 declarations + 6 explanatory comments). Most are the documented, correct pattern: AVFoundation objects that must be touched from a capture queue (`CameraViewModel`, `PhotoCameraViewModel`, `AVExportSessionBox`, `VideoFileManager`), and Firestore `ListenerRegistration`s that `deinit` must call `.remove()` on (`CoachFolderViewModel:77`, `ReviewQueueViewModel:69`, `NotificationObserverManager:19`).

Don't flag these as a group. The audit question is per-site: **does each one still have a stated threading contract, and does the code honor it?** `PhotoCameraViewModel:44` has an explicit written contract — check whether the others do, and whether any new `nonisolated(unsafe)` was added without one.

One to look at: `Views/Navigation/MainTabView.swift:360` — `nonisolated(unsafe) let user = user` is a local rebinding, a different shape from the rest.

Severity at baseline: **Low.**

---

## Closed — do NOT re-raise without new evidence

These were live in March 2026 and were verified fixed on 2026-08-09.

- **Empty `catch {}` blocks.** 15 → 0.
- **Business logic in views.** **Zero** files under `Views/` touch `Firestore.firestore()` or `db.collection(` directly. The 12 that call `FirestoreManager.shared` are mostly ViewModels (`CoachInvitationsViewModel`, `CoachVideoPlayerViewModel`) where it belongs. `AthleteInvitationsBanner` went 118 lines of inline Firebase → 62 lines of pure view. `DashboardView`'s game-ending logic moved to `live.endGame(game, in:)`. `MainTabView`'s NotificationCenter block is down to 5 references.
- **Missing `[weak self]`.** All 5 `Timer.scheduledTimer` sites capture weakly or capture nothing (`EmailVerificationView:185` uses `{ _ in }`). Both class-based `addPeriodicTimeObserver` sites (`CoachVideoPlayerViewModel:406,589`) use `[weak self]`. The 3 remaining observers without it — `VideoPlayerView:405`, `PreUploadTrimmerView:408`, `EnhancedVideoPlayer:467` — are **inside SwiftUI structs, which have no `self` to retain. These are false positives. Do not report them.**
- **Unsafe threading (the March sites).** `SyncCoordinator` is `@MainActor`, so `pendingDownloadTasks` is isolated. `PDFReportGenerator` is `@MainActor`, so the `UIGraphics` work is safe. The static `DateFormatter` in `Models.swift` is gone.
- **Magic byte sizes.** Centralized in `StorageConstants.swift`.
- **Retry duplication.** Centralized in `Services/RetryHelpers.swift` (`withRetry` / `retryAsync`), 43 call sites.
- **Notification name strings.** Only 2 raw `Notification.Name("` outside `AppNotifications.swift`.
- **Duplicated search result cards.** `AdvancedSearchView` now uses a generic `SearchResultCard<Content: View>` wrapper (line 741).
- **Play-result badge colors.** Centralized on `PlayResultType.color` (`Models/PlayResultType.swift:151`).
- **`StatisticsService` duplication.** File is 252 lines with 3 distinct `recalculate*` methods; the ~50 shared lines are gone.

---

## Output format

Per category: current count, delta vs the 2026-08-09 baseline, `file:line` evidence, new instances, severity. Close with the three highest-leverage fixes and roughly what each would cost.

If a category now measures at zero, say so and propose moving it to Closed — then actually edit this file to record the new baseline and today's date, so the next run has honest numbers.
