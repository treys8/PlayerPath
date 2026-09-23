# Coach-side Liquid Glass — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (or subagent-driven-development). Steps use `- [ ]`. On approval, copy this file to `docs/superpowers/plans/2026-09-23-coach-liquid-glass.md` (the 2026-09-22 athlete plan lives beside it) and commit it with Task 1.

## Context

The 2026-09-22 iOS 26 chrome pass (plan: `docs/superpowers/plans/2026-09-22-ios26-liquid-glass-chrome.md`) targeted the athlete side. The glass tab bar and minimize-on-scroll already reach coaches (`AppDelegate` is global; `CoachTabView.swift:168` has `.ppTabBarMinimizesOnScroll()`). A coach-side review turned up five gaps, and Trey approved all five:

1. No Live Now accessory for a live coach session. Record is only reachable from the Dashboard card.
2. Live session visuals still use legacy red/navy. The athlete live cards moved to `ppAccent` + `LiveBadge` in `86d5f97c`.
3. `CoachAthletesTab` toolbar menu uses `ellipsis.circle` in legacy navy, which draws a circle inside the glass capsule.
4. Floating dark panels over video/camera use `.ultraThinMaterial`, not glass.
5. The draft publish bar is a solid slab under the scroll view, with a navy Share Now button.

**Goal:** bring the coach side in line with the athlete glass pass. iOS 17/18 chrome stays as it is today.

## Global Constraints

- Deployment target stays **iOS 17.0**. Every iOS 26 API goes behind `#available(iOS 26, *)`. `tabViewBottomAccessory(isEnabled:)` needs **iOS 26.1**.
- All OS gating lives in `PlayerPath/Views/Navigation/GlassChrome.swift` (and the existing `LiveNowAccessoryModifier`). Call sites don't carry their own `#available`, except the one body branch in Task 5.
- iOS 17/18 chrome must render as it does today. **Exception, same as `86d5f97c`:** the recolors in Tasks 2 and 5 apply on every OS.
- Colors: `Theme` + `@Environment(\.ppAccent)` only. Never add new `.brandNavy`/`.red`. Coaches get the base accent (terracotta, `PPAccentKey.defaultValue`), which the coach player already uses (`TelestrationToolbar`, the sequence toolbar tint).
- Keep the **one-owner rule** (see memory `project_ios26_liquid_glass_chrome`): exactly one coach recorder presentation at the tab root.
- Don't touch `CoachTabView`'s `.tint(.brandNavy)` or the rest of the dashboard's navy/gold content. That belongs to the separate content-redesign plan.
- There's no Swift test target. "Test" = clean build + a simulator check against the stated expected result.
- Never bump version/build numbers. Commit direct to `main`, one commit per task.

Build command (used by every task):
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PlayerPath.xcodeproj \
  -scheme PlayerPath -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -3
```

## Verified facts (SDK = iPhoneOS27.0.sdk, repo @ dcc77ad3)

| Fact | Source |
|---|---|
| `Glass.tint(_ color: Color?) -> Glass`; `glassEffect(_:in:)` | SwiftUICore.swiftinterface:7255, 3064 |
| `.glassProminent` / `.glass` button styles, iOS 26.0 | SwiftUI.swiftinterface:4335, 1440 |
| `safeAreaBar(edge: VerticalEdge, …)`, iOS 26.0 | SwiftUI.swiftinterface:22280 |
| `ToolbarContentBuilder.buildLimitedAvailability` is **iOS 17.5** → no `if #available` inside `.toolbar {}` at a 17.0 target | SwiftUI.swiftinterface:11892 |
| `LiveNowAccessoryModifier` is `private` in `MainTabView.swift:908-921` | read |
| `LiveNowAccessory` hard-codes `accessibilityHint("Opens the Journal")` (`LiveNowAccessory.swift:59`) | read |
| Coach recorder cover: `CoachDashboardView.swift:272-286` (`cameraContext` + 2 onChanges). Set at `:386` (Record) and `:929` (resume from reviewing) | read |
| ~~`CoachFolderDetailView.swift:124` quick-record cover is safe because the tab bar is hidden there~~ **WRONG** — nothing hides the tab bar, so the accessory shows in folder detail. Final review fix routed Record Clip through `CoachLiveSessionController` and deleted that cover | final review |
| Live-only session: `CoachSessionManager.shared.activeSession?.status == .live`; title = `session.athleteNamesSummary` | `LiveSessionCard.swift:81` |
| Abandoned live sessions auto-end at 24 h (`cleanupAbandonedSessions`), so the coach accessory passes `staleAt: nil` | `CoachSessionManager.swift:100-112` |
| Draft publish bar sits in a VStack **below** the ScrollView (narrow `:592`, wide `:619`) with `.background(Theme.surface)` (`:1180`) | read |

## Review Focus (checks no build step exercises)

1. **Double camera:** tap Record in the accessory, then on the Dashboard card. Exactly one recorder should ever present (both routes go through `CoachLiveSessionController`).
2. **Session ended elsewhere** (another device, or revoke → `endSessionIfActive`) while the recorder is open. The cover should dismiss, and the accessory should disappear without a crash.
3. **Reviewing → Resume** from the dashboard should still open the recorder, now via the controller.
4. **iPad (regular width):** no accessory (sidebar style), and the dashboard card still works.
5. **Telestration toolbar legibility** over a *bright* video frame on iOS 26: the white glyphs must stay readable (this is why the glass is tinted dark with a forced dark scheme).

---

### Task 1: Coach Live Now accessory + single recorder owner

**Files**
- Create: `PlayerPath/Views/Coach/CoachLiveSessionController.swift` (~35 lines)
- Modify: `PlayerPath/Views/Navigation/LiveNowAccessory.swift` (add `openHint`; move the modifier here)
- Modify: `PlayerPath/Views/Navigation/MainTabView.swift` (pass `openHint`; delete the private modifier at `:905-921`)
- Modify: `PlayerPath/Views/Coach/CoachTabView.swift` (own the controller, the recorder cover and the accessory)
- Modify: `PlayerPath/CoachDashboardView.swift` (delete `cameraContext` + cover + 2 onChanges; route through the controller; preview env)

**Interfaces produced:** `CoachLiveSessionController` (`cameraContext: CoachSessionContext?`, `func recordIntoActiveSession()`), injected with `.environment(liveSession)`; `LiveNowAccessory(…, openHint: String, …)`; internal `LiveNowAccessoryModifier`.

- [ ] **1a. Controller**
```swift
//  CoachLiveSessionController.swift
//  The ONE owner of the coach session recorder. CoachTabView presents the cover;
//  the Dashboard card and the iOS 26.1+ Live Now accessory both ask through here,
//  so two surfaces can never open two cameras for one session.
import SwiftUI

@MainActor
@Observable
final class CoachLiveSessionController {
    /// Non-nil iff the recorder cover is up.
    var cameraContext: CoachSessionContext?

    /// Opens the recorder for the active session. No-op unless it's live.
    func recordIntoActiveSession() {
        guard let active = CoachSessionManager.shared.activeSession,
              active.status == .live,
              let id = active.id, !id.isEmpty else { return }
        cameraContext = CoachSessionContext(sessionID: id, session: active)
    }
}
```

- [ ] **1b. `LiveNowAccessory`:** add `let openHint: String` after `staleAt`. Change `:59` to `.accessibilityHint(openHint)`. Update the header comment ("MainTabView/CoachTabView resolve…"). Move `LiveNowAccessoryModifier` from `MainTabView.swift:905-921` to the bottom of this file, verbatim, minus `private`. In `MainTabView` add `openHint: "Opens the Journal",` to both `LiveNowAccessory(` calls (`:138`, `:158`).

- [ ] **1c. `CoachTabView`**
  - State: `@State private var liveSession = CoachLiveSessionController()` and `private var sessionManager: CoachSessionManager { .shared }`.
  - Computed:
    ```swift
    /// The session the Live Now accessory surfaces: live only. A reviewing
    /// session has nothing to record into; its card on the Dashboard handles it.
    private var liveCoachSession: CoachSession? {
        guard let s = sessionManager.activeSession, s.status == .live else { return nil }
        return s
    }
    ```
  - Compact `TabView` (after `.ppTabBarMinimizesOnScroll()`):
    ```swift
    .modifier(LiveNowAccessoryModifier(isEnabled: liveCoachSession != nil) {
        if #available(iOS 26.1, *) { coachLiveAccessory }
    })
    ```
  - Accessory:
    ```swift
    @available(iOS 26.1, *)
    @ViewBuilder
    private var coachLiveAccessory: some View {
        if let session = liveCoachSession {
            LiveNowAccessory(
                title: session.athleteNamesSummary,
                actionTitle: "Record",
                actionIcon: "video.fill",
                // Abandoned sessions auto-end at 24 h (cleanupAbandonedSessions),
                // so the bar never needs the "Still playing?" state or its End.
                staleAt: nil,
                openHint: "Opens the Dashboard",
                isEnding: false,
                onOpen: { coordinator.selectedTab = .dashboard },
                onAction: { liveSession.recordIntoActiveSession() },
                onEnd: {}
            )
        }
    }
    ```
  - Moved from the Dashboard (put these before `.environment(coordinator)` in the body chain), then add `.environment(liveSession)` beside `.environment(coordinator)`:
    ```swift
    .fullScreenCover(item: $liveSession.cameraContext) { context in
        DirectCameraRecorderView(coachContext: context)
    }
    .onChange(of: liveSession.cameraContext == nil) { _, becameNil in
        guard becameNil, let coachID = authManager.userID else { return }
        Task { await sessionManager.fetchSessions(coachID: coachID) }
    }
    .onChange(of: sessionManager.activeSession) { _, newValue in
        // Dismiss the recorder if the session was ended/completed externally.
        if newValue == nil { liveSession.cameraContext = nil }
    }
    ```

- [ ] **1d. `CoachDashboardView`**
  - Add `@Environment(CoachLiveSessionController.self) private var liveSession`.
  - Delete `@State cameraContext` (`:28-32`), the cover and both onChanges (`:272-286`).
  - `onRecord` (`:381-387`) becomes `{ liveSession.recordIntoActiveSession() }` (still `nil` unless live).
  - Resume (`:928-930`): replace the `if let active …` block with `liveSession.recordIntoActiveSession()`.
  - Preview (`:1136`): add `.environment(CoachLiveSessionController())`.
  - Leave `isEndingSession`/`endActiveSession` as they are (End stays on the card).

- [ ] **1e. Build.** Expected `** BUILD SUCCEEDED **`. `grep -n cameraContext PlayerPath/CoachDashboardView.swift` → no hits.
- [ ] **1f. Sim (iOS 26.4, coach account).** Start a session. The accessory shows "Live · {athlete}" on all 3 tabs. Record opens the camera, and so does the card's Record (never both). Tapping the bar opens the Dashboard. End from the card → the accessory disappears. Run Review Focus 1–3.
- [ ] **1g. Commit:** "Coach: Live Now accessory for live sessions; one recorder owner at the tab root"

### Task 2: Live session visuals → accent palette

Same recipe as `86d5f97c`, all OSes.

**Files:** `PlayerPath/Views/Coach/LiveSessionCard.swift`, `PlayerPath/CoachDashboardView.swift`

- [ ] **2a. `LiveSessionCard`:** add `@Environment(\.ppAccent) private var ppAccent`; `accentColor` becomes `isLive ? ppAccent : Theme.textSecondary`.
  - LIVE pill: when `isLive`, render `LiveBadge()` in place of the custom pill (keep "SESSION" beside it); keep the capsule for "SESSION ENDED".
  - Notes button `.brandNavy` → `ppAccent`.
  - Record button background: `Capsule().fill(ppAccent)`, drop the gradient and the shadow.
  - End button: `.foregroundColor(ppAccent)`, `.background(Capsule().fill(ppAccent.opacity(0.12)))`; the ProgressView tint → `ppAccent`.
  - Card (`:203-216`): `.fill(Theme.card)`, stroke `accentColor.opacity(0.45)` at `lineWidth: 1.5`, drop the `.shadow`.
- [ ] **2b. `CoachDashboardView`:** add `@Environment(\.ppAccent) private var ppAccent`.
  - `headerColor` (`:345`) → `ppAccent`.
  - "Live Now" text: `.foregroundStyle(ppAccent)` in place of the gradient.
  - "Review Clips" button `.background(Color.brandNavy)` (`:407`) → `ppAccent`.
  - Quick action "Resume Session" `color: .red` (`:589`) → `ppAccent`.
- [ ] **2c. Build + sim:** the live card reads like the athlete `LiveGameCard` (terracotta hairline, solid terracotta Record, tinted End). Ended state is gray, not navy. No red left: `grep -n '\.red' PlayerPath/Views/Coach/LiveSessionCard.swift` → none.
- [ ] **2d. Commit:** "Coach live session: accent palette + shared LiveBadge instead of red/navy"

### Task 3: Athletes-tab toolbar glyph

**Files:** `PlayerPath/Views/Coach/CoachAthletesTab.swift:98-99`

- [ ] **3a.** `Image(systemName: "ellipsis.circle")` → `Image(systemName: ToolbarSymbol.more)`. Keep `.foregroundColor(.brandNavy)` so pre-26 stays identical (the coach tint is navy anyway, and retinting coach chrome is out of scope). Don't split the HStack into `ToolbarItemGroup`: that changes pre-26 spacing, and a conditional toolbar needs iOS 17.5 (see Verified facts). `record.circle` stays; it's the semantic record glyph.
- [ ] **3b.** Build. Sim 26: a plain "…" in the capsule. Pre-26 (if an iOS 18 runtime is installed): still circled.
- [ ] **3c. Commit:** "Coach Athletes toolbar: plain overflow glyph inside iOS 26 glass"

### Task 4: Dark glass for floating panels over video/camera

**Files:** `GlassChrome.swift`, `Telestration/TelestrationToolbar.swift:220-221`, `Telestration/TelestrationOverlayView.swift:175-176`, `SessionAthletePickerOverlay.swift:86-90`

- [ ] **4a. Helper** (append to the `View` extension in `GlassChrome.swift`):
```swift
/// A control panel floating over video or the camera: Liquid Glass tinted
/// dark on iOS 26, with the dark scheme forced so the glass never flips light
/// behind the panels' white glyphs over a bright frame. Before 26, `fallback`
/// applies the panel's existing material so its look is unchanged.
@ViewBuilder
func ppDarkGlassPanel<S: Shape, Fallback: View>(
    in shape: S,
    tint: Color? = nil,
    fallback: (Self) -> Fallback
) -> some View {
    if #available(iOS 26, *) {
        self
            .glassEffect(.regular.tint(tint), in: shape)
            .environment(\.colorScheme, .dark)
    } else {
        fallback(self)
    }
}
```
- [ ] **4b. TelestrationToolbar**, replacing the two `.background` lines:
```swift
.ppDarkGlassPanel(in: RoundedRectangle(cornerRadius: 22, style: .continuous),
                  tint: Theme.tileNavyDark.opacity(0.55)) {
    $0.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
      .background(Theme.tileNavyDark.opacity(0.55), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
}
```
- [ ] **4c. TelestrationOverlayView "Saving…"**: `.background(.ultraThinMaterial).cornerRadius(12)` becomes `.ppDarkGlassPanel(in: RoundedRectangle(cornerRadius: 12)) { $0.background(.ultraThinMaterial).cornerRadius(12) }`.
- [ ] **4d. SessionAthletePickerOverlay:** swap the `.background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial).environment(\.colorScheme, .dark))` for `.ppDarkGlassPanel(in: RoundedRectangle(cornerRadius: 20)) { $0.background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial).environment(\.colorScheme, .dark)) }`.
- [ ] **4e. Build + sim 26:** open a clip → draw. The toolbar is glass, and its colors/Save are readable over both bright and dark frames (Review Focus 5). Coach session camera → after a clip, the picker panel is glass. Also check that the forced dark scheme didn't change any intended `.primary` text inside these panels.
- [ ] **4f. Commit:** "Coach video overlays: tinted Liquid Glass panels on iOS 26 (material kept pre-26)"

### Task 5: Draft publish bar → glass bar

**Files:** `GlassChrome.swift`, `Views/Coach/Review/ClipReviewPublishBar.swift`, `CoachVideoPlayerView.swift` (`:585-592`, `:619`, `:1180`)

- [ ] **5a. Helper** (`GlassChrome.swift`):
```swift
/// Pins a bottom action bar. iOS 26: `safeAreaBar`, so content scrolls under
/// the bar with the system scroll-edge effect. Before 26: stacked below the
/// view on `Theme.surface` (today's layout).
@ViewBuilder
func ppBottomBar<Bar: View>(isPresented: Bool, @ViewBuilder bar: () -> Bar) -> some View {
    if #available(iOS 26, *) {
        self.safeAreaBar(edge: .bottom) { if isPresented { bar() } }
    } else {
        VStack(spacing: 0) {
            self
            if isPresented { bar().background(Theme.surface) }
        }
    }
}
```
- [ ] **5b. `CoachVideoPlayerView`**
  - Narrow: attach `.ppBottomBar(isPresented: isOwnPrivateDraft) { draftPublishBar }` to the `ScrollView` and delete the `if isOwnPrivateDraft { draftPublishBar }` line at `:592`.
  - Delete `.background(Theme.surface)` from `draftPublishBar` (`:1180`).
  - Wide (`:619`): `if isOwnPrivateDraft { draftPublishBar.background(Theme.surface) }`. It isn't over a scroll region, so it stays solid.
- [ ] **5c. `ClipReviewPublishBar`:** add `@Environment(\.ppAccent) private var ppAccent`. Pull the three labels out as `shareLabel`, `saveLabel` and `discardMenu` content so both bodies share them. `body` becomes:
```swift
var body: some View {
    Group {
        if #available(iOS 26, *) { glassBody } else { legacyBody }
    }
    .disabled(isBusy)
    .padding(.horizontal)
    .padding(.bottom, 8)
}
```
  - `legacyBody` = today's layout with `.brandNavy` → `ppAccent` (Share Now fill, Save for Later text).
  - `glassBody` (`@available(iOS 26, *)`): VStack(spacing: 10) containing:
    - Share Now: `Button(action: onShareNow) { shareLabel.frame(maxWidth: .infinity) }.buttonStyle(.glassProminent).tint(ppAccent).controlSize(.large)`
    - an HStack(spacing: 10) of `Button(action: onSaveForLater) { saveLabel.frame(maxWidth: .infinity) }.buttonStyle(.glass).controlSize(.large)` and `Menu { discard } label: { Image(systemName: "ellipsis") }.buttonStyle(.glass).controlSize(.large)`
  - Keep the `.disabled(isBusy)` behavior from today (move it to the container as shown).
- [ ] **5d. Build + sim 26:** record a draft as a coach and open it (narrow). The notes scroll under a glass bar, Share Now is terracotta glass, and Publish, Save and Discard still work. iPad/landscape wide layout: the bar stays solid. The Share Now over-limit redirect is unchanged.
- [ ] **5e. Commit:** "Coach draft publish bar: glass buttons over a scroll-edge safe-area bar on iOS 26"

---

## Final verification

- Clean build after all five tasks.
- On the iOS 26.4 sim with a coach account, walk the full loop: start session → accessory → Record from the accessory → clip → athlete picker (glass) → end on the card → Review Clips → open the draft → telestrate (glass toolbar) → Share Now (glass bar).
- Pre-26 check is pending (no iOS 17/18 runtime installed, same as the athlete pass). Flag it to Trey.
- Run `/review` on the five commits.
- Update the memory `project_ios26_liquid_glass_chrome` with the coach half: the one-owner `CoachLiveSessionController`, and what was verified vs. pending.
