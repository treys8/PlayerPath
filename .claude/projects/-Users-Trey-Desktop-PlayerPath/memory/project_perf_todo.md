---
name: Performance refactors TODO (List B)
description: Structural refactors for @Published sprawl and view redraw optimization — deferred from the performance audit session
type: project
---

Structural refactors identified during performance audit (2026-03-15). These are the right fixes long-term but touch many files. Ship current fixes first and test on-device before tackling.

**Why:** ComprehensiveAuthManager has 12 @Published properties observed by 35+ views. UploadQueueManager mutates progress dictionaries 10x/second during uploads. DashboardView has 7 @State vars scoped too high. Each causes cascading redraws.

**How to apply:** Do one at a time with a build check between each. Test on-device after each.

## TODO

### 1. Split ComprehensiveAuthManager hot properties
Extract `isLoading` and `errorMessage` into a separate `AuthUIState` object so transient loading state doesn't redraw every auth-dependent view (35+ files).

### 2. Decouple UploadQueueManager progress from @Observable
Replace `activeUploads` dictionary mutations (every 100ms per upload) with a Combine PassthroughSubject or AsyncStream that only UploadStatusBanner subscribes to.

### 3. Extract DashboardView @State to child components
Move `showingPaywall`, `showingDirectCamera`, `selectedVideoForPlayback`, `showingSeasons`, `showingPhotos`, `isCheckingPermissions`, `pulseAnimation` into dedicated child views (`LiveGamesSection`, `QuickActionsSection`, etc.) so changing one doesn't redraw the entire dashboard.

### 4. Isolate MainTabView badge observer
`UnreadBadgeModifier` observes entire `ActivityNotificationService`. Extract to only wrap the Videos tab instead of all 5 tabs.

### 5. Consolidate UserMainFlow onChange handlers
3 cascading `.onChange` handlers (athletesForUser, selectedAthlete, quickActionsManager) cause multiple body invalidations per athlete creation. Consolidate into a single coordinated handler or view model.

---

## Background/Foreground Resilience TODO

### 6. Wrap critical saves in beginBackgroundTask
All `modelContext.save()` calls in Task blocks lack `UIApplication.beginBackgroundTask()`. If the OS kills the app mid-save, data could be partially written. Affected: `ImportTaggingSheet.saveTagging()`, `OnboardingSeasonCreationView.createSeason()`, `CoachVideoUploadView.uploadVideo()`, all game/practice/athlete creation flows.

### 7. Clean up orphaned temp video files on launch
`VideoRecorderView_Refactored` creates temp files for trimming. If the app is killed before cleanup runs, files persist. Add a launch-time sweep of the temp directory for `.mov`/`.mp4` files older than 1 hour.

### 8. Form state auto-persistence
Form data (game name, athlete name, season name) lives only in @State memory. If the OS kills the app due to memory pressure, all typed text is lost. Consider auto-saving intermediate form state to UserDefaults on `.onDisappear` or `sceneDidEnterBackground`, with recovery on next appearance.

---

## Data Consistency TODO

### 9. Wrap acceptInvitation() and removeCoachFromFolder() in WriteBatch
Both perform 2 sequential Firestore writes without atomicity. If step 1 succeeds and step 2 fails, data is inconsistent (coach has access but invitation still "pending", or coach revoked but no notification).

### 10. Move deleteUserProfile() to a Cloud Function
5-step cascade delete (folders → videos → annotations → invitations → notifications → user) across multiple collections. Partial failure leaves orphaned data. GDPR compliance requires atomic deletion.

### 11. Add stats recalculation for modified clips in sync path
SyncCoordinator (lines ~888-930) updates clip play results from remote but only recalculates stats for NEW clips. Modified clips bypass recalculation, causing game/athlete stats to diverge from actual clip data on multi-device sync.

### 12. Ensure reversePlayResultStats() handles all play result types
ImportTaggingSheet's reversal function doesn't handle pitching stats (ball, strike, wildPitch), creating asymmetry with addPlayResult() when re-tagging videos.

### 13. Add season stats for practice video play results
`recalculateSeasonStatistics()` only aggregates from games. `recalculateAthleteStatistics()` also includes standalone practice videos. Practice video play results are counted in athlete stats but NOT in season stats.
