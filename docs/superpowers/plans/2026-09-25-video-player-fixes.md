# Videos Tab Player Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (or subagent-driven-development). Steps use `- [ ]`.

**Goal:** Fix the bugs found in the 2026-09-25 Videos-tab review. After these changes, slow-mo stays at the speed the user picked, landscape shows one close button, coach-drawing markers line up with the scrubber, zoom stays inside the video frame, taps respond immediately, frame-stepping gives precise readouts, cancelling Trim doesn't black out the video, and sharing from the grid uses a readable file name.

**Architecture:** Almost everything happens in `EnhancedVideoPlayer` (the controls) and its only caller, `VideoPlayerView`. `VideoClipPagerView` gains one piece of `@State` (the speed shared across a prev/next session). `VideoClipCard`/`VideoClipsView` get the grid-side fixes. There are eight tasks, ordered by user impact. Each one builds and commits on its own.

**Tech stack:** SwiftUI and AVFoundation (`AVPlayer.defaultRate`, iOS 16+). It reuses `AnnotationMarkersOverlay`, `ShareSheet` and `VideoClip.makeShareURL()`. There are no new files and no schema changes.

**Spec:** the review in this conversation (2026-09-25): bugs 1–5, likely bugs 6–7, and the frame-step order and precision items from the "Playback-control gaps" list.

## Global Constraints

- Deployment target **iOS 17.0**; `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
- `EnhancedVideoPlayer` has **exactly one** caller: `VideoPlayerView.swift:349`. Its memberwise init takes arguments in **declaration order**. New properties go exactly where each task says, and the call site must list them in the same order.
- `AnnotationMarkersOverlay` is shared with `CoachVideoPlayerView.swift:721`. **Don't change `AnnotationPlaybackViews.swift`.**
- Colors come from `Theme` / `@Environment(\.ppAccent)` only. Don't add new legacy tokens.
- Edit by matching the text. Line numbers are for orientation only (repo @ `5ba3cd6`).
- There's no Swift test target. "Test" means a clean build, the task's grep, and the task's simulator check. Checks that need a clip with coach drawings are marked **[device/data]**. If the sim has no such clip, record them as device-test pending. Don't skip them silently.
- Commit only the files each task names, one commit per task, directly to `main`. Never `git add -A`. Never touch version/build numbers.
- Commit message trailer: `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`

Build (every task):
```bash
cd /Users/Trey/Desktop/PlayerPath && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PlayerPath.xcodeproj \
  -scheme PlayerPath -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | head -20
```

## Verified facts (repo @ 5ba3cd6)

| Fact | Source |
|---|---|
| Speed is applied only inside `togglePlayPause`/`setPlaybackSpeed`; the other `play()` calls restart at 1× | `EnhancedVideoPlayer.swift:191,509`; `VideoPlayerView.swift:387,817` |
| Landscape draws two ✕ buttons: Enhanced's `.overlay(alignment: .topTrailing)` whenever `onClose != nil`, **and** `VideoPlayerView.landscapeControls` | `EnhancedVideoPlayer.swift:101-116`; `VideoPlayerView.swift:245-254,352` |
| Markers span the full frame width, sit **above** the controls, and have 20×30 hit targets | `VideoPlayerView.swift:364-374`; `AnnotationPlaybackViews.swift:50,58-74` |
| The coach player seeks to the annotation's frame before showing a drawing; the athlete player doesn't | `CoachVideoPlayerViewModel.swift:670-672` vs `VideoPlayerView.swift:394-408` |
| Zoom is `scaleEffect`+`offset` with no `.clipped()` anywhere up the tree | `EnhancedVideoPlayer.swift:81-91` |
| Single tap = play/pause, and a `count: 2` tap is always attached (it delays single taps) | `EnhancedVideoPlayer.swift:177-182` |
| Time observer every 0.5s; `formatTime` shows whole seconds; frame steps call `step` **before** `pause` | `EnhancedVideoPlayer.swift:466,529-540,580-585` |
| `EnhancedVideoPlayer.cleanup()` (on `onDisappear`) does `replaceCurrentItem(with: nil)`; `VideoPlayerView.onDisappear` removes the annotation listener + auto-show observer; Trim is a `fullScreenCover` over the player | `EnhancedVideoPlayer.swift:476-489`; `VideoPlayerView.swift:786-791,808` |
| The grid card shares `resolvedFileURL` (UUID name); `makeShareURL()` hard-links under a friendly name but touches the filesystem, so it must **not** run in a body | `VideoClipCard.swift:298-301`; `VideoClip+Sharing.swift:34-60` |
| `makeShareURL()` can return the clip's **real** file (`return source`) when both link and copy fail | `VideoClip+Sharing.swift:55-57` |
| `ShareSheet(items:cleanupFilesOnDismiss:)` defaults cleanup to **true**, which deletes every file URL it was given | `ShareSheet.swift:16,25-31` |
| Tapping a card fires a haptic twice (card + `onPlay`) | `VideoClipCard.swift:39`; `VideoClipsView.swift:692` |

## Review Focus

1. **Sharing from the grid must never delete the original clip.** Share → cancel, and Share → AirDrop/Save, must both leave the clip playable afterward. (Task 8 check 8c.)
2. **Slow-mo in every way playback can resume:** after a drawing is dismissed, after the app is backgrounded and foregrounded, when replaying from the end, and on prev/next. The chip and the actual speed must always match. (Task 1 check 1b.)
3. **Landscape stays edge-to-edge after `.clipped()`.** The video must still fill the notch and home-indicator areas and not get cut to the safe area. (Task 4 check 4b.)
4. **Scrubber drag vs the new tap handling.** Dragging the slider must never count as a tap that pauses or plays, and tapping when the controls are hidden must not pause. (Task 5 check 5b.)
5. **[device/data] Coach-drawing clip:** tapping a marker lands on the drawing's frame, the marker lines up with the scrubber position, and a drawing that auto-shows while zoomed lines up with the video. (Task 3 check 3b, Task 4 check 4c.)

---

### Task 1: Playback speed persists

**Files:**
- Modify: `PlayerPath/Views/Components/EnhancedVideoPlayer.swift`
- Modify: `PlayerPath/VideoPlayerView.swift`
- Modify: `PlayerPath/Views/Components/VideoClipPagerView.swift`

**Interfaces:**
- Produces: `EnhancedVideoPlayer.sharedSpeed: Binding<PlaybackSpeed>?` (declared directly after `forceAspectFit`); `VideoPlayerView.playbackSpeed: Binding<PlaybackSpeed>?` (declared directly after `navigation`).

- [ ] **Step 1: Add `sharedSpeed`.** In `EnhancedVideoPlayer`, directly after `var forceAspectFit: Bool = false`:

```swift
    /// Speed shared across a prev/next session (`VideoClipPagerView`), so
    /// moving to the next clip keeps 0.25× instead of snapping back to 1×.
    /// nil = this player's speed is its own.
    var sharedSpeed: Binding<PlaybackSpeed>? = nil
```

- [ ] **Step 2: Seed the speed in `setupPlayer()`.** Directly after `AudioSessionManager.configureForPlayback()`:

```swift
        if let sharedSpeed { playbackSpeed = sharedSpeed.wrappedValue }
        // Every play() starts at defaultRate, so the chosen speed also survives
        // the resumes this view doesn't own (VideoPlayerView's drawing dismiss
        // and scene-phase resume).
        player.defaultRate = Float(playbackSpeed.value)
```

- [ ] **Step 3: Replace `togglePlayPause()` completely:**

```swift
    private func togglePlayPause() {
        if isPlaying {
            player.pause()
        } else if isAtEnd {
            // Replay from the start; play() uses defaultRate, so slow-mo holds.
            isAtEnd = false
            player.seek(to: .zero) { _ in
                Task { @MainActor in self.player.play() }
            }
        } else {
            player.play()
        }
        Haptics.light()
    }
```

- [ ] **Step 4: Replace `setPlaybackSpeed(_:)` completely:**

```swift
    private func setPlaybackSpeed(_ speed: PlaybackSpeed) {
        playbackSpeed = speed
        sharedSpeed?.wrappedValue = speed
        player.defaultRate = Float(speed.value)
        if isPlaying {
            player.rate = Float(speed.value)
        }
        Haptics.light()
    }
```

- [ ] **Step 5: Landscape capsule matches portrait.** In `speedControlsCompact`, change `.background(ppAccent)` to:

```swift
                .background(playbackSpeed == .normal ? Color.white.opacity(0.2) : ppAccent)
```

- [ ] **Step 6: Thread it through `VideoPlayerView`.** Directly after `var navigation: ClipNavigation? = nil`:

```swift
    /// Speed shared across the pager session; nil for a standalone clip.
    var playbackSpeed: Binding<PlaybackSpeed>? = nil
```

In the `EnhancedVideoPlayer(` call, add `sharedSpeed: playbackSpeed` as the **last** argument (after `forceAspectFit: coachFeedbackVideoID != nil`, add a comma).

- [ ] **Step 7: Own the speed in the pager.** In `VideoClipPagerView`, under `@State private var currentID: UUID`:

```swift
    /// One speed for the whole prev/next session — each clip gets a fresh
    /// player (`.id(clip.id)`), so it can't live in the player's own @State.
    @State private var playbackSpeed: PlaybackSpeed = .normal
```

In the `VideoPlayerView(` call, after the `navigation:` argument, add `playbackSpeed: $playbackSpeed`.

- [ ] **Step 8: Build.** Expect `BUILD SUCCEEDED`. Grep: `grep -n "player.rate" PlayerPath/Views/Components/EnhancedVideoPlayer.swift` should show only the one line inside `setPlaybackSpeed`.

- [ ] **Step 9: Sim check 1b.** Open any clip from the Videos grid and set 0.25×.
  - (a) Play → background the app → foreground: it resumes slow, and the chip still reads 0.25x.
  - (b) Let it play to the end → Replay: still slow.
  - (c) Press › (next clip) → Play: still slow, and the chip reads 0.25x. The speed is seeded in `onAppear`, so a single-frame "1x" before it switches is expected. A visible, lasting 1x is a failure.
  - (d) Rotate to landscape: the capsule is neutral at 1x and accented at 0.25x.
  - (e) **[device/data]** On a clip with a coach drawing, dismiss the drawing: it resumes slow.

- [ ] **Step 10: Commit.**

```bash
git add PlayerPath/Views/Components/EnhancedVideoPlayer.swift PlayerPath/VideoPlayerView.swift PlayerPath/Views/Components/VideoClipPagerView.swift
git commit -m "Player: keep the chosen playback speed across resumes and prev/next

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: One close button in landscape

**Files:**
- Modify: `PlayerPath/Views/Components/EnhancedVideoPlayer.swift`
- Modify: `PlayerPath/VideoPlayerView.swift`

**Interfaces:**
- Removes: `EnhancedVideoPlayer.onClose` (the only caller stops passing it).

- [ ] **Step 1: In `EnhancedVideoPlayer`, delete** the `onClose` property and its doc comment (`/// Called when the user taps the close button…` + `var onClose: (() -> Void)?`). Also delete the whole `.overlay(alignment: .topTrailing) { if isLandscape, let onClose, showControls { … } }` block that follows `.frame(width: geometry.size.width, height: geometry.size.height)`.

- [ ] **Step 2: In `VideoPlayerView`**, delete the line `onClose: { dismiss() },` from the `EnhancedVideoPlayer(` call. In `landscapeControls`, replace the inline close `Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") … } .accessibilityLabel("Close video player")` with the existing `closeButton` property:

```swift
                closeButton
```

- [ ] **Step 3: Build.** Grep: `grep -n "onClose" PlayerPath/Views/Components/EnhancedVideoPlayer.swift PlayerPath/VideoPlayerView.swift` should return nothing.

- [ ] **Step 4: Sim check.** Open a clip and rotate to landscape: there's exactly one ✕ at top-right, and it closes the player. Portrait is unchanged.

- [ ] **Step 5: Commit.**

```bash
git add PlayerPath/Views/Components/EnhancedVideoPlayer.swift PlayerPath/VideoPlayerView.swift
git commit -m "Player: remove the duplicate landscape close button

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Coach markers ride the scrubber; drawings land on their frame

**Files:**
- Modify: `PlayerPath/Views/Components/EnhancedVideoPlayer.swift`
- Modify: `PlayerPath/VideoPlayerView.swift`

**Interfaces:**
- Produces: `EnhancedVideoPlayer.annotationMarkers: [VideoAnnotation]` and `onTapDrawingMarker: ((VideoAnnotation) -> Void)?`, declared directly after `sharedSpeed`, in that order.

- [ ] **Step 1: Add the properties** directly after `var sharedSpeed: Binding<PlaybackSpeed>? = nil`:

```swift
    /// Coach annotations drawn as a marker row directly above the scrubber, so
    /// each marker sits where the scrubber thumb will be at that moment. They
    /// live inside the controls bar, so they fade with it and can never sit on
    /// top of the speed chip. Empty = no row.
    var annotationMarkers: [VideoAnnotation] = []
    /// Tap on a drawing marker. nil = markers are inert.
    var onTapDrawingMarker: ((VideoAnnotation) -> Void)? = nil
```

- [ ] **Step 2: Add the inset constant** directly above `private var timelineView: some View {`:

```swift
    /// Horizontal inset of the marker row so t=0 / t=end line up with the
    /// slider thumb's CENTER at its travel limits (the thumb never reaches
    /// the track's edges). Half the system thumb width — tuned in the sim.
    private static let markerTrackInset: CGFloat = 14
```

- [ ] **Step 3: Add the marker row** as the first child of the `VStack(spacing: 4)` in `timelineView`, directly above `Slider(`:

```swift
            if !annotationMarkers.isEmpty, durationLoaded, duration > 0 {
                AnnotationMarkersOverlay(
                    annotations: annotationMarkers,
                    duration: duration,
                    onTapDrawing: onTapDrawingMarker
                )
                .frame(height: 30)
                .padding(.horizontal, Self.markerTrackInset)
            }
```

- [ ] **Step 4: In `VideoPlayerView.activePlayerView`**, delete the whole `if activeDrawingOverlay == nil, !coachAnnotations.isEmpty, let duration = videoDuration, duration > 0 { AnnotationMarkersOverlay(…) }` block and its `// Tappable timeline markers…` comment. Then add these two arguments at the end of the `EnhancedVideoPlayer(` call, after `sharedSpeed: playbackSpeed` (add a comma):

```swift
                annotationMarkers: activeDrawingOverlay == nil ? coachAnnotations : [],
                onTapDrawingMarker: { annotation in showDrawing(for: annotation) }
```

- [ ] **Step 5: Seek to the drawing's frame.** In `showDrawing(for:)`, directly after `player?.pause()`:

```swift
        // Show the drawing on the frame it was drawn on, matching
        // CoachVideoPlayerViewModel.showDrawingOverlay (which also seeks for
        // its initial auto-show, so opening a clip lands on the first
        // drawing's frame in both players). The auto-show observer
        // ticks once a second, so without this the drawing can sit over a
        // frame up to ~1s past its own. Already-shown IDs stay in
        // shownDrawingIDs, so seeking back can't re-trigger auto-show.
        player?.seek(
            to: CMTime(seconds: annotation.timestamp, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
```

- [ ] **Step 6: Build.** Grep: `grep -n "AnnotationMarkersOverlay" PlayerPath/VideoPlayerView.swift` should return nothing.

- [ ] **Step 7: Sim check 3b [device/data].** On a clip with 2+ coach drawings:
  - (a) Markers show above the scrubber and fade with the controls.
  - (b) Drag the thumb onto a marker: the thumb's center and the bar line up to within about 2pt at both the start and end of the clip. If they don't, adjust `markerTrackInset` and rebuild.
  - (c) Tap a marker: the video pauses **on the drawing's frame** and the drawing appears. Dismissing it resumes playback.
  - (d) The speed chip is always tappable, with no marker stealing the tap.
  - (e) A clip with no coach feedback has no extra row and no layout shift.

- [ ] **Step 8: Commit.**

```bash
git add PlayerPath/Views/Components/EnhancedVideoPlayer.swift PlayerPath/VideoPlayerView.swift
git commit -m "Player: align coach markers with the scrubber and open drawings on their frame

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Zoom stays in frame and yields to drawings

**Files:**
- Modify: `PlayerPath/Views/Components/EnhancedVideoPlayer.swift`
- Modify: `PlayerPath/VideoPlayerView.swift`

**Interfaces:**
- Produces: `EnhancedVideoPlayer.suppressZoom: Bool` (declared directly after `onTapDrawingMarker`); private `resetZoom()` and `clampedPan(_:in:)`, which Task 5 uses.

- [ ] **Step 1: Add the property** directly after `var onTapDrawingMarker: ((VideoAnnotation) -> Void)? = nil`:

```swift
    /// True while a coach drawing is on screen. The drawing overlay is laid
    /// out against the UNZOOMED video rect, so zoom snaps back to 1× the
    /// moment it appears.
    var suppressZoom: Bool = false
```

- [ ] **Step 2: Clip the zoomed video.** In `body`, change the representable's modifier chain to add `.clipped()` **before** `.ignoresSafeArea`. `ignoresSafeArea` expands the frame its child is laid out in, so the clip happens against the full-bleed bounds in landscape:

```swift
                VideoPlayerRepresentable(
                    player: player,
                    videoGravity: resolvedVideoGravity
                )
                    .scaleEffect(zoomScale, anchor: .center)
                    .offset(panOffset)
                    .clipped()
                    .ignoresSafeArea(edges: isLandscape ? .all : [])
```

(Keep the existing edge-to-edge comment above `.ignoresSafeArea`.)

- [ ] **Step 3: Add helpers** directly above `// MARK: - Gesture Layer`:

```swift
    private func resetZoom() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            zoomScale = 1.0; panOffset = .zero; lastPanOffset = .zero
        }
    }

    /// Keeps the pan inside the zoomed content at the CURRENT scale — also
    /// re-applied while pinching out, or a pan made at 4× leaves black bars
    /// at 2×.
    private func clampedPan(_ offset: CGSize, in size: CGSize) -> CGSize {
        let maxX = (zoomScale - 1) * size.width / 2
        let maxY = (zoomScale - 1) * size.height / 2
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }
```

- [ ] **Step 4: Replace the `SimultaneousGesture(…)` argument** of `.gesture(` in `gestureLayer(geometry:)` with:

```swift
                SimultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            guard !suppressZoom else { return }
                            let delta = value / lastZoomScale
                            lastZoomScale = value
                            zoomScale = min(max(zoomScale * delta, 1.0), 4.0)
                            panOffset = clampedPan(panOffset, in: geometry.size)
                        }
                        .onEnded { _ in
                            lastZoomScale = 1.0
                            lastPanOffset = panOffset
                            if zoomScale <= 1.0 { resetZoom() }
                        },
                    DragGesture()
                        .onChanged { value in
                            guard zoomScale > 1.0 else { return }
                            panOffset = clampedPan(
                                CGSize(
                                    width: lastPanOffset.width + value.translation.width,
                                    height: lastPanOffset.height + value.translation.height
                                ),
                                in: geometry.size
                            )
                            showControlsTemporarily()
                        }
                        .onEnded { _ in lastPanOffset = panOffset }
                )
```

Then replace the body of the existing `.onTapGesture(count: 2) { … }` with `resetZoom()`. Task 5 replaces that modifier anyway.

- [ ] **Step 5: Reset on drawing.** In `body`, after `.onChange(of: scenePhase) { … }`:

```swift
        .onChange(of: suppressZoom) { _, suppressed in
            if suppressed { resetZoom() }
        }
```

- [ ] **Step 6: Pass it in.** In the `VideoPlayerView` `EnhancedVideoPlayer(` call, add as the last argument (after `onTapDrawingMarker:`, add a comma):

```swift
                suppressZoom: activeDrawingOverlay != nil
```

- [ ] **Step 7: Build.**

- [ ] **Step 8: Sim check.**
  - 4a (portrait): pinch to 3× and pan to a corner. Nothing spills over the nav bar or the detail panel below. Pinch back to about 1.5×: no black bars, and the pan stays pulled in.
  - 4b (landscape): at 1× the video is still edge-to-edge through the notch and home-indicator areas, and it stays clipped when zoomed.
  - 4c **[device/data]**: zoom to 2×, then let a coach drawing auto-show. Zoom snaps to 1× and the drawing lines up with the player.

- [ ] **Step 9: Commit.**

```bash
git add PlayerPath/Views/Components/EnhancedVideoPlayer.swift PlayerPath/VideoPlayerView.swift
git commit -m "Player: clip zoom to the video frame, re-clamp pan, reset zoom for coach drawings

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Tap shows the controls first; no double-tap lag at 1×

**Files:**
- Modify: `PlayerPath/Views/Components/EnhancedVideoPlayer.swift`

**Interfaces:**
- Consumes: `resetZoom()` (Task 4).

Behavior: when the controls are **hidden**, a tap only reveals them (the clip keeps playing). When they're **visible**, a tap toggles play/pause, as it does today. Double-tap (reset zoom) only exists while zoomed, so at 1× single taps fire immediately.

- [ ] **Step 1: Replace both tap modifiers** at the end of `gestureLayer(geometry:)` (the `.onTapGesture(count: 2) { … }` and `.onTapGesture { togglePlayPause(); showControlsTemporarily() }`) with:

```swift
            // Double-tap resets zoom, so it only exists while zoomed. Left on at
            // 1×, SwiftUI holds every single tap ~0.3s to rule out a double.
            .gesture(
                TapGesture(count: 2).onEnded { resetZoom() },
                including: zoomScale > 1 ? .all : .subviews
            )
            .onTapGesture { handleSingleTap() }
```

⚠️ The mask must be `.subviews`, **never `.none`**. `.none` also disables every gesture below this modifier, and that includes the pinch/pan `SimultaneousGesture` attached just above.

- [ ] **Step 2: Add the handler** directly below `togglePlayPause()`:

```swift
    /// Hidden controls: the tap just brings them back (reaching for the
    /// scrubber shouldn't pause the clip). Visible controls: play/pause.
    private func handleSingleTap() {
        if showControls { togglePlayPause() }
        showControlsTemporarily()
    }
```

- [ ] **Step 3: Build.**

- [ ] **Step 4: Sim check 5b.**
  - (a) Play, wait 3s for the controls to fade, tap the video: the controls appear and it **keeps playing**. Tap again: it pauses, instantly with no lag.
  - (b) Drag the scrubber: it never toggles play.
  - (c) Pinch to 2× → double-tap: zoom resets. At 1×, a double-tap just toggles twice (acceptable).
  - (d) VoiceOver: the Play/Pause button still works.

- [ ] **Step 5: Commit.**

```bash
git add PlayerPath/Views/Components/EnhancedVideoPlayer.swift
git commit -m "Player: tap reveals hidden controls instead of pausing; drop double-tap lag at 1x

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Frame-step precision

**Files:**
- Modify: `PlayerPath/Views/Components/EnhancedVideoPlayer.swift`

- [ ] **Step 1: Pause before stepping.** Replace `stepForward()` and `stepBackward()`:

```swift
    // Pause FIRST: stepping a playing item is overridden by playback.
    private func stepForward() {
        player.pause()
        player.currentItem?.step(byCount: 1)
        Haptics.light()
    }

    private func stepBackward() {
        isAtEnd = false
        player.pause()
        player.currentItem?.step(byCount: -1)
        Haptics.light()
    }
```

- [ ] **Step 2: Make the auto-hide timer start only when playback starts.** `body` re-evaluates on every `currentTime` tick, and `player.publisher(for:)` builds a new KVO publisher each time. A fresh publisher that SwiftUI re-subscribes to replays its current value (`.initial`), which re-runs `scheduleControlsHide()` and restarts the 3s timer. At 10 Hz, the controls could then never hide. Replace the `.onReceive(player.publisher(for: \.timeControlStatus)) { … }` closure body so it only acts on the paused→playing transition:

```swift
        .onReceive(player.publisher(for: \.timeControlStatus)) { status in
            let nowPlaying = status == .playing
            // Edge-triggered: a re-subscribe replays the current status, and
            // rescheduling on every replay would keep pushing the auto-hide
            // back so the controls never fade.
            let started = nowPlaying && !isPlaying
            isPlaying = nowPlaying
            if started && showControls { scheduleControlsHide() }
        }
```

- [ ] **Step 3: Smoother scrubber.** In `setupPlayer()`, change the time observer's interval from `0.5` to `0.1`:

```swift
            let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
```

- [ ] **Step 4: Tenths for short clips.** Replace `formatTime(_:)`:

```swift
    /// m:ss, plus tenths for clips under a minute — the swing/pitch clips this
    /// player mostly shows, where a whole-second readout doesn't move while
    /// frame-stepping. Truncates (never rounds), so 59.96s can't print "0:60.0".
    private func formatTime(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        if duration < 60 {
            let tenths = Int((clamped * 10).rounded(.down))
            return String(format: "%d:%02d.%d", tenths / 600, (tenths % 600) / 10, tenths % 10)
        }
        let total = Int(clamped)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
```

- [ ] **Step 5: Build.**

- [ ] **Step 6: Sim check.**
  - (a) On a short clip, press ▶︎| repeatedly while playing: the first press pauses and advances one frame, and the readout changes by 0.0–0.1 per step.
  - (b) The scrubber moves smoothly during playback.
  - (c) A clip over 60s shows `m:ss` with no tenths.
  - (d) The digits don't jitter in width (`monospacedDigit` is already applied).
  - (e) **Auto-hide still works:** press Play without touching anything else. The controls fade after about 3s. Tap to reveal them: they fade again about 3s later.

- [ ] **Step 7: Commit.**

```bash
git add PlayerPath/Views/Components/EnhancedVideoPlayer.swift
git commit -m "Player: pause before frame-step, smoother scrubber, tenths on short clips

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Cancelling Trim doesn't kill the player (reproduce first)

**Files:**
- Modify: `PlayerPath/Views/Components/EnhancedVideoPlayer.swift`
- Modify: `PlayerPath/VideoPlayerView.swift`

Background: presenting a `fullScreenCover` fires `onDisappear` on the view underneath, and SwiftUI also **cancels `.task` on disappear and restarts it on re-appear**. So after a cancelled trim, `VideoPlayerView`'s `.task(id: clip.version)` may re-run `setupPlayer()` and build a fresh player. That would hide the dead item. Which of the two wins is only knowable by running it.

- [ ] **Step 1: Reproduce on the current build.** In the sim, open an **uploaded** clip (Trim only shows for `isUploaded`). Play to about the middle, pause, then ⋯ → Trim Clip → Cancel. Record which of these happens:
  - **(A) Black screen, or Play does nothing:** the bug is real. Continue with Steps 2–5.
  - **(B) The loading spinner shows, then the clip is back at 0:00 and plays:** `.task` re-ran and rebuilt the player. It's not broken, just a reload. Skip Steps 2–5, and put "Task 7: outcome B, cancelled trim reloads the clip from 0:00; not fixed" in the final report as a minor.
  - **(C) Same position, and it plays:** refuted. Skip Steps 2–5 and note it in the final report.

- [ ] **Step 2: Don't destroy the owner's player item.** `VideoPlayerView` owns the `AVPlayer` in `@State`, and releasing that state (dismiss, or pager `.id` swap) frees it. In `EnhancedVideoPlayer.cleanup()`, delete the line:

```swift
        player.replaceCurrentItem(with: nil)
```

`player.pause()` stays. `onAppear` → `setupPlayer()` re-adds the time observer when the view comes back.

- [ ] **Step 3: Keep coach listeners across the Trim cover.** In `VideoPlayerView`, replace the `.onDisappear { … }` body:

```swift
        .onDisappear {
            player?.pause()
            // Presenting the Trim fullScreenCover fires onDisappear on this
            // view. Tearing down here would leave a cancelled trim with no
            // annotation listener or auto-show observer (a saved trim bumps
            // clip.version and .task rebuilds both anyway).
            guard !showingRetrimFlow else { return }
            stopAutoShowObserver()
            coachAnnotationsListener?.remove()
            coachAnnotationsListener = nil
        }
```

- [ ] **Step 4: Build.**

- [ ] **Step 5: Sim check.**
  - (a) Repeat Step 1: after Cancel, Play works and the scrubber moves. Outcome (B) is acceptable here too: a reload is fine, a dead player is not.
  - (b) Trim and save: the player reloads the trimmed clip.
  - (c) Close the player mid-playback: the audio stops.
  - (d) Press prev/next several times: only one clip's audio is ever heard.

- [ ] **Step 6: Commit.**

```bash
git add PlayerPath/Views/Components/EnhancedVideoPlayer.swift PlayerPath/VideoPlayerView.swift
git commit -m "Player: survive a cancelled re-trim instead of going black

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Grid Share uses the friendly name; single haptic on tap

**Files:**
- Modify: `PlayerPath/Views/Components/VideoClipCard.swift`
- Modify: `PlayerPath/VideoClipsView.swift`

- [ ] **Step 1: Add state** to `VideoClipCard`, under `@State private var showingTagSheet = false`:

```swift
    /// Friendly-named share link, built on tap (makeShareURL touches the
    /// filesystem, so never in a body). Non-nil presents the share sheet.
    @State private var shareURL: URL?
```

- [ ] **Step 2: Replace the `ShareLink(item: video.resolvedFileURL) { … }`** inside `videoMenuItems` with:

```swift
            Button {
                if let url = video.makeShareURL() {
                    shareURL = url
                } else {
                    errorMessage = "Could not prepare this video for sharing."
                    showingError = true
                }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
```

- [ ] **Step 3: Present the sheet.** After `.sheet(isPresented: $showingGameLinker) { … }`:

```swift
        .sheet(isPresented: Binding(
            get: { shareURL != nil },
            set: { if !$0 { shareURL = nil } }
        )) {
            if let shareURL {
                // cleanupFilesOnDismiss MUST stay false: makeShareURL() falls
                // back to the clip's REAL file when link + copy both fail, and
                // cleanup would delete the athlete's original video. The temp
                // link is replaced on the next share anyway.
                ShareSheet(items: [shareURL], cleanupFilesOnDismiss: false)
            }
        }
```

- [ ] **Step 4: Single haptic.** In `VideoClipsView`, inside the card's `onPlay` `else` branch, delete the `Haptics.light()` that follows `playerSession = VideoPlayerSession(…)`. The card's button already fires one.

- [ ] **Step 5: Build.** Grep: `grep -n "cleanupFilesOnDismiss: false" PlayerPath/Views/Components/VideoClipCard.swift` should return exactly 1 line.

- [ ] **Step 6: Sim check 8c.**
  - (a) Long-press a card → Share: the sheet shows a readable name (e.g. "Double - Apr 22, 2026").
  - (b) Cancel the sheet → open the clip: it plays.
  - (c) Share → Save to Files → open the clip again: it plays.
  - (d) Do the same from the ⋯ menu on the card.
  - (e) Tapping a card gives one haptic, not two.

- [ ] **Step 7: Commit.**

```bash
git add PlayerPath/Views/Components/VideoClipCard.swift PlayerPath/VideoClipsView.swift
git commit -m "Videos: share clips from the grid under a readable name; single tap haptic

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

## Final call-site shape (after Tasks 1–4)

```swift
            EnhancedVideoPlayer(
                player: player,
                preloadedDuration: videoDuration,
                clipIsLandscape: clipIsLandscape,
                forceAspectFit: coachFeedbackVideoID != nil,
                sharedSpeed: playbackSpeed,
                annotationMarkers: activeDrawingOverlay == nil ? coachAnnotations : [],
                onTapDrawingMarker: { annotation in showDrawing(for: annotation) },
                suppressZoom: activeDrawingOverlay != nil
            )
```

## Out of scope — needs Trey's call (not in this plan)

- **Autoplay on open / on prev-next.** Right now every clip opens paused.
- **Loop.** `CoachVideoPlayerViewModel` already has a whole-clip loop toggle that could be reused.
- **Skip size.** ±5s is half of a short clip; ±1s or ±2s may fit better.
- **Live scrubbing / filmstrip.** The biggest improvement for swing review. The coach player's filmstrip scrubber could be reused.
- The landscape top bar (menu, counter, ✕) doesn't fade with the bottom controls.
- The double haptic in selection mode (card `light` + `selection`).
