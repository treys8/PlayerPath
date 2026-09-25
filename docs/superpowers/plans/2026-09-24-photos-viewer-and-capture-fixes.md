# Photos Viewer + Camera Capture Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Opened photos show the whole image and swipe without stutter; new photos (camera, scan, library import) back up right away, and a failed camera save tells the user.

**Architecture:** (1) `ZoomablePhotoPage` defaults to aspect-fit, and double-tap zooms to the tapped point. Its pan clamp now computes from the fitted image size instead of assuming fill. (2) `UIImage.decodedFullRes` forces the JPEG decode off-main via `preparingForDisplay()`. (3) `syncPhotos` is made safe to call right after a save: passes are serialized (no duplicate docs), and edits or deletes made mid-upload survive. (4) A fire-and-forget `syncPhotosSoon(for:)` runs after camera saves, scorecard scans and bulk imports. (5, 6) A warning toast appears when a camera save fails, on the Photos tab and on the game page (6 is gated).

**Tech Stack:** SwiftUI (iOS 17+), SwiftData, Firebase Storage/Firestore, ImageIO/UIKit.

**Spec:** The Photos review in this session. It covers findings #1 (viewer crops by default), #2 (main-thread decode), #4 (new photos wait up to 30 min to upload — corrected: bulk import is affected too, see Task 4) and #5 (silent camera save failure). Findings #3, #6, #7 and #8 are out of scope.

## Global Constraints

- iOS 17 deployment floor. `onTapGesture(count:coordinateSpace:perform:)` (location-reporting) and `MagnifyGesture` are both iOS 17 APIs, so no `#available` is needed.
- **No test target exists** for Swift (CLAUDE.md). Each task is verified by a CLI build plus the manual checks listed in that task. There is no TDD step.
- Build command (needs the `DEVELOPER_DIR` prefix; ignore transient SourceKit noise and trust the final `BUILD SUCCEEDED`):
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PlayerPath.xcodeproj -scheme PlayerPath -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5`
- Do NOT add any drag recognizer to pager pages beyond the existing masked pan. Any drag attached at 1× kills TabView paging (see the header comment in `PhotoDetailView.swift`).
- Error handling: views use `ErrorHandlerService`; services log via their OSLog `Logger`. Never write `try? context.save()`.
- Do not touch version or build numbers.
- Commit directly to `main`, and stage only the files each task names. `GameDetailView.swift`, `PlayResultAccumulator.swift` and `AdvancedSearchView.swift` carry **someone else's uncommitted edits**. Never `git add -A`.

## Before Task 1

Commit this plan on its own, matching the repo's `Plan: …` convention:

```bash
git add docs/superpowers/plans/2026-09-24-photos-viewer-and-capture-fixes.md
git commit -m "Plan: photos viewer fit/zoom, off-main decode, prompt photo upload

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

## Review Focus

1. **Landscape photo on a portrait phone, double-tapped in the black letterbox band.** The zoom should land on the nearest image edge, not pan into black. Covered by the clamp in Task 1; manual check 1d.
2. **Pinch out from a panned 3× zoom back toward 1×.** The image edge should never detach from the screen edge mid-pinch. Covered by the clamp inside `MagnifyGesture.onChanged` (Task 1); manual check 1e.
3. **Swiping between pages still works at 1× after the gesture rewrite.** This is the regression most likely to ship. Manual check 1f, which must pass on a device.
4. **Delete or edit a photo in the seconds after taking it, while it's still uploading.** A delete must not crash or resurrect the photo, and a star/tag/caption must reach Firestore. Covered by Task 3 Step 4; manual checks 4d and 4e.
5. **Camera save while a sync is already mid-photo-pass, or with a pull-to-refresh right after.** Only one Firestore doc should be created per photo. Covered by Task 3's coalescing guard; manual check 4c.

---

### Task 1: Viewer opens photos aspect-fit; double-tap zooms to the tap point

**Files:**
- Modify: `PlayerPath/Views/Photos/ZoomablePhotoPage.swift` (whole `struct` body, lines 14–153)
- Modify: `PlayerPath/Views/Photos/PhotoDetailView.swift:5-6` (header comment only)

**Interfaces:**
- Consumes: nothing new. `ZoomablePhotoPage(photo:onZoomChanged:onSingleTap:)` is unchanged, so `PhotoDetailView` needs no call-site change.
- Produces: nothing used by later tasks.

**Behavior change (intentional):** double-tap no longer toggles fit/fill. At 1× it zooms to 2.5× centered on the tapped point; when zoomed it resets to 1×. This matches Photos.app.

- [ ] **Step 1: Replace the state + constants block (lines 22–35)** with:

```swift
    @State private var fullImage: UIImage?
    @State private var loadFailed = false
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    /// Pan offset when zoomed in. Reset to `.zero` any time scale returns to 1×
    /// so the next zoom-in starts centered.
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    /// Double-tap zooms the tapped point to this scale (Photos.app convention).
    private static let doubleTapScale: CGFloat = 2.5
    private static let maxScale: CGFloat = 5.0

    private var isZoomed: Bool { scale > 1.0 }
```

(`photoContentMode` is deleted.)

- [ ] **Step 2: Replace the `if let fullImage { GeometryReader { … } }` branch (lines 41–116)** with:

```swift
            if let fullImage {
                // Aspect-FIT by default so the whole photo is visible, like
                // Photos.app. The old `.fill` default cropped ~65% of a landscape
                // shot on a portrait phone, and pinch can't zoom out below 1× to
                // recover it. Pinch zooms 1×–5×; double-tap zooms to the tapped
                // point; drag pans only while zoomed.
                GeometryReader { geometry in
                    Image(uiImage: fullImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .contentShape(Rectangle())
                        .gesture(
                            MagnifyGesture()
                                .onChanged { value in
                                    scale = min(Self.maxScale, max(1.0, lastScale * value.magnification))
                                    // Zooming out shrinks the pannable area — pull the
                                    // pan back inside it so an image edge never
                                    // detaches from the screen edge mid-pinch.
                                    offset = clampOffset(lastOffset, scale: scale, imageSize: fullImage.size, in: geometry.size)
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                    if scale == 1.0 {
                                        // Zoomed back to default — drop any pan
                                        // so the next zoom starts centered.
                                        withAnimation(.spring(response: 0.3)) {
                                            offset = .zero
                                        }
                                    }
                                    lastOffset = offset
                                    onZoomChanged(isZoomed)
                                }
                        )
                        // When zoomed, this drag pans the photo instead of flipping
                        // pages. The `including:` mask must fully disable it at 1×:
                        // ANY drag recognizer attached here — even a .simultaneousGesture
                        // that ignores the touch — starves the TabView pager of
                        // horizontal drags (and the zoom transition of its dismiss
                        // pan), which is exactly the "can't swipe to next photo" bug.
                        // Swipe-down-to-dismiss is NOT reimplemented here for the
                        // same reason; the iOS 18 zoom transition provides it.
                        .highPriorityGesture(
                            DragGesture()
                                .onChanged { value in
                                    guard isZoomed else { return }
                                    let proposed = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                    offset = clampOffset(proposed, scale: scale, imageSize: fullImage.size, in: geometry.size)
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                },
                            including: isZoomed ? .gesture : .subviews
                        )
                        .onTapGesture(count: 2) { location in
                            withAnimation(.spring(response: 0.3)) {
                                if isZoomed {
                                    scale = 1.0
                                    lastScale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    zoom(to: Self.doubleTapScale, at: location, imageSize: fullImage.size, in: geometry.size)
                                }
                            }
                            onZoomChanged(isZoomed)
                        }
                        // Declared after the double-tap so the count:2 recognizer
                        // wins the ambiguity; a lone tap toggles chrome.
                        .onTapGesture(count: 1) {
                            onSingleTap()
                        }
                }
```

(The `else if loadFailed` / `else` branches and `.task` / `.onDisappear` stay exactly as they are.)

- [ ] **Step 3: Replace `clampOffset` (lines 141–153)** with the fit-aware clamp plus the zoom helper:

```swift
    /// Clamps a proposed pan offset so the zoomed image's edges can't be
    /// dragged past the screen edges. Works from the image's aspect-FIT size in
    /// `viewport`, so an axis where the zoomed image is still narrower than the
    /// screen (e.g. the height of a landscape shot at 2.5×) gets no pan at all.
    private func clampOffset(_ proposed: CGSize, scale: CGFloat, imageSize: CGSize, in viewport: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let fitRatio = min(viewport.width / imageSize.width, viewport.height / imageSize.height)
        let maxX = max(0, (imageSize.width * fitRatio * scale - viewport.width) / 2)
        let maxY = max(0, (imageSize.height * fitRatio * scale - viewport.height) / 2)
        return CGSize(
            width: min(maxX, max(-maxX, proposed.width)),
            height: min(maxY, max(-maxY, proposed.height))
        )
    }

    /// Zooms to `target` keeping the tapped point under the finger.
    /// `scaleEffect` scales about the view's center `c`, sending a point `p` to
    /// `c + s·(p − c)`; offsetting by `(1 − s)·(p − c)` puts it back at `p`.
    /// The clamp then pulls a tap in the letterbox band onto the image edge.
    private func zoom(to target: CGFloat, at location: CGPoint, imageSize: CGSize, in viewport: CGSize) {
        let proposed = CGSize(
            width: (1 - target) * (location.x - viewport.width / 2),
            height: (1 - target) * (location.y - viewport.height / 2)
        )
        scale = target
        lastScale = target
        offset = clampOffset(proposed, scale: target, imageSize: imageSize, in: viewport)
        lastOffset = offset
    }
```

- [ ] **Step 4: Fix the stale header comments**

- In `ZoomablePhotoPage.swift`, nothing else refers to fit/fill once Steps 1–3 are done. Confirm with `grep -n "fill\|photoContentMode" PlayerPath/Views/Photos/ZoomablePhotoPage.swift`. The only hit should be the "Aspect-FIT … `.fill` default" comment.
- In `PhotoDetailView.swift`, change lines 5–6 from
  `//  Full-screen, swipeable photo viewer. Pages through a set of photos (pinch`
  `//  zoom + double-tap fit/fill per page live in ZoomablePhotoPage) while this`
  to
  `//  Full-screen, swipeable photo viewer. Pages through a set of photos (pinch`
  `//  zoom + double-tap zoom-to-point per page live in ZoomablePhotoPage) while this`

- [ ] **Step 5: Build.** Run the build command from Global Constraints. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Manual checks (simulator is fine except 1f, which needs a device)**

  - 1a. Open a portrait photo. The whole photo is visible and nothing is cropped.
  - 1b. Open a landscape photo. It spans the full width with black bands above and below.
  - 1c. Double-tap on a face. The view zooms to 2.5× with the face staying under the tap point. Double-tap again to return to 1×, centered.
  - 1d. On a landscape photo, double-tap in the black band above the image. The zoom lands at the image's top edge, and no black shows inside the frame.
  - 1e. Pinch to 3×, pan to a corner, then pinch slowly back toward 1×. The image corner stays pinned to the screen corner until it re-centers at 1×.
  - 1f. **(device)** At 1×, swipe left and right. Pages change. Zoom in, and a horizontal drag pans the photo instead of paging. Swipe down at 1× (iOS 18+) and the viewer dismisses.
  - 1g. A single tap still toggles the chrome, and the metadata overlay hides while zoomed.

- [ ] **Step 7: Commit**

```bash
git add PlayerPath/Views/Photos/ZoomablePhotoPage.swift PlayerPath/Views/Photos/PhotoDetailView.swift
git commit -m "Photo viewer: open aspect-fit, double-tap zooms to the tapped point

The .fill default cropped ~65% of a landscape photo (and ~40% of a portrait
one) on a portrait phone, with no pinch-out to recover it. Pan clamp now
works from the fitted image size. MagnificationGesture -> MagnifyGesture.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Decode full-res photos off the main thread for real

**Files:**
- Modify: `PlayerPath/Views/Photos/UIImage+FullResDecode.swift:12-19`

**Interfaces:**
- Consumes: nothing.
- Produces: `UIImage.decodedFullRes(atPath:) async -> UIImage?`, with the same signature. Its callers (`ZoomablePhotoPage.loadFullImage`, `PhotoDetailView.saveCurrentToCameraRoll`) are unchanged.

- [ ] **Step 1: Replace the function** with:

```swift
    /// Decodes a (potentially 12MP) image file off the main thread via
    /// `Task.detached` — the codebase's established off-main convention. The
    /// caller assigns the result on the main actor.
    ///
    /// `UIImage(contentsOfFile:)` alone only maps the file — the JPEG decode
    /// would then run on the MAIN thread at first draw, right as the page
    /// swipes in (a visible hitch). `preparingForDisplay()` forces the decode
    /// here instead. It returns nil for images it can't prepare, so fall back
    /// to the lazy image rather than failing the load.
    static func decodedFullRes(atPath path: String) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let image = UIImage(contentsOfFile: path) else { return nil }
            return image.preparingForDisplay() ?? image
        }.value
    }
```

- [ ] **Step 2: Build.** Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual check (device, Release-ish feel).** Open a photo from a grid of large library imports and swipe quickly through 10+ photos. There should be no hitch as each page lands. Save to Camera Roll from the ••• menu still works. Keep Xcode's memory gauge open while swiping through 20 photos. Neighbor pages now decode eagerly, off-main, so usage may run higher than before, but it must plateau rather than keep climbing (`onDisappear` releases each page's image).

- [ ] **Step 4: Commit**

```bash
git add "PlayerPath/Views/Photos/UIImage+FullResDecode.swift"
git commit -m "Photo viewer: force full-res decode off-main with preparingForDisplay

UIImage(contentsOfFile:) is lazy; the JPEG decode was happening on the
main thread at first draw, mid-swipe.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Make photo sync safe to run right after a save

Task 4 starts a photo sync a moment after every save. That exposes three pre-existing races in `syncPhotos` which today only matter in rare timing, but after Task 4 become the normal case. This task fixes all three **before** anything calls sync sooner.

- **Overlapping passes create duplicate docs.** `FirestoreManager.createPhoto` uses `addDocument`, which is **not idempotent** (`FirestoreManager+EntitySync.swift:665`). `syncPhotos` already has callers outside the `isSyncing` guard: the backfill reroute, pull-to-refresh, and `syncAll`. If two passes overlap, both see `cloudURL == nil && needsSync` on a new photo and each creates a doc, which becomes a duplicate photo on every other device. **Fix:** serialize passes. A call that lands mid-pass sets a flag, and the running pass loops once more.
- **An edit during the upload is lost remotely.** The upload branch builds the create payload, awaits two network calls, then sets `needsSync = false` unconditionally (`SyncCoordinator+Photos.swift:107`). A tag, star or caption made in that window (exactly when someone touches a photo they just took), or the bulk-import season reroute, is cleared without ever being sent. **Fix:** snapshot the editable fields when the payload is built, and leave the photo dirty if they changed. The metadata-update loop later in the same pass (line 127) then sends the edit.
- **A delete during the upload resurrects the photo, or crashes.** `Photo.delete` only cleans Storage/Firestore when `cloudURL`/`firestoreId` are already set, and the upload branch writes to the model after each await. A photo deleted mid-upload either gets a Firestore doc created after deletion (it reappears on the next pass and on other devices) or traps on a write to a deleted `@Model` (see memory `feedback_swiftdata_model_access_across_await`). **Fix:** capture `fileName` before any await. After each await, check the photo is still live; if not, remove whatever was created. Also set `cloudURL` only together with `firestoreId`, so `Photo.delete` never frees quota for bytes that were never counted.

**Files:**
- Modify: `PlayerPath/SyncCoordinator.swift:40` (two properties after `photosBlockedByQuota`)
- Modify: `PlayerPath/SyncCoordinator+Photos.swift:10-12` (add `PhotoEditSnapshot`), `:24-26` (coalescing wrapper + `syncPhotosSoon`), `:65-124` (upload loop)

**Interfaces:**
- Produces: `SyncCoordinator.syncPhotosSoon(for user: User?)`, which is `@MainActor`, synchronous and fire-and-forget. Used by Tasks 4 and 6.
- `SyncCoordinator.syncPhotos(for:) async throws` keeps its signature. Behavior change: a call made while a pass is running returns immediately (a pull-to-refresh spinner may end early) and schedules one follow-up pass.

- [ ] **Step 1: Add the guard state** in `SyncCoordinator.swift`, directly after `var photosBlockedByQuota: Int = 0` (line 40):

```swift

    /// A photo-sync pass is running. `syncPhotos` has callers outside the
    /// `isSyncing` guard (post-save kicks, bulk-import reroute, pull-to-refresh),
    /// and two overlapping passes would both upload the same new photo and each
    /// create a Firestore doc (`createPhoto` uses the non-idempotent
    /// `addDocument`) — a duplicate on every other device. See `syncPhotos(for:)`.
    @ObservationIgnored var isSyncingPhotos = false
    /// A `syncPhotos` call arrived mid-pass; the running pass loops once more so
    /// the caller's new photo isn't left for the next full sync.
    @ObservationIgnored var photoSyncRequested = false
```

- [ ] **Step 2: Add the edit snapshot type** in `SyncCoordinator+Photos.swift`, directly after the `syncLog` declaration (line 10). It's `nonisolated` like `RecruitingStatItem`, so the synthesized `Equatable` isn't main-actor-isolated; only the init touches the model.

```swift

/// The user-editable fields of a photo, captured when its create payload is
/// built. Compared after the upload's awaits: a difference means an edit
/// (tag, star, caption, season re-home) landed mid-upload and never reached the
/// created doc, so the photo must stay dirty for the metadata-update loop.
private nonisolated struct PhotoEditSnapshot: Equatable {
    let caption: String?
    let isHighlight: Bool
    let isScorecardPhoto: Bool
    let gameID: UUID?
    let practiceID: UUID?
    let seasonID: UUID?

    @MainActor init(_ photo: Photo) {
        caption = photo.caption
        isHighlight = photo.isHighlight
        isScorecardPhoto = photo.isScorecardPhoto
        gameID = photo.game?.id
        practiceID = photo.practice?.id
        seasonID = photo.season?.id
    }
}
```

- [ ] **Step 3: Split `syncPhotos`.** Replace lines 24–26:

```swift
    // MARK: - Photos Sync

    func syncPhotos(for user: User) async throws {
```

with:

```swift
    // MARK: - Photos Sync

    /// Runs photo sync passes one at a time. A call that lands mid-pass returns
    /// at once and makes the running pass loop again — so overlapping callers
    /// can never double-create a photo's Firestore doc, and a just-saved photo
    /// still uploads promptly. (A coalesced caller doesn't wait for that pass.)
    func syncPhotos(for user: User) async throws {
        guard !isSyncingPhotos else {
            photoSyncRequested = true
            return
        }
        isSyncingPhotos = true
        defer { isSyncingPhotos = false }
        repeat {
            photoSyncRequested = false
            try await runPhotoSyncPass(for: user)
        } while photoSyncRequested
    }

    /// Fire-and-forget photo upload after a local photo save, so a capture or
    /// import backs up now rather than at the next full sync — up to 30 min,
    /// since the 5-minute periodic sync skips photos. Failures only log: the
    /// photo stays `needsSync` and the next pass retries it.
    func syncPhotosSoon(for user: User?) {
        guard let user else { return }
        Task {
            do {
                try await syncPhotos(for: user)
            } catch {
                syncLog.error("Post-save photo sync failed: \(error.localizedDescription)")
            }
        }
    }

    /// `isDeleted` / `modelContext` are safe to read on a deleted model, unlike
    /// its attributes — check this after every await before touching `photo`.
    private static func isLive(_ photo: Photo) -> Bool {
        !photo.isDeleted && photo.modelContext != nil
    }

    /// One full photo pass: upload new, push metadata edits, pull remote, delete
    /// remotely-deleted, re-queue missing files. Call via `syncPhotos(for:)`.
    private func runPhotoSyncPass(for user: User) async throws {
```

The rest of the old body (from `guard let context = modelContext else { return }` on) is unchanged apart from Step 4, and is now `runPhotoSyncPass`'s body.

- [ ] **Step 4: Harden the upload loop.** Replace the whole `for photo in photos where photo.cloudURL == nil && photo.needsSync { … }` loop (originally lines 65–124, ending just before `// Update metadata for photos that have been edited locally`) with:

```swift
            for photo in photos where photo.cloudURL == nil && photo.needsSync {
                let resolvedPath = photo.resolvedFilePath
                // Captured before any await — the photo can be deleted mid-upload
                // (a post-save sync starts seconds after capture), and a deleted
                // model's attributes must not be read.
                let fileName = photo.fileName
                guard FileManager.default.fileExists(atPath: resolvedPath) else { continue }
                // Enforce storage limit before uploading (use live StoreKit tier)
                let fileSize: Int64
                do {
                    let attrs = try FileManager.default.attributesOfItem(atPath: resolvedPath)
                    fileSize = (attrs[.size] as? Int64) ?? 0
                } catch {
                    syncLog.error("Failed to read photo file size at '\(resolvedPath)': \(error.localizedDescription)")
                    continue
                }
                let tier = SubscriptionGate.effectiveAthleteTier
                let limitBytes = Int64(tier.storageLimitGB) * StorageConstants.bytesPerGB
                guard user.cloudStorageUsedBytes + fileSize <= limitBytes else {
                    blockedByQuota += 1
                    syncLog.warning("Photo upload skipped — cloud storage full (\(user.cloudStorageUsedBytes) + \(fileSize) > \(limitBytes) bytes)")
                    continue
                }
                do {
                    let cloudURL = try await VideoCloudManager.shared.uploadPhoto(
                        at: URL(fileURLWithPath: resolvedPath),
                        ownerUID: ownerUID
                    )
                    // Deleted while the file uploaded. Don't create a doc — the next
                    // pass's download loop would resurrect the photo — and drop the blob.
                    guard Self.isLive(photo) else {
                        syncLog.info("Photo deleted mid-upload — removing uploaded blob")
                        Task {
                            await retryAsync {
                                try await VideoCloudManager.shared.deleteAthletePhoto(fileName: fileName)
                            }
                        }
                        continue
                    }
                    // `cloudURL` goes into the payload but NOT onto the model until the
                    // doc exists: `Photo.delete` treats a non-nil cloudURL as "counted
                    // against quota", and these bytes aren't counted yet.
                    var payload = photo.toFirestoreData(ownerUID: ownerUID)
                    payload["downloadURL"] = cloudURL
                    let sent = PhotoEditSnapshot(photo)
                    let firestoreId: String
                    do {
                        firestoreId = try await FirestoreManager.shared.createPhoto(data: payload)
                    } catch {
                        // Firestore write failed after Storage upload — clean up orphaned file
                        syncLog.error("Firestore photo create failed, cleaning up Storage: \(error.localizedDescription)")
                        Task {
                            await retryAsync {
                                try await VideoCloudManager.shared.deleteAthletePhoto(fileName: fileName)
                            }
                        }
                        throw error
                    }
                    // Deleted while the doc was being created: undo both.
                    guard Self.isLive(photo) else {
                        syncLog.info("Photo deleted mid-create — removing doc and blob")
                        Task {
                            await retryAsync {
                                try await FirestoreManager.shared.deletePhoto(photoId: firestoreId)
                            }
                            await retryAsync {
                                try await VideoCloudManager.shared.deleteAthletePhoto(fileName: fileName)
                            }
                        }
                        continue
                    }
                    photo.cloudURL = cloudURL
                    photo.firestoreId = firestoreId
                    // An edit made during the two awaits isn't in the created doc.
                    // Leave the photo dirty so the metadata-update loop below — this
                    // same pass — sends it, instead of clearing the edit unsent.
                    photo.needsSync = PhotoEditSnapshot(photo) != sent
                    if let uploadedSize = (try? FileManager.default.attributesOfItem(atPath: resolvedPath)[.size] as? Int64) {
                        user.cloudStorageUsedBytes += uploadedSize
                    } else {
                        syncLog.warning("Could not read uploaded photo file size for storage tracking")
                    }
                    // Persist cloudURL + firestoreId (+ quota) IMMEDIATELY. If the
                    // batch save at the end of syncPhotos later fails, we must not
                    // lose the fact that this photo is already in Storage + Firestore
                    // — otherwise the next sync sees cloudURL == nil and re-uploads,
                    // leaking the first blob AND double-charging quota. Mirrors the
                    // firestoreId-immediate-save pattern in +Coaches / +Athletes.
                    ErrorHandlerService.shared.saveContext(context, caller: "SyncCoordinator.syncPhotos.uploaded")
                    syncedPhotos.append(photo)
                } catch {
                    syncLog.error("Failed to sync photo: \(error.localizedDescription)")
                }
            }
```

Changes from the original, so a reviewer can diff intent:
- `fileName` is captured up front. It replaces the old in-catch `capturedFileName`.
- A liveness guard follows each of the two awaits.
- `photo.cloudURL` is no longer set before `createPhoto`. The URL goes into `payload["downloadURL"]` instead (the same key `toFirestoreData` writes at `Photo.swift:84`). Because of that, the old failure-path `photo.cloudURL = nil` is gone: there's nothing to roll back.
- `needsSync` is derived from the snapshot instead of set to `false` unconditionally.

Two pre-existing behaviors are deliberately kept:
- On a pass-level failure, the batch-save catch re-dirties `syncedPhotos`.
- `syncedPhotos.append` runs for every uploaded photo.

- [ ] **Step 5: Verify the metadata-update loop still follows.** Run `sed -n '/Update metadata for photos that have been edited locally/,+3p' PlayerPath/SyncCoordinator+Photos.swift`. The filter must still read `$0.needsSync && $0.firestoreId != nil && $0.cloudURL != nil`, and it's computed *after* the upload loop, so an upload left dirty by Step 4 is picked up in the same pass.

- [ ] **Step 6: Build.** Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add PlayerPath/SyncCoordinator.swift PlayerPath/SyncCoordinator+Photos.swift
git commit -m "Photo sync: serialize passes; survive edits and deletes mid-upload

- createPhoto uses addDocument, so two overlapping syncPhotos passes could
  each create a doc for one new photo (a cross-device duplicate). Passes are
  now coalesced into one serial run.
- An edit made while a photo uploaded was cleared unsent (needsSync=false
  unconditionally). Now it stays dirty and the same pass pushes it.
- A photo deleted mid-upload got a doc created after deletion (resurrected)
  or a write to a deleted @Model. Liveness is checked after each await, and
  cloudURL lands on the model only with firestoreId.
- New syncPhotosSoon(for:) for post-save kicks (wired up next commit).

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Start the upload right after a save (camera, scorecard, bulk import)

**Correction to the review:** the review said bulk library import already syncs right away. It doesn't. `BulkPhotoImportAttach.swift:465` is inside `reroute(to:)`, the past-season backfill prompt, so it only runs when that prompt is answered. Ordinary imports wait for the next full sync, the same as camera photos, so this task covers imports too.

**Files:**
- Modify: `PlayerPath/Views/Photos/PhotosView.swift:691-704` (`savePhoto`)
- Modify: `PlayerPath/Views/Games/ScorecardScanFlow.swift` (`persistScorecardPhoto`, after its `saveContext`)
- Modify: `PlayerPath/Views/Photos/BulkPhotoImportAttach.swift` (`importPhotos`, after `importTask = nil`, ~line 368)
- (GameDetailView's camera save is Task 6, because of that file's foreign uncommitted edits.)

**Interfaces:**
- Consumes: `SyncCoordinator.syncPhotosSoon(for:)` (Task 3).

- [ ] **Step 1: `PhotosView.savePhoto`.** Replace `PhotosView.swift:691-704` with the version below. The `catch` body is unchanged here; Task 5 replaces it.

```swift
    private func savePhoto(_ image: UIImage) {
        // Snapshot before the await (model access across suspension).
        let user = athlete.user
        Task {
            do {
                _ = try await PhotoPersistenceService().savePhoto(
                    image: image,
                    context: modelContext,
                    athlete: athlete
                )
                Haptics.success()
                // Back it up now — otherwise it sits local-only until the next
                // full sync (the periodic sync skips photos).
                SyncCoordinator.shared.syncPhotosSoon(for: user)
            } catch {
                ErrorHandlerService.shared.handle(error, context: "PhotosView.savePhoto", showAlert: false)
            }
        }
    }
```

- [ ] **Step 2: `ScorecardScanFlow.persistScorecardPhoto`.** `athlete` is the view's `let athlete: Athlete` (line 21). Directly after
  `ErrorHandlerService.shared.saveContext(context, caller: "ScorecardScanFlow.persist")`, add:

```swift
            SyncCoordinator.shared.syncPhotosSoon(for: athlete.user)
```

  (`isScorecardPhoto` is set synchronously right after `savePhoto` returns, before the kicked Task can run on the main actor, so the create payload includes it. If it ever didn't, Task 3's snapshot would catch the difference.)

- [ ] **Step 3: `BulkPhotoImportAttach.importPhotos`.** Directly after the two lines

```swift
        isImporting = false
        importTask = nil
```

  add:

```swift

        // Back the new photos up now rather than at the next full sync. Safe
        // alongside the backfill prompt below: a season re-home that lands while
        // these upload stays dirty (see PhotoEditSnapshot) and syncs in the
        // same run.
        if outcome.succeeded > 0 {
            SyncCoordinator.shared.syncPhotosSoon(for: athlete.user)
        }
```

- [ ] **Step 4: Build.** Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual checks (signed in, online unless noted)**
  - 4a. Photos tab → ••• → Take Photo. Within a few seconds the gray phone badge on the new cell disappears. The Firestore console shows exactly one `photos` doc with that `swiftDataId`.
  - 4b. On a second device (or after reinstalling), the photo appears once.
  - 4c. Take a photo, then immediately pull to refresh twice. There is still exactly one Firestore doc for that `swiftDataId`.
  - 4d. Take a photo and **immediately** star it and add a caption, before the badge clears. After the badge clears, the Firestore doc has `isHighlight: true` and the caption.
  - 4e. Take a photo and **immediately** delete it, before the badge clears. There's no crash. Within a minute there's no doc for that `swiftDataId` (or it's `isDeleted: true`) and no `athlete_photos/<uid>/<fileName>` object. Pull to refresh: the photo does not reappear.
  - 4f. Import 10 photos from the library. All badges clear within about a minute, and there are 10 docs, with no duplicates.
  - 4g. Turn on Airplane Mode and take a photo. It saves, keeps the gray badge, and shows no error. Turn Airplane Mode off and pull to refresh. It uploads once.

- [ ] **Step 6: Commit**

```bash
git add PlayerPath/Views/Photos/PhotosView.swift PlayerPath/Views/Games/ScorecardScanFlow.swift PlayerPath/Views/Photos/BulkPhotoImportAttach.swift
git commit -m "Photos: start the upload right after a camera save, scan, or import

These sat local-only until the next full sync (up to 30 min; the 5-min
periodic sync skips photos). The bulk-import sync call only ran from the
past-season backfill prompt.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Tell the user when a camera save fails (Photos tab)

**Why a toast, not an alert:** the save runs while the camera's `fullScreenCover` is dismissing. SwiftUI silently drops an alert presented during that transition. `PhotosView` already has a toast overlay (`actionToast*`, `ToastType.warning` exists), which isn't a presentation and so can't collide.

**Files:**
- Modify: `PlayerPath/Views/Photos/PhotosView.swift` (`savePhoto`'s `catch`)

**Interfaces:**
- Consumes: nothing new. It edits the `catch` of the `savePhoto` that Task 4 rewrote.

- [ ] **Step 1: Replace the `catch` in `savePhoto`** with:

```swift
            } catch {
                ErrorHandlerService.shared.handle(error, context: "PhotosView.savePhoto", showAlert: false)
                // The camera already flashed and closed, so without this the photo
                // just never appears. Toast, not alert: this lands while the
                // camera cover is still dismissing, and an alert presented then
                // is silently dropped.
                Haptics.error()
                actionToastType = .warning
                actionToastMessage = "Couldn't save your photo. Please try again."
                showActionToast = true
            }
```

- [ ] **Step 2: Build.** Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual check.** Temporarily force a failure by putting `throw PhotoPersistenceError.failedToEncode` at the top of the `do` in `savePhoto`. Take a photo: the camera closes and the warning toast appears with an error haptic. **Remove the forced throw** and rebuild. Then confirm `git diff PlayerPath/Views/Photos/PhotosView.swift` shows no `throw PhotoPersistenceError`.

- [ ] **Step 4: Commit**

```bash
git add PlayerPath/Views/Photos/PhotosView.swift
git commit -m "Photos: show a warning toast when a camera save fails

It was logged with showAlert: false — shutter flashed, camera closed, and
the photo silently never appeared.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Same two fixes on the game page camera (gated)

**Gate:** `GameDetailView.swift` has ~115 lines of **someone else's uncommitted edits** (as of 2026-09-24). Before starting, run `git status --short PlayerPath/Views/Games/GameDetailView.swift`. If it still shows ` M`, **stop and ask Trey** whether to wait for those to be committed or to include them. Do not commit another session's work.

**Files:**
- Modify: `PlayerPath/Views/Games/GameDetailView.swift` (`saveGamePhoto`, currently ~line 894; state block near line 19; modifier chain near the `.alert(isGolf ? "Delete Round"…` at ~551)

**Interfaces:**
- Consumes: `SyncCoordinator.syncPhotosSoon(for:)` (Task 3), `ToastType.warning`, and the `.toast(isPresenting:type:message:duration:)` modifier (same one `PhotosView.swift:395` uses).

- [ ] **Step 1: Add state** next to `@State private var showingDeleteConfirmation = false`:

```swift
    @State private var showingPhotoSaveError = false
```

- [ ] **Step 2: Add the toast** to the modifier chain, directly after the `.alert(isGolf ? "Delete Round" : "Delete Game", …) { … } message: { … }` block:

```swift
        .toast(isPresenting: $showingPhotoSaveError, type: .warning, message: "Couldn't save your photo. Please try again.", duration: 3.0)
```

- [ ] **Step 3: Replace `saveGamePhoto`** with:

```swift
    private func saveGamePhoto(_ image: UIImage) {
        guard let athlete = game.athlete else { return }
        // Snapshot before the await (model access across suspension).
        let user = athlete.user
        Task {
            do {
                _ = try await PhotoPersistenceService().savePhoto(
                    image: image,
                    context: modelContext,
                    athlete: athlete,
                    game: game,
                    // Inherit the game's actual season, not just activeSeason —
                    // otherwise a photo on a past-season game mis-tags to the
                    // active season (matches the bulk-import path).
                    season: game.season ?? athlete.activeSeason
                )
                Haptics.success()
                SyncCoordinator.shared.syncPhotosSoon(for: user)
            } catch {
                ErrorHandlerService.shared.handle(error, context: "GameDetail.savePhoto", showAlert: false)
                // Toast, not alert — lands while the camera cover is dismissing.
                Haptics.error()
                showingPhotoSaveError = true
            }
        }
    }
```

- [ ] **Step 4: Build.** Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual check.** From a game page, take a photo. It appears in the game's photo grid and the gray badge clears within seconds. Repeat Task 5's forced-throw check here, then remove the throw.

- [ ] **Step 6: Commit** (only if the gate passed with a clean file, or Trey approved including the other edits)

```bash
git add PlayerPath/Views/Games/GameDetailView.swift
git commit -m "Game page camera: upload right after save; warn on save failure

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

## After all tasks

- Run `/review` on the commits (the playerpath-reviewer checks the SwiftData and sync footguns).
- Update memory `project_photo_fullscreen_swipe_viewer.md` with: default is aspect-fit; double-tap zooms to the tap point (the fit/fill toggle is gone); the clamp is fit-aware.
- Add a memory entry covering the photo-sync invariants from Task 3: passes are coalesced (`isSyncingPhotos`/`photoSyncRequested`) because `createPhoto` uses the non-idempotent `addDocument`; liveness is checked after every upload await; `cloudURL` lands on the model only together with `firestoreId`; and `needsSync` after upload comes from `PhotoEditSnapshot`. Also note the device checks still pending: 1f, 2-memory, 4a–4g.
