# Review Prompt — Coach Review Surface Refactor (2026-06-06)

Paste the block below into a fresh Claude Code terminal in this repo to do an independent, adversarial review of the uncommitted coach video-review refactor. It is written to be picked up cold.

---

Do a fresh, adversarial code review of an uncommitted refactor on the coach video-review flow. Assume the author may be wrong — verify against the actual code, don't trust this description. Read full files, not just diffs around the hunks. Do NOT make code changes; produce a findings report (correctness bugs first, then risks/edge cases, then nits).

## Product context (ground truth)
PlayerPath is a SwiftUI/SwiftData + Firebase iOS app. Coach flow: coach starts a live session → records clips → they upload as `visibility:"private"` into the coach's "My Drafts" tab of a lessons folder → coach reviews (note/cues/telestration drawings/drill cards) → publishes to the athlete. Athletes also share game videos into a coach folder (`visibility:"shared"` on arrival, "Needs My Review"); the coach marks those up in the same player. Feedback is one-way (athlete read-only). The ONLY thing that makes a clip + feedback visible to the athlete is publishing (`visibility` private→shared, which fires the `onVideoPublished` Cloud Function push). `reviewedBy` is coach-side bookkeeping that nothing athlete-facing reads. Markups are intentionally editable; Publish is the "sent" boundary.

## What the refactor claims to do
1. **Unify the coach review surface + fix a "silent never delivered" footgun.** Previously a coach's private DRAFT could open in `CoachVideoPlayerView`, which had NO publish button (publish was only on the old `ClipReviewSheet` and the folder "Share All"). A coach could write a note + tap "Done reviewing" (which only writes `reviewedBy`, auto-set on open anyway) and the athlete would never receive it, because the note/drill CFs early-return on `visibility=='private'`. The fix: `CoachVideoPlayerView` now shows a draft publish bar (Share Now / Save for Later / Discard) when `isOwnPrivateDraft` (`video.visibility=="private" && video.uploadedBy==userID`), and HIDES "Done reviewing" on drafts. The folder's My-Drafts cover now presents `CoachVideoPlayerView` instead of `ClipReviewSheet`. `ClipReviewSheet.swift`, `Review/ClipReviewDrillSection.swift`, `Review/ClipReviewTelestrationSection.swift` were deleted; `Review/ClipReviewPublishBar.swift` is reused. `CoachFeedbackCard.onDone` was made optional.
2. **Drill cards editable + deletable** (they were accidentally one-time). Added `FirestoreManager.deleteDrillCard`; `DrillCardSummaryView` got an ellipsis Edit/Delete menu (coach-only); `DrillCardTabView` threads `onEdit`/`onDelete`; `CoachVideoPlayerView` wires an edit sheet (`editingDrillCard` via `.sheet(item:)`) + delete confirmation.
3. **Session "Complete" warns on unshared drafts.** `CoachDashboardView.completeActiveSession` checks `unpublishedDrafts(for:)` (reads `ReviewQueueViewModel.shared.groupedClips` filtered to `session.folderIDs.values`); if any, a confirmationDialog offers "Publish N & Complete" / "Complete Without Sharing" / Cancel.

## Files changed this session
M PlayerPath/CoachVideoPlayerView.swift   (largest — body was split into playerBody/runInitialLoad/trailingToolbarButtons to beat the SwiftUI type-checker; also added draft bar + drill edit/delete)
M PlayerPath/CoachFolderDetailView.swift  (My-Drafts cover now wraps CoachVideoPlayerView in a NavigationStack)
M PlayerPath/CoachDashboardView.swift     (complete-with-drafts warning)
M PlayerPath/FirestoreManager+DrillCards.swift (deleteDrillCard)
M PlayerPath/Views/Coach/DrillCardSummaryView.swift (Edit/Delete menu)
M PlayerPath/Views/Coach/Review/DrillCardTabView.swift (onEdit/onDelete passthrough)
M PlayerPath/Views/Coach/CoachFeedbackCard.swift (onDone optional)  ← note: this file is also new/uncommitted from a PRIOR session; only the onDone change is from this refactor
D PlayerPath/Views/Coach/ClipReviewSheet.swift (+ 2 ClipReview* sections)
(Other M/?? files in `git status` — CoachVideoPlayerViewModel, CoachVideoSidebar, etc. — predate this refactor; ignore unless they interact.)

## Things I most want independently verified (find holes in these)
1. **The footgun-fix invariant.** I claimed `isOwnPrivateDraft` is only ever true inside the My-Drafts `.fullScreenCover(item:$reviewingClip)` (which passes onDraftShared/onDraftDiscarded/onDraftSavedForLater). If a private draft can reach `CoachVideoPlayerView` via ANY other path (e.g. a `CoachFolderComponents` NavigationLink, a notification deep-link, the dashboard "Needs Review", a games folder) the publish bar would appear WITHOUT those callbacks → on success it calls `onDraftShared?()` (no-op) and never resets `isPublishingDraft`/dismisses → stuck spinner + clip published but UI frozen. Enumerate EVERY `CoachVideoPlayerView(` call site and prove, per site, whether the clip can be a coach's own private draft.
2. **Publish drops nothing.** `shareDraftNow` calls `publishPrivateVideo(videoID:sharedFolderID:)` with `notes:nil`, relying on the note already being persisted (the player edits the note via CoachNoteEditorSheet → `setCoachNote`, and cues via `updateVideoTags` autosave). Confirm a coach who types a note then immediately taps Share Now actually keeps the note (no unsaved-draft-text loss vs the old ClipReviewSheet, whose note field only persisted on Share/Save-for-Later). Pay attention to in-flight edits / sheet-still-open timing.
3. **Environment propagation in the cover.** `CoachVideoPlayerView` uses `@EnvironmentObject authManager`, `@Environment(\.modelContext)`, `@Environment(CoachNavigationCoordinator.self)`, `@Environment(\.ppAccent)`, etc. Verify all required environment is present when presented in the My-Drafts `fullScreenCover` (the old ClipReviewSheet only needed authManager). Will anything crash (`EnvironmentObject ... missing`) or silently get a default (modelContext)?
4. **Drill delete/edit.** Verify `deleteDrillCard` is permitted by `firestore.rules` for the acting coach, that no denormalized count (like `drawingCount`) needs decrementing, that the local `drillCards` array stays in sync after edit AND delete, and that the menu never shows for the athlete (folder owner).
5. **Session-complete warning correctness.** `unpublishedDrafts(for:)` depends on `ReviewQueueViewModel.shared` (a live listener started on dashboard appear, `limit: 100`). When is it stale/empty (just-recorded clip not yet in the snapshot, >100 drafts, listener not started)? In those cases the warning silently won't fire and Complete strands drafts again — is that acceptable degradation or a hole? Also check `publishAllThenComplete` error handling (partial publish failures still complete the session).
6. **Behavior parity after the body split.** `body` → `playerBody` + `runInitialLoad()` (was a big `.task`) + `trailingToolbarButtons` + `doneReviewingAction`. Confirm `.task`/scenePhase/`.onDisappear` observer teardown, auto-show-first-drawing, auto-mark-reviewed-on-open all still behave as before. The draft publish bar is added to BOTH narrowLayout and wideLayout — check iPad/landscape too.
7. **Telestration/drawings on a still-private draft** must work (annotations subcollection writes against a `visibility:"private"` video; check rules + the VM's permission-denied handling).
8. Confirm the 3 deleted files left no dangling references and `ClipReviewPublishBar` is still wired.

## How to verify the build
xcodebuild -project PlayerPath.xcodeproj -scheme PlayerPath -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
(The author reports BUILD SUCCEEDED; in-editor SourceKit "cannot find type" errors on these files are single-file false positives.)

## Background (optional, verify don't trust)
Memory notes `project_coach_unified_review_surface`, `project_coach_done_reviewing_semantics`, `project_coach_sessions`, `project_one_way_comments`, `feedback_notes_not_timestamps` describe intent and history. Treat them as claims to check, not facts.

Deliver: a prioritized findings list with exact file:line refs, each marked Confirmed-bug / Likely-bug / Risk / Nit, and a short verdict on whether the footgun is actually closed.
