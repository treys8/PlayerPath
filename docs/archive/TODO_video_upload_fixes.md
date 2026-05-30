# Video Upload & Shared Folders — Fix Plan
**Date:** 2026-03-27

Verified against source code. Ordered by priority and dependency.

---

## 1. Fix coach videoType hardcoding (Bug #1 — Critical)

The Game/Instruction picker in CoachVideoUploadView collects context but never passes it through. All coach uploads become "instruction" in Firestore.

**Files to change:**

### UploadQueueManager.swift
- [ ] Add `videoType: String?`, `gameOpponent: String?`, `gameDate: Date?` fields to `QueuedUpload` struct (~line 988)
- [ ] Add those same params to the coach `init` (~line 1033)
- [ ] Add those same params to `enqueueCoachUpload()` signature (~line 385)
- [ ] In `processCoachUpload()` (~line 905): replace hardcoded `videoType: "instruction"` with `upload.videoType ?? "instruction"`
- [ ] Pass `gameContext:` to `uploadVideoMetadata()` when videoType is "game", built from `upload.gameOpponent` and `upload.gameDate`

### CoachVideoUploadView.swift
- [ ] In `uploadVideo()` (~line 378): pass `videoContext`, `gameOpponent`, and `contextDate` through to `enqueueCoachUpload()`
  - Map `.game` → `"game"`, `.instruction` → `"instruction"`

**Test:** Upload a coach video with "Game" selected + opponent name. Check Firestore `videos/` doc has `videoType: "game"` and `gameContext.opponent` populated.

---

## 2. Remove dead code processWithThumbnailRetry (Bug #9 — Quick win)

- [ ] Delete `processWithThumbnailRetry()` in `CoachSessionManager.swift` (~lines 276-289)

---

## 3. Fix silent "game" fallback for untagged clips (Bug #4)

**File:** ShareToCoachFolderView.swift (~line 280)

- [ ] Change fallback `videoType` from `"game"` to `"other"` or `"untagged"`
- [ ] OR: add a simple alert/picker asking the athlete to classify the clip before sharing

Pick whichever feels right — the key thing is not silently mislabeling clips.

---

## 4. Add compression for athlete shared folder uploads (Bug #6)

**File:** SharedFolderManager.swift, in `uploadVideo()` (~line 534)

- [ ] Before the `VideoCloudManager.shared.uploadVideo()` call, run `VideoCompressionService.shared.compressForUpload(at: videoURL)`
- [ ] Use compressed URL if successful, fall back to original on failure (same pattern as UploadQueueManager ~line 648)

---

## 5. Add upload progress for athlete shares (Bug #10)

**Files:**

### ShareToCoachFolderView.swift
- [ ] Replace `@State private var isUploading = false` with a `@State private var uploadProgress: Double?`
- [ ] Update `uploadingOverlay` (~line 208) to show `ProgressView(value: uploadProgress)` with percentage text when non-nil, spinner when nil
- [ ] Pass a progress callback to `SharedFolderManager.uploadVideo()`

### SharedFolderManager.swift
- [ ] Add `progressHandler: ((Double) -> Void)? = nil` param to `uploadVideo()`
- [ ] Forward it to `VideoCloudManager.uploadVideo()` progress callback (~line 534)

---

## 6. Route athlete uploads through UploadQueueManager for retry (Bug #3)

This is the biggest change. Can defer to a follow-up session if time runs short.

**Approach:** Add an `enqueueAthleteSharedFolderUpload()` method to UploadQueueManager that mirrors the coach flow but with `visibility: "shared"` (no private-first review step).

### UploadQueueManager.swift
- [ ] Add `enqueueAthleteSharedFolderUpload()` with params matching SharedFolderManager.uploadVideo's signature
- [ ] Add a `processAthleteSharedUpload()` method that uploads → writes metadata with `visibility: "shared"` → notifies coaches
- [ ] QueuedUpload needs an `isAthleteSharedUpload` flag or a union type to distinguish from coach uploads

### ShareToCoachFolderView.swift
- [ ] Replace direct `SharedFolderManager.uploadVideo()` call with `UploadQueueManager.enqueueAthleteSharedFolderUpload()`
- [ ] Show queue-based progress instead of inline spinner

**Note:** This gives athletes retry (10 attempts), compression, timeout protection, and progress for free. But it changes the UX from synchronous "done/failed" to async queue — athlete won't see immediate confirmation. Consider keeping a "pending uploads" indicator.

---

## 7. Duplicate detection for athlete shares (Bug #7) — If time allows

### ShareToCoachFolderView.swift
- [ ] Before upload, query Firestore for videos in target folder with matching `fileName` or file hash
- [ ] If found, show confirmation: "This video may already be in this folder. Share anyway?"

---

## Not fixing today

- **Bug #2 (folderType enforcement):** folderType already drives icons + lessons preference. Full routing/validation is a bigger UX design decision — defer.
- **Bug #5 (cloud-only video sharing):** Requires on-demand download pipeline. Defer to post-launch.
- **Bug #8 (VideoClip sharedFolderIds tracking):** Schema change + migration. Defer.
