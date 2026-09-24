# Capture Overlays: Liquid Glass + Palette — Implementation Plan (Batch 1 of 5)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (or subagent-driven-development). Steps use `- [ ]`.

**Goal:** Replace the hand-rolled "fake glass" panels and `.ultraThinMaterial` camera controls in the record → trim → tag flow with real iOS 26 Liquid Glass. Then retire the legacy blue/navy/purple accents on those same screens.

**Architecture:** Two new helpers in `GlassChrome.swift` build on the existing `ppDarkGlassPanel`: `ppOverlayGlass` for small controls and `ppVideoOverlayPanel` for the big panels. The call sites swap their background stacks for one modifier. On iOS 17/18 the helpers' fallbacks rebuild the exact pre-26 look, so older OSes don't change. The recolor task moves the same screens onto `@Environment(\.ppAccent)`, which is injected at the recorder root and the re-trim root.

**Tech stack:** SwiftUI and the iOS 26 `glassEffect` API (`Glass.tint`, `Glass.interactive`). The deployment target stays iOS 17.

**Spec:** the 2026-09-23 audit in this conversation, batch #1 ("fake-glass trio + camera controls"). The palette items in these same files are folded in so each screen gets one test pass.

### The 5-batch breakdown (each gets its own plan, written when the previous one ships)
1. **This plan:** capture overlays (glass + palette on the record/trim/tag screens).
2. Paywalls + sign-in/verification: `.brandNavy/.brandGold` and the `primaryButton/premiumButton/coachButton/premiumAccent` gradients; delete the 0-use tokens (`brandPrimary`, `brandSecondary`, `premiumBackground`).
3. `ppBottomBar` on the 7 bottom bars: season compare ×2, invite coach, scorecard editor, `HoleNavBar`, batch tag editor.
4. Coach dashboard navy (`CoachDashboardView`, `CoachDashboardComponents`, `CoachInvitationsView`, `CoachTabView` `.tint(.brandNavy)`).
5. Floating toasts/banners: a new light-scheme glass helper plus the ~11 banner/toast/progress sites.

## Global Constraints

- Deployment target stays **iOS 17.0**. Every iOS 26 API goes through `GlassChrome.swift`, so call sites carry no `#available`.
- **Glass fallbacks** (Tasks 1–2) must render exactly as today on iOS 17/18. The fallbacks reproduce the current code verbatim.
- **Recolors** (Task 3) apply on every OS, the same as the precedent in `86d5f97c`.
- Colors: `Theme` + `@Environment(\.ppAccent)` / `\.ppAccentLight` only. Never add `.brandNavy`, `LinearGradient.primaryButton` or `.purple`. `ppAccentLight` is the dark-surface variant, for text/badges over video.
- Coach capture stays on the **base** accent (terracotta). Coach UI never takes the golf green.
- Result-category colors (green hits / red outs / cyan walk / gold HR) are **not** accent. They come from `PlayResultType.color`.
- No Swift test target. "Test" = clean build + the stated simulator or device check.
- **Commit only the files each task names.** The working tree has unrelated edits (`PlayResultAccumulator.swift`, `GameDetailView.swift`) that must NOT be staged. Commit directly to `main`, one commit per task. Never touch version/build numbers.

Build (every task):
```bash
cd /Users/Trey/Desktop/PlayerPath && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PlayerPath.xcodeproj \
  -scheme PlayerPath -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | head -20
```

## Verified facts (repo @ a896fbc, Xcode SDK)

| Fact | Source |
|---|---|
| `Glass.tint(_ color: Color?) -> Glass`, `Glass.interactive(_ isEnabled: Bool = true) -> Glass` | SwiftUICore.swiftinterface:7255-7256 |
| `ppDarkGlassPanel(in:tint:fallback:)` already forces the dark scheme on iOS 26; its fallback leaves the scheme alone | `GlassChrome.swift` |
| The three fake-glass panels are identical: 28pt continuous rect, `ultraThinMaterial` + `glassDark` + 100pt `glassShine` + `glassBorder` stroke + black 0.4 r30 y15 shadow | `PlayResultOverlayView.swift:462-486`, `PracticeVideoSaveView.swift:282-299`, `PreUploadTrimmerView.swift:372-391` |
| `glassDark`/`glassShine` have no other users. `glassBorder` is also the button hairline in `PlayResultOverlayComponents:327` and `PreUploadTrimmerView:309,336` (it stays) | grep |
| Camera circle buttons: cancel/flash/flip/grid/settings all use `.background(Circle().fill(.ultraThinMaterial))` | `ModernCameraView.swift:179-182, 236-239, 254-257, 274-277, 290-293` |
| Zoom badge capsule `ModernCameraView.swift:328-331`. Timer (`black 0.6`) and quality text (`black 0.35`) are status readouts and stay as they are | read |
| Recorder badges `DirectCameraRecorderView.swift:258-261` (live game) and `:279` (live session). Golf hole stepper `CurrentHoleStepper.swift:58-59` | read |
| Recorder sport: `clipSport` (`DirectCameraRecorderView.swift:38-40`), coach mode = `isCoachMode` (`:35`). No `ppAccent` is injected anywhere in these files today | read |
| `PlayResultType.walk.color == .cyan`, `.pitchingWalk.color == .red` | `Models/PlayResultType.swift:151-175` |
| WALK headers use `.brandNavy` (`PlayResultOverlayView.swift:589, 669`). In light mode that's `#003373` on a dark panel, which is nearly invisible (**real bug**) | read |
| Only iOS 26.x / 27 simulator runtimes are installed, so the iOS 17/18 fallback **cannot be viewed**. It's protected by being the verbatim current code | `simctl list runtimes` |
| The camera doesn't work in the simulator. `PlayResultOverlayView` and `PracticeVideoSaveView` are reachable only after a recording, so they get **device** checks. `PreUploadTrimmerView` is reachable in the sim via a saved clip's Re-trim | read (presenters) |

## Review Focus

1. **Legibility over a bright frame (iOS 26):** white copy on the tag/save/trim panels over a sunny outfield frame. The panel tint (`.black.opacity(0.25)`) is a starting value. If it isn't legible, raise it in the helper, to 0.4 at most, and record the value.
2. **Text fields in forced-dark glass:** the pitch-speed field (overlay) and the note field (practice save) now render under `colorScheme = .dark` on iOS 26. The placeholder and the typed text must be visible, and the keyboard must still dismiss.
3. **Disabled camera buttons during recording:** still dimmed to 0.5 and not tappable, with no glass press effect.
4. **Golf athlete:** the accent is green on the overlay's mode, pitch and primary buttons and the trimmer's Save; terracotta for baseball; terracotta in coach capture even when the session's athlete plays golf.
5. **Landscape:** the tag panel's right-side column and the camera's left column still lay out correctly (glass must not clip the ScrollView content).

---

### Task 1: Glass helpers + the three fake-glass panels

**Files:**
- Modify: `PlayerPath/Views/Navigation/GlassChrome.swift`
- Modify: `PlayerPath/PlayResultOverlayView.swift:214, 462-486`
- Modify: `PlayerPath/PracticeVideoSaveView.swift:77, 282-299`
- Modify: `PlayerPath/Views/Components/PreUploadTrimmerView.swift:142, 372-391`

**Produces:** `ppDarkGlassPanel(in:tint:interactive:fallback:)`, `ppOverlayGlass(in:interactive:)` and `ppVideoOverlayPanel(cornerRadius:)`, all `View` extensions.

- [ ] **Step 1: Add `interactive` to `ppDarkGlassPanel`.** In `GlassChrome.swift`, change the signature and the glass line (the defaulted param keeps the 3 existing call sites compiling unchanged):

```swift
    func ppDarkGlassPanel<S: Shape, Fallback: View>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false,
        fallback: (Self) -> Fallback
    ) -> some View {
        if #available(iOS 26, *) {
            self
                .glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
                .environment(\.colorScheme, .dark)
        } else {
            fallback(self)
        }
    }
```

Append to its doc comment: `` `interactive` adds the glass press response — pass it for buttons. ``

- [ ] **Step 2: Add the two helpers** at the end of the same `extension View`:

```swift
    /// A small control or badge floating over video or the camera — circle
    /// buttons, the Back capsule, the zoom readout. iOS 26: dark Liquid Glass
    /// (`interactive` for buttons). Before 26: the plain `.ultraThinMaterial`
    /// fill these controls always had.
    func ppOverlayGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        ppDarkGlassPanel(in: shape, interactive: interactive) {
            $0.background(.ultraThinMaterial, in: shape)
        }
    }

    /// The large tag / trim / save panel floating over a paused clip. iOS 26:
    /// dark Liquid Glass with a light black tint so its white copy holds up over
    /// a bright frame (glass draws its own depth, so no shadow). Before 26: the
    /// hand-built material + gradient stack these panels have always used.
    func ppVideoOverlayPanel(cornerRadius: CGFloat = 28) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return ppDarkGlassPanel(in: shape, tint: .black.opacity(0.25)) {
            $0
                .background(
                    ZStack {
                        shape.fill(.ultraThinMaterial)
                        shape.fill(LinearGradient.glassDark)
                        VStack {
                            shape.fill(LinearGradient.glassShine)
                                .frame(height: 100)
                            Spacer()
                        }
                        .clipShape(shape)
                    }
                )
                .overlay(shape.strokeBorder(LinearGradient.glassBorder, lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 30, x: 0, y: 15)
        }
    }
```

- [ ] **Step 3: Swap the three panels.** In each file, replace the whole block from `.background(` (the `ZStack` containing `.ultraThinMaterial`/`glassDark`/`glassShine`) through the `.shadow(color: .black.opacity(0.4), radius: 30, x: 0, y: 15)` line with one line, and leave the `.padding(20)` above it alone:

```swift
        .ppVideoOverlayPanel()
```

  - `PlayResultOverlayView.swift` lines 462-486
  - `PracticeVideoSaveView.swift` lines 282-299
  - `PreUploadTrimmerView.swift` lines 372-391

- [ ] **Step 4: Swap the Back/Discard capsules.** In each of the 3 files, replace the line
  `.background(Capsule().fill(.ultraThinMaterial))`
  with
  `.ppOverlayGlass(in: Capsule(), interactive: true)`
  at `PlayResultOverlayView.swift:214`, `PracticeVideoSaveView.swift:77` and `PreUploadTrimmerView.swift:142`.

- [ ] **Step 5: Confirm no fake-glass stack is left at the call sites.**
Run: `grep -rn "glassDark\|glassShine" --include='*.swift' PlayerPath | grep -v DesignTokens.swift`
Expected: only the two `GlassChrome.swift` lines.

- [ ] **Step 6: Build.** Expected: `BUILD SUCCEEDED`.

- [ ] **Step 7: Simulator check (trimmer).** Boot the iPhone 17 Pro sim. If no clip exists, add a video with `xcrun simctl addmedia booted <any .mov/.mp4>` and bulk-import it. Open the clip → ⋯ → Re-trim → Continue.
Expected: the trimmer panel is Liquid Glass (content refracts at the edges, no white gradient shine band), Back is a glass capsule, and the copy is legible. Take a screenshot with `xcrun simctl io booted screenshot` and look at it.

- [ ] **Step 8: Commit**

```bash
git add PlayerPath/Views/Navigation/GlassChrome.swift PlayerPath/PlayResultOverlayView.swift PlayerPath/PracticeVideoSaveView.swift PlayerPath/Views/Components/PreUploadTrimmerView.swift
git commit -m "Capture overlays: real Liquid Glass for the tag/trim/save panels on iOS 26"
```

---

### Task 2: Camera controls on glass

**Files:**
- Modify: `PlayerPath/ModernCameraView.swift:179-182, 236-239, 254-257, 274-277, 290-293, 328-331`
- Modify: `PlayerPath/DirectCameraRecorderView.swift:258-261, 279`
- Modify: `PlayerPath/Views/Components/CurrentHoleStepper.swift:58-59`

**Consumes:** `ppOverlayGlass(in:interactive:)` from Task 1.

- [ ] **Step 1: Five circle buttons.** In `ModernCameraView.swift` (`cancelButton`, `flashButton`, `flipButton`, `gridButton`, `settingsButton`), replace each
```swift
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                )
```
with
```swift
                .ppOverlayGlass(in: Circle(), interactive: true)
```
Leave each button's `.frame(width: 44, height: 44)`, `.disabled` and `.opacity` exactly as they are.

- [ ] **Step 2: Zoom badge.** In `zoomBadge`, replace the `.background(Capsule().fill(.ultraThinMaterial))` block (lines 328-331) with `.ppOverlayGlass(in: Capsule())`. Don't touch `recordingTimerBadge`, `slowMoBadge` or `qualityText`.

- [ ] **Step 3: Recorder badges.** In `DirectCameraRecorderView.swift`, replace the live-game badge's `.background(Capsule().fill(.ultraThinMaterial))` block (258-261) and the live-session badge's one-liner (279) with `.ppOverlayGlass(in: Capsule())`. Keep `.allowsHitTesting(false)`.

- [ ] **Step 4: Golf hole stepper.** In `CurrentHoleStepper.swift`, replace
```swift
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
```
with
```swift
        .ppDarkGlassPanel(in: Capsule()) {
            $0.background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
        }
```
(Glass draws its own edge, so the hairline stays pre-26 only. The capsule isn't a button, since its +/− are, so it isn't `interactive`.)

- [ ] **Step 5: Confirm.** Run `grep -n "ultraThinMaterial" PlayerPath/ModernCameraView.swift PlayerPath/DirectCameraRecorderView.swift PlayerPath/Views/Components/CurrentHoleStepper.swift`. Expected: the one inside the stepper's fallback closure only.

- [ ] **Step 6: Build.** Expected: `BUILD SUCCEEDED`.

- [ ] **Step 7: Simulator check.** Open the recorder from Videos → Record. The sim has no camera, but the control overlay still renders over black (if a camera-error alert appears, dismiss it with OK, then screenshot before the view dismisses).
Expected: glass circle buttons and a glass zoom badge. If the alert dismisses the recorder too fast to see, this check moves to the device list below. Record that in the commit body.

- [ ] **Step 8: Commit**

```bash
git add PlayerPath/ModernCameraView.swift PlayerPath/DirectCameraRecorderView.swift PlayerPath/Views/Components/CurrentHoleStepper.swift
git commit -m "Camera: Liquid Glass controls, zoom readout, live badges and hole stepper on iOS 26"
```

---

### Task 3: Retire legacy blue/navy/purple on the capture screens

**Files:**
- Modify: `PlayerPath/DirectCameraRecorderView.swift` (accent injection, right before `.confirmationDialog(` at ~:107)
- Modify: `PlayerPath/Views/Components/RetrimSavedClipFlow.swift:63, 101` (+ env var)
- Modify: `PlayerPath/Views/Components/PlayResultOverlayComponents.swift:236-237, 265-266, 290-303` (+ env vars)
- Modify: `PlayerPath/PlayResultOverlayView.swift:391, 589, 669` (+ env var)
- Modify: `PlayerPath/Views/Components/PreUploadTrimmerView.swift:229, 305, 311` (+ env vars)

- [ ] **Step 1: Inject the accent at the recorder root.** In `DirectCameraRecorderView.body`, directly after the `ZStack { … }` closing brace and before `.confirmationDialog(`:
```swift
        // Sport accent for the whole capture flow (trimmer, tag overlay, practice
        // save). Coach capture stays on the base accent, like all coach UI.
        .ppAccent(forGolf: !isCoachMode && clipSport == .golf)
```

- [ ] **Step 2: Inject at the re-trim root.** In `RetrimSavedClipFlow.body`, directly after the `ZStack { … }` closing brace and before `.onChange(of: cloudManager.uploadProgress…`:
```swift
        .ppAccent(forGolf: (clip.season?.sport ?? athlete.sportType) == .golf)
```
Add `@Environment(\.ppAccent) private var ppAccent` under the existing `@Environment(\.modelContext)` line, and change line 101 `.fill(LinearGradient.primaryButton)` → `.fill(ppAccent)`.
*(The Continue button sits inside this same view, above the modifier, so it reads the default terracotta, not the injected value. That's acceptable because Continue is sport-neutral. If Trey wants it sport-aware, move `confirmationCard` into its own subview. Note this in the commit, don't do it.)*

- [ ] **Step 3: Overlay components.** In `PlayResultOverlayComponents.swift`:
  - `ModeButton`: add `@Environment(\.ppAccent) private var ppAccent` under `let action`. Change lines 236-237 to
    ```swift
                                .fill(ppAccent)
                                .shadow(color: ppAccent.opacity(0.4), radius: 8, x: 0, y: 2)
    ```
  - `PitchTypeButton`: add the same env var under `let action`. Change lines 265-266 to the same two lines.
  - `PlayResultActionButton`: add the env var under `let action`. In `shadowColor` change `.brandNavy.opacity(0.4)` → `ppAccent.opacity(0.4)`. In `backgroundView` `.primary` change `.fill(LinearGradient.primaryButton)` → `.fill(ppAccent)`.

- [ ] **Step 4: Overlay view.** In `PlayResultOverlayView.swift` add `@Environment(\.ppAccentLight) private var ppAccentLight` above the first `@State private var`, then:
  - line 391 `"Done"`: `.foregroundColor(.brandNavy)` → `.foregroundColor(ppAccentLight)`
  - line 589: `color: .brandNavy` → `color: PlayResultType.walk.color`
  - line 669: `color: .brandNavy` → `color: PlayResultType.pitchingWalk.color`

- [ ] **Step 5: Trimmer.** In `PreUploadTrimmerView.swift`, add under the `vSizeClass` line:
```swift
    @Environment(\.ppAccent) private var ppAccent
    @Environment(\.ppAccentLight) private var ppAccentLight
```
  - line 229 DURATION badge: `color: .brandNavy` → `color: ppAccentLight`
  - line 305: `.fill(LinearGradient.primaryButton)` → `.fill(ppAccent)`
  - line 311: `Color.brandNavy.opacity(0.4)` → `ppAccent.opacity(0.4)`

- [ ] **Step 6: Confirm the legacy tokens are gone from the flow.**
Run: `grep -nE "brandNavy|primaryButton|\.purple" PlayerPath/PlayResultOverlayView.swift PlayerPath/Views/Components/PlayResultOverlayComponents.swift PlayerPath/Views/Components/PreUploadTrimmerView.swift PlayerPath/Views/Components/RetrimSavedClipFlow.swift PlayerPath/PracticeVideoSaveView.swift`
Expected: only `PlayResultOverlayView.swift:624` (`PITCH RESULT` header `.purple`, a category color like the rest of the section headers, not brand) remains. `ModernCameraView`'s purple SLOW-MO badge is also out of scope (a status badge, not brand).

- [ ] **Step 7: Build.** Expected: `BUILD SUCCEEDED`.

- [ ] **Step 8: Simulator check.** Re-trim a **baseball** clip: Save Trimmed and the DURATION readout are terracotta. Re-trim a **golf** clip: Save Trimmed and DURATION are green.

- [ ] **Step 9: Commit**

```bash
git add PlayerPath/DirectCameraRecorderView.swift PlayerPath/Views/Components/RetrimSavedClipFlow.swift PlayerPath/Views/Components/PlayResultOverlayComponents.swift PlayerPath/PlayResultOverlayView.swift PlayerPath/Views/Components/PreUploadTrimmerView.swift
git commit -m "Capture flow: sport accent replaces legacy blue/navy/purple; WALK headers use the result color"
```

---

### Wrap-up (after Task 3)

- [ ] Run `/review` on the 3 commits and fix what survives.
- [ ] Update memory `project_ios26_liquid_glass_chrome.md`: capture overlays shipped, the helper names, the panel tint value, and the device-test list below as PENDING.
- [ ] Hand Trey the **device checklist** (the simulator can't cover these):
  1. Record → tag overlay: glass panel, legible over a bright frame, pitch-speed field usable (Review Focus 1–2).
  2. Practice record → save panel: note field legible and typing works.
  3. Camera buttons: glass press response; disabled + dimmed while recording.
  4. Golf athlete: green accent through record → trim → tag; coach session capture: terracotta.
  5. Landscape record + tag.
  6. (If an iOS 17/18 device is available) the whole flow looks exactly as before.
