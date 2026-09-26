# Video Player Chrome Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the unreadable top bar on the athlete video player (portrait) and tidy three visual rough edges found in the 2026-09-26 screenshot review.

**Architecture:** Four small, independent view-layer edits. The top bar becomes solid dark chrome that matches the video's navy backing, the toolbar glyphs follow the iOS 26 "plain glyph inside glass" rule via `ToolbarSymbol`, the ±5s skips hide on short clips, and the detail panel's action bar drops its white fill so the cream runs through.

**Tech Stack:** SwiftUI (iOS 17+ deployment target, iOS 26 glass paths gated in `GlassChrome.swift`), AVKit.

**Spec:** the screenshot review in conversation (2026-09-26). Findings, in priority order:
1. "‹ 1 of 2 ›" and the status-bar clock are dark on navy, so both are unreadable. The disabled chevron also looks identical to the enabled one.
2. X (`xmark.circle.fill` inside iOS 26 glass = circle in a circle) doesn't match ••• (plain glyph, terracotta).
3. ±5s skip on a 3.4s clip is meaningless.
4. The action bar is white (`Theme.card`) under a cream (`Theme.surface`) panel.

## Global Constraints

- iOS 17 deployment target: anything iOS 26-only goes through `GlassChrome.swift` helpers, never an inline `#available` at the call site.
- No test target exists for Swift. Verification = clean `xcodebuild` + a simulator check.
- Build: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PlayerPath.xcodeproj -scheme PlayerPath -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
- Don't touch version/build numbers (Trey owns them).
- The app forces `.preferredColorScheme(.light)` (MainAppView). Only the nav bar is scoped dark here, never the whole view.
- Landscape (`vSizeClass == .compact`) hides the nav bar and draws its own overlay (`landscapeControls`). Its visuals must not change, except that the pager label gains disabled dimming.

## Review Focus

1. **Standalone clip (no pager):** opened from Highlights/Journal/Game rows, `navigation == nil`. The bar must still be navy with a light status bar and a white X, and no principal item.
2. **Pre-iOS 26 fallback:** `ToolbarSymbol.close` must return the circled glyph so the button isn't a bare "x" floating on a solid bar with no glass capsule.
3. **Pager at either end:** on clip 1 of N the ‹ must be visibly dimmed; on N of N the › must be. This is the case the screenshot showed.
4. **Loading/error states:** `loadingView`/`errorView` also sit on `tileNavyDark`, so the new bar must match them with no seam.
5. **Clip exactly 10.0s, and duration not yet loaded:** at ≥10s the skips show; while loading they stay hidden, with no flash of skips on a short clip.

---

### Task 1: Dark top bar + readable pager control

**Files:**
- Modify: `PlayerPath/VideoPlayerView.swift`, including `clipNavigationControl` (~lines 259–292), its two call sites (~244, ~768), and the modifier chain after `.toolbar(vSizeClass == .compact ? .hidden : .visible, for: .navigationBar)` (~755)

**Why it's broken:** `videoPlayerContent.background(Theme.tileNavyDark)` (~730) bleeds up under the transparent nav bar, but the portrait pager control is called with `onDark: false` → `Theme.textPrimary` (dark ink). The navigation stack is light-scheme, so the status bar is dark too. The disabled chevron uses an explicit `foregroundStyle`, which SwiftUI doesn't dim on `.disabled`.

**Verified preconditions (2026-09-26):**
- Every presenter uses `.fullScreenCover`: VideoClipsView, HighlightsView, JournalView, VideoClipRow, PracticeDetailView, the pager from VideoClipsView/AdvancedSearchView, and the dead DashboardView. So this `NavigationStack` owns the status bar, and `toolbarColorScheme` can flip it.
- No `UIViewControllerBasedStatusBarAppearance = NO` in the Info.plist or build settings, so per-controller status bar styles apply.
- `AppDelegate.configureAppearance()` sets `configureWithDefaultBackground()` for all nav bars. Before iOS 26 this bar was therefore a light blur, not navy, and this change turns it navy on every OS. `.toolbarBackground` overrides the global appearance for this stack only. The title font attributes are unaffected (the view has no title).

- [ ] **Step 1: Paint the nav bar navy and scope it dark.** Directly after the `.toolbar(... .hidden : .visible, for: .navigationBar)` line, add:

```swift
            // The video's navy backing runs up under the bar; paint the bar the
            // same navy and scope it dark so the status bar, pager label and
            // glyphs read light. Bar only — the detail panel below stays cream.
            .toolbarBackground(Theme.tileNavyDark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
```

- [ ] **Step 2: Drop the `onDark` parameter (both call sites are now on dark) and dim disabled chevrons.** Replace the whole `clipNavigationControl` function with:

```swift
    /// ‹ 3 of 42 › — portrait toolbar (dark bar) and landscape overlay (over
    /// video); both are dark, so it's always white. Disabled chevrons dim by
    /// hand: an explicit foregroundStyle opts out of the automatic dimming.
    private func clipNavigationControl(_ navigation: ClipNavigation) -> some View {
        HStack(spacing: 14) {
            Button {
                Haptics.selection()
                navigation.onPrevious?()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
            }
            .disabled(navigation.onPrevious == nil)
            .opacity(navigation.onPrevious == nil ? 0.35 : 1)
            .accessibilityLabel("Previous video")

            Text("\(navigation.position) of \(navigation.total)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .accessibilityLabel("Video \(navigation.position) of \(navigation.total)")

            Button {
                Haptics.selection()
                navigation.onNext?()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
            }
            .disabled(navigation.onNext == nil)
            .opacity(navigation.onNext == nil ? 0.35 : 1)
            .accessibilityLabel("Next video")
        }
        .foregroundStyle(Color.white)
        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
    }
```

- [ ] **Step 3: Update both call sites.** In `landscapeControls`: `clipNavigationControl(navigation, onDark: true)` → `clipNavigationControl(navigation)`. In the `.principal` `ToolbarItem`: `clipNavigationControl(navigation, onDark: false)` → `clipNavigationControl(navigation)`. Confirm there are no other callers: `grep -n 'clipNavigationControl' PlayerPath/VideoPlayerView.swift` should show exactly the definition + 2 calls.

- [ ] **Step 4: Build.** Run the Global Constraints build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Sim check.** Open Videos tab → any clip in a list of 2+ (pager), then a clip from Highlights (standalone). Check: the bar is navy with no seam against the video, the clock is white, "1 of 2" is white, ‹ is dimmed on clip 1, › is dimmed on the last clip, and rotating to landscape looks unchanged. Open a cloud-only clip so the "Downloading from cloud..." `loadingView` shows: its navy should meet the bar with no seam.

- [ ] **Step 6: Check the one side effect.** Tap •••. The menu may now render in dark style, because UIKit menus inherit the source view's trait collection and the bar is now dark-scheme. That's expected and acceptable for dark player chrome. If Trey objects, it's a follow-up, not a blocker. Also check that sheets opened from the menu (Edit Play Result, Link to Game) still come up light. They should, because they present from the view controller, not the bar.

- [ ] **Step 7: Commit.**

```bash
git add PlayerPath/VideoPlayerView.swift
git commit -m "Video player: dark top bar so pager label and status bar are readable"
```

---

### Task 2: Matching toolbar glyphs (X and •••)

**Files:**
- Modify: `PlayerPath/Views/Navigation/GlassChrome.swift` (`enum ToolbarSymbol`, lines 15–29)
- Modify: `PlayerPath/VideoPlayerView.swift`, the `.toolbar { }` leading + trailing items (~756–775)

**Interfaces:**
- Produces: `ToolbarSymbol.close: String`, which is `"xmark"` on iOS 26+ and `"xmark.circle.fill"` below.

`closeButton` (the `xmark.circle.fill` + shadow) stays as it is. After this task only the landscape overlay uses it, and there it floats over video with no glass capsule, so the circle is correct.

- [ ] **Step 1: Add the symbol.** In `ToolbarSymbol`, after `more`:

```swift
    /// Close button on a full-screen cover's toolbar.
    static var close: String {
        if #available(iOS 26, *) { return "xmark" }
        return "xmark.circle.fill"
    }
```

- [ ] **Step 2: Toolbar close item.** Replace the trailing `ToolbarItem`'s body (`closeButton`) with:

```swift
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: ToolbarSymbol.close)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Close video player")
                }
```

- [ ] **Step 3: White ••• on the dark bar.** In the leading `ToolbarItem`, add `.foregroundStyle(.white)` to the `Image(systemName: ToolbarSymbol.more)` (before its `.accessibilityLabel`).

- [ ] **Step 4: Build.** Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Sim check (iOS 26).** Both buttons should be the same glass circle with a plain white glyph: no inner gray disc on X and no terracotta dots. If ••• is still terracotta (the toolbar tint overriding the label), add `.tint(.white)` to the `Menu` itself, rebuild and recheck. The ••• menu still opens with every item, and X dismisses.

- [ ] **Step 6: Commit.**

```bash
git add PlayerPath/Views/Navigation/GlassChrome.swift PlayerPath/VideoPlayerView.swift
git commit -m "Video player: plain X and white ellipsis match inside iOS 26 glass"
```

---

### Task 3: Hide ±5s skips on short clips

**Files:**
- Modify: `PlayerPath/Views/Components/EnhancedVideoPlayer.swift`, `playbackControlsView` (lines 345–403) + a new computed property beside it

`EnhancedVideoPlayer` has exactly one caller (`VideoPlayerView.activePlayerView`), so this affects only the athlete player. The coach player is a separate view.

- [ ] **Step 1: Add the gate** directly above `private var playbackControlsView`:

```swift
    /// ±5s only earns its slot on a clip long enough to skip within — on a
    /// 3s swing either button just slams to an end; frame-step is the tool.
    /// Hidden until the duration is known so a short clip never flashes them.
    private static let minDurationForSkip: Double = 10
    private var showsSkipButtons: Bool {
        durationLoaded && duration >= Self.minDurationForSkip
    }
```

- [ ] **Step 2: Wrap both skip buttons.** Put the "Skip back 5 seconds" `Button` (`gobackward.5`) inside `if showsSkipButtons { ... }`, and do the same, separately, for the "Skip forward 5 seconds" `Button` (`goforward.5`). Leave the frame-step and play/pause buttons unconditional. The HStack's order stays frame-back, [skip-back], play, [skip-fwd], frame-fwd.

- [ ] **Step 3: Build.** Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Sim check.** A clip under 10s shows ⏮ ▶ ⏭ only, centered, in portrait and landscape. A clip of 10s or more shows all five, and ±5s still works. Paging from a short clip to a long one (pager) makes the skips appear without a stale layout. On a **local** long clip the skips may pop in a beat after the player appears. That's expected: `VideoPlayerView` shows local players before `videoDuration` resolves, and `durationLoaded` flips when either load finishes. An indefinite duration (NaN) fails `>=`, so the skips stay hidden, which is the safe default.

- [ ] **Step 5: Commit.**

```bash
git add PlayerPath/Views/Components/EnhancedVideoPlayer.swift
git commit -m "Video player: hide 5s skips on clips shorter than 10s"
```

---

### Task 4: Cream action bar

**Files:**
- Modify: `PlayerPath/Views/Player/AthleteClipReviewDetail.swift:247`

The parent `VStack` already sets `.background(Theme.surface)` (line 56), so the bar's own `Theme.card` fill is the only thing making it white. The hairline overlay at line 248 stays as the separator. The empty band under the buttons is the home-indicator safe area, which is standard and not padding, so no layout change.

- [ ] **Step 1: Delete** the line `.background(Theme.card)` from `bottomBar`.

- [ ] **Step 2: Build.** Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Sim check.** The panel + bar + home-indicator band are one continuous cream with a single hairline above the buttons. Check a clip with a coach review too (the scrolling-panel variant): the bar stays pinned and the content above doesn't show through.

- [ ] **Step 4: Commit.**

```bash
git add PlayerPath/Views/Player/AthleteClipReviewDetail.swift
git commit -m "Clip detail: action bar sits on the panel's cream, not white"
```
