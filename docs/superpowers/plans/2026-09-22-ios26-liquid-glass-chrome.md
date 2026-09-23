# iOS 26 Liquid Glass Chrome — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make PlayerPath's system chrome (tab bar, toolbars) behave like a native iOS 26/27 app — Liquid Glass tab bar, minimize-on-scroll, glass-appropriate toolbar glyphs, and a live-game bottom accessory — while iOS 17/18 keep today's exact look.

**Architecture:** Almost everything is already native (standard `TabView` + `.tabItem`, standard `ToolbarItem`s — iOS 26 already draws the toolbar pills as glass). The work is (1) removing the one override that blocks glass (`AppDelegate` opaque tab bar), (2) adopting three iOS 26 APIs behind `#available`, (3) swapping circled SF Symbols that double up inside glass capsules. Two small new files hold the gated helpers and the accessory view.

**Tech Stack:** SwiftUI, UIKit appearance proxies, iOS 26.0/26.1 SDK APIs, Xcode 27 (build 27A266a), iOS 27.0 SDK.

**Spec:** No separate spec — the design discussion lives in the 2026-09-22 conversation. The decisions it produced are copied into Global Constraints below.

## Global Constraints

- Deployment target stays **iOS 17.0** (`IPHONEOS_DEPLOYMENT_TARGET = 17.0`, both build configs). Do not change it.
- Every iOS 26 API goes behind `#available(iOS 26, *)`; `tabViewBottomAccessory(isEnabled:)` requires **`#available(iOS 26.1, *)`** (verified in SDK — the 26.0 overload has no `isEnabled:`).
- iOS 17/18 must render **pixel-identical to today** for everything this plan touches.
- Content redesign (game-card thumbnails, W/L results, fewer all-caps labels, Stats legacy cards) is **out of scope** — separate plan.
- Colors: `Theme` + `@Environment(\.ppAccent)` only. Type: `.pp*` fonts only. Never `.brandNavy` / `.bodySmall` etc. in new code.
- No test target exists for Swift (CLAUDE.md). "Test" = clean build + simulator screenshot check against the stated expected result.
- Never set or bump version/build numbers (Trey owns those).
- Commit direct to `main` (Trey's workflow), one commit per task.

## Verified facts this plan depends on (no guessing)

All checked 2026-09-22 against `iPhoneOS.sdk` in Xcode 27.0 and the repo at `06d3f1fd`.

| Fact | Source |
|---|---|
| `func tabBarMinimizeBehavior(_:)` — iOS 26.0; `.onScrollDown`, `.onScrollUp`, `.automatic` | SwiftUI.swiftinterface:11118-11140 |
| `func tabViewBottomAccessory(content:)` — iOS 26.0; `tabViewBottomAccessory(isEnabled:content:)` — **iOS 26.1** | SwiftUI.swiftinterface:17572, 17579 |
| `EnvironmentValues.tabViewBottomAccessoryPlacement: TabViewBottomAccessoryPlacement?` with cases `.inline`, `.expanded` | SwiftUI.swiftinterface:6824, 6864 |
| iOS 27 SwiftUI adds no new material/chrome system (adds reorderable, `CrossFadeNavigationTransition`, `ToolbarItemVisibilityPriority`, `TabsPickerStyle`; deprecates `PreviewProvider`) | SDK grep for `@available(iOS 27` |
| Tab bar is forced opaque: `configureWithOpaqueBackground()` + `Theme.card` + `Theme.divider` hairline | `PlayerPath/AppDelegate.swift:110-134` |
| That override was added 2026-06-02 because glass picked up a "green bleed" from Journal thumbnails | commit `3bcb8d9b` — i.e. the bleed **is** Liquid Glass refraction; before it, `configureWithDefaultBackground()` produced glass |
| Athlete tabs: `TabView` with `.tabItem`, compact branch at `MainTabView.swift:453-461`, regular (iPad) `.sidebarAdaptable` branch at `:444-452` | read |
| Coach tabs: same shape at `CoachTabView.swift:149-167` | read |
| Toolbars are native `ToolbarItem`s (e.g. `GamesView.swift:500-555`) — already glass on iOS 26 | read |
| Live state: `Game.isLive` (`Models.swift:96`), `Practice.isLive` (`Models.swift:387`, golf practices only) | read |
| Live actions already centralised in `LiveActivityController` (`Views/Components/LiveActivityController.swift`) — `recordInto(game:context:)`, `recordInto(practice:context:)`, `presentScoreHole(for:)`, `recordingGame`, `recordingPractice`, `scoreTarget` | read |
| Journal's live strip rules: game → golf ? Score Hole : Record; every live practice → Record (`JournalView.swift:509-570`) | read |
| Simulators installed: iOS 26.0–26.5 and 27.0 only. **No iOS 17/18 runtime.** | `xcrun simctl list runtimes` |

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `PlayerPath/AppDelegate.swift` | Modify `:110-134` | Tab bar: glass on 26+, opaque cream below |
| `PlayerPath/Views/Navigation/GlassChrome.swift` | **Create** (~40 lines) | `ToolbarSymbol` glyph helper + `ppTabBarMinimizesOnScroll()` modifier |
| `PlayerPath/Views/Navigation/LiveNowAccessory.swift` | **Create** (~90 lines) | The bottom-accessory view (pure view, no data access) |
| `PlayerPath/Views/Navigation/MainTabView.swift` | Modify | Apply minimize + accessory; host a `LiveActivityController` for the accessory's actions |
| `PlayerPath/Views/Coach/CoachTabView.swift` | Modify `:160-167` | Apply minimize |
| 13 toolbar call sites (listed in Task 3) | Modify | Use `ToolbarSymbol` |

---

### Task 0: Baseline + iOS 18 simulator

**Files:** none (environment only)

- [ ] **Step 1: Install an iOS 18 simulator runtime** (Trey, manual — GUI download). Xcode → Settings → Components → iOS 18.x → Get. Then create a device:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl list runtimes | grep "iOS 18"
# use the identifier printed above:
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl create "iPhone 16 (iOS 18)" "iPhone 16" com.apple.CoreSimulator.SimRuntime.iOS-18-<minor>
```

Expected: a device UDID is printed.

- [ ] **Step 2: Build clean on current main**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project PlayerPath.xcodeproj -scheme PlayerPath -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Capture baseline screenshots** on the iOS 27 sim and the iOS 18 sim — Journal (scrolled into photos), Games, Stats, a Game detail, Coach dashboard. Save to the scratchpad as `baseline-{os}-{screen}.png` with `xcrun simctl io booted screenshot <path>`. These are the "iOS 18 must be identical" reference.

---

### Task 1: Liquid Glass tab bar on iOS 26+

**Files:**
- Modify: `PlayerPath/AppDelegate.swift:110-117`

**Interfaces:** Consumes nothing. Produces nothing other tasks depend on.

- [ ] **Step 1: Replace the background block.** Current code (`:110-117`):

```swift
        let tabAppearance = UITabBarAppearance()
        // Opaque cream/white so scrolling video thumbnails can't tint the bar
        // (the Journal tab bar was picking up a green bleed). Theme.card is the
        // designated tab-bar surface; a divider hairline separates it from the
        // cream content above.
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor(Theme.card)
        tabAppearance.shadowColor = UIColor(Theme.divider)
```

New code:

```swift
        let tabAppearance = UITabBarAppearance()
        if #available(iOS 26, *) {
            // iOS 26+: let the system draw the floating Liquid Glass bar. Content
            // refracting through it (the "green bleed" from Journal thumbnails that
            // 3bcb8d9b suppressed) IS the glass material — forcing it opaque is what
            // made the app read as pre-26 next to Apple's own apps.
            tabAppearance.configureWithDefaultBackground()
        } else {
            // iOS 17/18: opaque cream so scrolling thumbnails can't tint the bar.
            // Theme.card is the designated tab-bar surface; a divider hairline
            // separates it from the cream content above.
            tabAppearance.configureWithOpaqueBackground()
            tabAppearance.backgroundColor = UIColor(Theme.card)
            tabAppearance.shadowColor = UIColor(Theme.divider)
        }
```

Leave the item-appearance loop (`:118-130`) and the two `UITabBar.appearance()` assignments untouched — the Inter tab label font and the sport-aware selected tint must keep working.

- [ ] **Step 2: Build** (command from Task 0 Step 2). Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Verify on the iOS 27 sim.** Scroll the Journal so a photo passes under the tab bar.
  Expected: the tab bar is translucent and the photo's colors show through it softly. Selected tab is still terracotta (or golf green on a golf profile); labels are still Inter.
  **If the bar is still solid cream:** stop and report — do not layer workarounds on it.

- [ ] **Step 4: Verify on the iOS 18 sim.** Expected: identical to `baseline-18-*.png`.

- [ ] **Step 5: ⛔ Trey sign-off on device.** The tint showing through *is* the feature. If Trey rejects it after seeing it on a phone, revert this task alone (`git revert`). Tasks 2-4 don't depend on it.

- [ ] **Step 6: Commit**

```bash
git add PlayerPath/AppDelegate.swift
git commit -m "Tab bar: Liquid Glass on iOS 26+, opaque cream kept for iOS 17/18"
```

---

### Task 2: Gated helpers + tab bar minimize-on-scroll

**Files:**
- Create: `PlayerPath/Views/Navigation/GlassChrome.swift`
- Modify: `PlayerPath/Views/Navigation/MainTabView.swift:453-461` (compact branch only)
- Modify: `PlayerPath/Views/Coach/CoachTabView.swift:160-167` (compact branch only)

**Interfaces:**
- Produces: `enum ToolbarSymbol { static var more: String; static func filter(active: Bool) -> String }` (used by Task 3), and `View.ppTabBarMinimizesOnScroll()`.

- [ ] **Step 1: Create `GlassChrome.swift`**

```swift
//
//  GlassChrome.swift
//  PlayerPath
//
//  iOS 26 Liquid Glass adoption helpers, gated so iOS 17/18 keep the pre-26
//  look. Everything version-dependent about system chrome lives here, so call
//  sites never carry their own #available checks.
//

import SwiftUI

/// SF Symbol names for toolbar buttons. iOS 26 draws a glass capsule around
/// every toolbar item, so a circled glyph renders as a circle inside a circle;
/// pre-26 toolbars have no capsule and still want the circle.
enum ToolbarSymbol {
    /// Overflow ("more actions") menu.
    static var more: String {
        if #available(iOS 26, *) { return "ellipsis" }
        return "ellipsis.circle"
    }

    /// Filter menu. The filled circle stays as the "a filter is on" signal on
    /// every OS — it reads as a badge, not as a doubled outline.
    static func filter(active: Bool) -> String {
        if active { return "line.3.horizontal.decrease.circle.fill" }
        if #available(iOS 26, *) { return "line.3.horizontal.decrease" }
        return "line.3.horizontal.decrease.circle"
    }
}

extension View {
    /// Shrinks the iOS 26 tab bar while scrolling down (as in Apple's own apps);
    /// no-op before iOS 26. Apply to the compact-width TabView only — the iPad
    /// sidebar-adaptable style has no bottom bar to minimize.
    @ViewBuilder
    func ppTabBarMinimizesOnScroll() -> some View {
        if #available(iOS 26, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}
```

- [ ] **Step 2: Apply to the athlete compact TabView** — `MainTabView.swift:454-460`:

```swift
            TabView(selection: $selectedTab) {
                homeTab
                gamesTab
                videosTab
                statsTab
                moreTab
            }
            .ppTabBarMinimizesOnScroll()
```

- [ ] **Step 3: Apply to the coach compact TabView** — `CoachTabView.swift:160-166`:

```swift
                TabView(selection: Binding(
                    get: { coordinator.selectedTab.rawValue },
                    set: { if let tab = CoachTab(rawValue: $0) { coordinator.selectedTab = tab } }
                )) {
                    dashboardTab
                    athletesTab
                    profileTab
                }
                .ppTabBarMinimizesOnScroll()
```

- [ ] **Step 4: Build.** Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Verify on the iOS 27 sim.** In the Journal, scroll down → the tab bar collapses to a small pill with the selected tab icon. Scroll up → it expands. Repeat on Games, Videos, Stats, More, and the coach Dashboard.
  Expected: it collapses on every scrolling tab and never hides a tab you can't get back to (tap the collapsed pill → it expands).

- [ ] **Step 6: Verify on the iOS 18 sim.** Expected: the tab bar never collapses; identical to baseline.

- [ ] **Step 7: Commit**

```bash
git add PlayerPath/Views/Navigation/GlassChrome.swift PlayerPath/Views/Navigation/MainTabView.swift PlayerPath/Views/Coach/CoachTabView.swift
git commit -m "Tab bar minimizes on scroll (iOS 26+); add GlassChrome helpers"
```

---

### Task 3: Toolbar glyphs that don't double up inside glass

**Files:** Modify each site below. Every site was classified by its enclosing container on 2026-09-22.

**Interfaces:** Consumes `ToolbarSymbol.more` and `ToolbarSymbol.filter(active:)` from Task 2.

**In scope — inside a toolbar (glass capsule on 26):**

| # | File:line | Current | Replace with |
|---|---|---|---|
| 1 | `VideoClipsView.swift:162` | `Image(systemName: "ellipsis.circle")` | `Image(systemName: ToolbarSymbol.more)` |
| 2 | `VideoClipsView.swift:231` | same | same |
| 3 | `StatisticsView.swift:252` (inside `ToolbarItem(.primaryAction)` at `:195`) | same | same |
| 4 | `GamesView.swift:551` | same | same |
| 5 | `VideoPlayerView.swift:707` | same | same |
| 6 | `AthleteFoldersListView.swift:540` | same | same |
| 7 | `CoachFolderDetailView.swift:230` (`trailingMenu`, used in toolbar at `:177`) | `Image(systemName: "ellipsis.circle")` + `.foregroundColor(.primary)` | `Image(systemName: ToolbarSymbol.more)` — keep the foreground modifier |
| 8 | `Views/Photos/PhotosView.swift:232` | `ellipsis.circle` | `ToolbarSymbol.more` |
| 9 | `Views/Games/GameDetailView.swift:722` (inside `ToolbarItem(.primaryAction)` at `:640`) | `ellipsis.circle` + `.font(.title3)` | `ToolbarSymbol.more` — keep `.font(.title3)` (removing it would change iOS 18) |
| 10 | `Views/Games/TournamentDetailView.swift:107` | `ellipsis.circle` | `ToolbarSymbol.more` |
| 11 | `Views/Practices/PracticeDetailView.swift:491` (inside `primaryActionMenu` `:449`) | `ellipsis.circle` + `.font(.title3)` | `ToolbarSymbol.more` — keep `.font(.title3)` |
| 12 | `HighlightsView.swift:484` (`ToolbarItemGroup(.bottomBar)`) | `Label("Actions", systemImage: "ellipsis.circle")` | `Label("Actions", systemImage: ToolbarSymbol.more)` |
| 13 | `SeasonFilterMenu.swift:61-63` (used in toolbars in Games, Videos, Stats, Practices) | `selectedSeasonID != nil ? "…circle.fill" : "…circle"` | `ToolbarSymbol.filter(active: selectedSeasonID != nil)` |
| 14 | `AthleteFoldersListView.swift:113` | `"line.3.horizontal.decrease.circle"` | `ToolbarSymbol.filter(active: false)` — this site has no active state today; keep it that way |
| 15 | `Views/Photos/PhotosView.swift:198` | `hasActiveFilters ? "…circle.fill" : "…circle"` | `ToolbarSymbol.filter(active: hasActiveFilters)` |
| 16 | `Views/Search/AdvancedSearchView.swift:65` | `showingFilters ? "…circle.fill" : "…circle"` | `ToolbarSymbol.filter(active: showingFilters)` |

**Out of scope — not in a toolbar; leave alone:**
- `HighlightsView.swift:416` — icon inside a menu `Section`
- `CoachFolderDetailView.swift:396` — empty-state illustration
- `CoachFolderDetailView.swift:444` — in-content `HStack`
- `CoachAthletesTab.swift:98` — in-content overlay (also uses legacy `.brandNavy`; separate cleanup)
- `MainTabView.swift:668`, `CoachNavigationCoordinator.swift:28` — **tab bar** icons, not toolbar

- [ ] **Step 1: Edit sites 1-12** (`ellipsis.circle` → `ToolbarSymbol.more`), exactly as in the table.
- [ ] **Step 2: Edit sites 13-16** (filter glyph → `ToolbarSymbol.filter(active:)`), exactly as in the table.
- [ ] **Step 3: Confirm nothing in-scope was missed**

```bash
grep -rn '"ellipsis.circle"\|"line.3.horizontal.decrease.circle"' PlayerPath | grep "\.swift:"
```

Expected: only the 6 out-of-scope lines above remain (HighlightsView:416, CoachFolderDetailView:396 and :444, CoachAthletesTab:98, MainTabView:668, CoachNavigationCoordinator:28).

- [ ] **Step 4: Build.** Expected: `** BUILD SUCCEEDED **`
- [ ] **Step 5: Verify on the iOS 27 sim.** Games, Stats, Videos, Photos, Game detail, Practice detail: the overflow button is a plain `…` inside its glass pill. There's no circle inside a circle. Pick a season filter → the filter glyph turns into the filled circle.
- [ ] **Step 6: Verify on the iOS 18 sim.** Expected: circled glyphs, identical to baseline.
- [ ] **Step 7: Commit**

```bash
git add -A PlayerPath
git commit -m "Toolbar: plain glyphs inside iOS 26 glass capsules (circled kept pre-26)"
```

---

### Task 4: "Live Now" bottom accessory (iOS 26.1+)

**Decided 2026-09-22 (Trey):** show on **every** tab, including the Journal. **Stale state added:** once the activity passes the existing stale threshold (`GameAlertService.staleDuration` 3.5 h, `golfRoundStaleDuration` 5.5 h for golf rounds/practice rounds, measured from `liveStartDate`), the bar reads **"Still playing?"** and its action becomes **End**, behind a confirmation dialog. Ending recalculates stats, so it's never one tap. The accessory re-evaluates staleness every 60 s via `TimelineView`, so it flips without needing a re-render. **Implemented:** `LiveNowAccessory.swift` and `MainTabView.swift` are the canonical versions. The code blocks below are the draft from before the stale state was added. The implementation adds `staleAt: Date?`, `isEnding: Bool`, `onEnd:` to the accessory, plus `staleAt(start:isRound:)`, `liveEndConfirmTitle`, `endLiveItem()` and a `.confirmationDialog` in MainTabView.

**Files:**
- Create: `PlayerPath/Views/Navigation/LiveNowAccessory.swift`
- Modify: `PlayerPath/Views/Navigation/MainTabView.swift`

**Interfaces:**
- Produces: `struct LiveNowAccessory: View` — `init(title: String, actionTitle: String, actionIcon: String, onOpen: @escaping () -> Void, onAction: @escaping () -> Void)`. A pure view: no model access, so it can't trap on a deleted `@Model`.
- Consumes: `LiveActivityController` (existing), `HoleScoringSheet(game:holeNumber:)` / `HoleScoringSheet(practice:holeNumber:)` (existing, `JournalView.swift:380-382`), `DirectCameraRecorderView(athlete:game:)` / `(athlete:practice:)` (existing).

**Behavior rules (copied from the Journal live strip, `JournalView.swift:509-570`, so the two surfaces never disagree):**
- Live **game**: golf → action "Score" (`presentScoreHole(for:)`), otherwise → "Record" (`recordInto(game:)`).
- Live **practice** (golf only — `Practice.isLive` is only set for golf): "Record" (`recordInto(practice:)`).
- Sport scoping: same as `JournalView.sportMatches` — the item's `season?.sport` must equal `selectedAthlete.sportType`, and seasonless passes.
- Games take priority over practices. If more than one is live, show the first (`LiveActivityGuard` allows only one live golf activity at a time).
- Tapping the text → switch to the Journal tab, where the full live card is.
- Stale (see above) → label "Still playing?", action "End" → confirmation → `LiveActivityController.endGame` / `endPractice`; spinner while `isEnding`.

- [ ] **Step 1: Create `LiveNowAccessory.swift`**

```swift
//
//  LiveNowAccessory.swift
//  PlayerPath
//
//  iOS 26.1+ tab-bar bottom accessory for an in-progress game or golf practice —
//  the Music-style mini bar. Pure view: MainTabView resolves the live item and
//  passes strings + closures, so this never touches a @Model (no deleted-model
//  traps while a game ends underneath it).
//

import SwiftUI

@available(iOS 26.1, *)
struct LiveNowAccessory: View {
    let title: String
    let actionTitle: String
    let actionIcon: String
    let onOpen: () -> Void
    let onAction: () -> Void

    @Environment(\.ppAccent) private var ppAccent
    /// `.inline` = the tab bar has minimized and the accessory shares its row;
    /// there's only room for the icon then.
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(ppAccent)
                        .frame(width: 8, height: 8)
                    Text("Live")
                        .font(.ppCaptionBold)
                        .foregroundStyle(ppAccent)
                    Text(title)
                        .font(.ppHeadline)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Live: \(title)")
            .accessibilityHint("Opens the Journal")

            Button(action: onAction) {
                if placement == .inline {
                    Image(systemName: actionIcon)
                } else {
                    Label(actionTitle, systemImage: actionIcon)
                        .font(.ppCaptionBold)
                }
            }
            .tint(ppAccent)
            .accessibilityLabel(actionTitle)
        }
        .padding(.horizontal, 16)
    }
}
```

- [ ] **Step 2: Add state to `MainTabView`** (next to the other `@State`s, after `:45`):

```swift
    // Actions for the iOS 26.1+ Live Now tab-bar accessory. Its own controller
    // (not the Journal's), so the recorder/score covers present from the tab root
    // no matter which tab is showing.
    @State private var liveAccessory = LiveActivityController()
```

- [ ] **Step 3: Add the live-item resolver to `MainTabView`** (after `gamesTabIcon`, `:64`):

```swift
    /// The in-progress activity the Live Now accessory surfaces, scoped to the
    /// profile's sport exactly like JournalView's live strip. Games win over
    /// practices. Reading the relationships in body registers SwiftData
    /// observation, so the accessory appears/disappears as `isLive` flips.
    private enum LiveItem {
        case game(Game)
        case practice(Practice)
    }

    private var liveItem: LiveItem? {
        let sport = selectedAthlete.sportType
        func matches(_ s: Season.SportType?) -> Bool { s == nil || s == sport }
        if let game = (selectedAthlete.games ?? []).first(where: { $0.isLive && matches($0.season?.sport) }) {
            return .game(game)
        }
        if let practice = (selectedAthlete.practices ?? []).first(where: { $0.isLive && matches($0.season?.sport) }) {
            return .practice(practice)
        }
        return nil
    }
```

- [ ] **Step 4: Add the accessory builder to `MainTabView`** (after the `liveItem` resolver):

```swift
    @available(iOS 26.1, *)
    @ViewBuilder
    private var liveNowAccessory: some View {
        switch liveItem {
        case .game(let game):
            let isGolf = game.season?.sport == .golf
            LiveNowAccessory(
                // Same wording as LiveGameCard.titleText (LiveGameCard.swift:131-134):
                // golf rounds are "at {course}", baseball "vs {opponent}".
                title: "\(isGolf ? "at" : "vs") \(game.opponent.isEmpty ? "Unknown" : game.opponent)",
                actionTitle: isGolf ? "Score" : "Record",
                actionIcon: isGolf ? "flag" : "video.fill",
                onOpen: { selectedTab = MainTab.home.rawValue },
                onAction: {
                    if isGolf { liveAccessory.presentScoreHole(for: game) }
                    else { liveAccessory.recordInto(game: game, context: "TabAccessoryRecord") }
                }
            )
        case .practice(let practice):
            LiveNowAccessory(
                // LiveGameCard shows the course when set; otherwise fall back to
                // the type name ("Practice Round" / "Range Session").
                title: practice.course.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
                    ?? PracticeType(rawValue: practice.practiceType)?.displayName ?? "Practice",
                actionTitle: "Record",
                actionIcon: "video.fill",
                onOpen: { selectedTab = MainTab.home.rawValue },
                onAction: { liveAccessory.recordInto(practice: practice, context: "TabAccessoryRecord") }
            )
        case nil:
            EmptyView()
        }
    }
```

- [ ] **Step 5: Attach it to the compact TabView** — extend the Task 2 edit at `MainTabView.swift:454-461`:

```swift
            TabView(selection: $selectedTab) {
                homeTab
                gamesTab
                videosTab
                statsTab
                moreTab
            }
            .ppTabBarMinimizesOnScroll()
            .modifier(LiveNowAccessoryModifier(isEnabled: liveItem != nil) { liveNowAccessory })
```

Add the gating modifier at the bottom of `MainTabView.swift`, next to the badge modifiers. The `if #available` has to live inside a modifier: branching the whole `TabView` on availability would be fine at runtime, but branching on `liveItem` would change the TabView's identity and reset every tab's navigation stack. That's why the 26.1 `isEnabled:` overload is the one used.

```swift
/// Applies the Live Now accessory on iOS 26.1+ (`isEnabled:` keeps the TabView's
/// identity stable as live state flips); no-op on earlier OSes, where the
/// Journal's live strip remains the entry point.
private struct LiveNowAccessoryModifier<Accessory: View>: ViewModifier {
    let isEnabled: Bool
    @ViewBuilder let accessory: () -> Accessory

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: isEnabled) { accessory() }
        } else {
            content
        }
    }
}
```

> `liveNowAccessory` is `@available(iOS 26.1, *)`, so the closure has to be built inside an availability context. If the compiler rejects referencing it from the non-gated call site, wrap the call-site closure body in `if #available(iOS 26.1, *) { liveNowAccessory }`. Do whichever compiles — the build is the arbiter.

- [ ] **Step 6: Present the accessory's covers/sheet** — add to `MainTabView.body` next to the existing `.sheet`s (`:229-265`). This mirrors `JournalView.swift:369-383`:

```swift
            .fullScreenCover(item: $liveAccessory.recordingGame) { game in
                DirectCameraRecorderView(athlete: selectedAthlete, game: game)
            }
            .fullScreenCover(item: $liveAccessory.recordingPractice) { practice in
                DirectCameraRecorderView(athlete: selectedAthlete, practice: practice)
            }
            .sheet(item: $liveAccessory.scoreTarget) { target in
                switch target.parent {
                case .game(let game):
                    HoleScoringSheet(game: game, holeNumber: target.holeNumber)
                case .practice(let practice):
                    HoleScoringSheet(practice: practice, holeNumber: target.holeNumber)
                }
            }
```

(Verified: `JournalView.swift:377-384` puts no extra modifiers on `HoleScoringSheet`, so this is an exact mirror.)

- [ ] **Step 7: Build.** Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Verify on the iOS 27 sim — baseball profile.** Start a game (live).
  - The accessory appears above the tab bar: "● Live vs {opponent}" and a "Record" button.
  - Switch tabs → it stays.
  - Scroll → the tab bar minimizes, the accessory goes inline, and Record shows as icon-only.
  - Tap Record → the camera opens bound to that game. Save a clip → it appears on that game.
  - Tap the text → you land on the Journal.
  - End the game → the accessory disappears, and no tab loses its navigation stack.
- [ ] **Step 9: Verify on the iOS 27 sim — golf profile.** Start a round → "Score" opens `HoleScoringSheet` on the same hole the Journal card names. Start a range session → "Record".
- [ ] **Step 10: Verify on an iOS 26.0 sim** (installed: `iOS 26.0 (26.0.1)`). Expected: no accessory at all, no crash, minimize still works.
- [ ] **Step 11: Verify on the iOS 18 sim.** Expected: no accessory, identical to baseline.
- [ ] **Step 12: Commit**

```bash
git add PlayerPath/Views/Navigation/LiveNowAccessory.swift PlayerPath/Views/Navigation/MainTabView.swift
git commit -m "Live Now tab-bar accessory for in-progress games (iOS 26.1+)"
```

---

### Task 5: Final pass

- [ ] **Step 1:** Run `/review` over `06d3f1fd..HEAD`.
- [ ] **Step 2:** Update `docs/quick-reference/` if it documents the tab bar appearance. Grep first: `grep -rn "configureWithOpaqueBackground\|tab bar" docs/quick-reference`.
- [ ] **Step 3:** Device test on Trey's phone: Journal photo scroll (glass tint), minimize, and a real live game with Record from the accessory.
- [ ] **Step 4:** Save a project memory recording the shipped state and the sign-off outcome from Task 1 Step 5.

## Explicitly not in this plan

- Content redesign (thumbnails and W/L on game cards, fewer all-caps labels, legacy Stats cards) → next plan.
- `.buttonStyle(.glass)` / `.glassProminent` on in-content buttons → decide after seeing Tasks 1-4 on device. Glass on flat cream reads weakly, so don't apply it everywhere up front.
- iOS 27-only APIs (`CrossFadeNavigationTransition`, `reorderable`) → nothing in the current UI needs them.
- Search as a tab (`Tab(role: .search)`) → the tabs use `.tabItem`, not the `Tab` API. Converting is a larger change with no clear payoff yet.
