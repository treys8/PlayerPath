# Floating Toasts, Banners & HUDs: Liquid Glass — Implementation Plan (Batch 5 of 5)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (or subagent-driven-development). Steps use `- [ ]`.

**Goal:** Move the app's floating transient surfaces onto iOS 26 Liquid Glass: the shared toast, the "Athlete created" toast, the three top banners (activity, highlight reel, milestone) and five progress HUDs. Also fix the shared toast's white-on-light text.

**Architecture:** `GlassChrome.swift` gets three helpers:
- `ppFloatingGlass(in:fallback:)` — light (non-forced-scheme) regular glass for toasts and banners.
- `ppBannerGlass()` — the shared banner card built on it.
- `ppHUDGlass(cornerRadius:)` — the existing dark `ppDarkGlassPanel` for HUDs over a dimmed screen, whose copy is white.

Each fallback reproduces the site's pre-26 background (material + shadow). The one deliberate every-OS change is the toast fix in Task 2.

**Tech stack:** SwiftUI; iOS 26 `glassEffect`. The deployment target stays iOS 17.

**Spec:** the 2026-09-23 palette/glass audit, batch #5 (`docs/superpowers/plans/2026-09-23-capture-overlays-glass.md`: "Floating toasts/banners: a new light-scheme glass helper plus the ~11 banner/toast/progress sites"). The sites were enumerated fresh on 2026-09-24 (below). Glass goes only on surfaces that **float over** content. Per Apple's guidance, inline content banners stay as they are.

## Site inventory (2026-09-24 grep of every `*Material` outside GlassChrome)

| # | Site | Surface | Pre-26 background today | Glass |
|---|---|---|---|---|
| 1 | `Views/Components/ToastModifier.swift:55` | shared `.toast()` capsule, 18 call sites | `.ultraThinMaterial` capsule, **white** text | light (Task 2) |
| 2 | `Views/Athletes/UserMainFlow.swift:205` | "Athlete created" top toast | `.ultraThinMaterial` capsule | light |
| 3 | `Views/Shared/ActivityNotificationBanner.swift:63-64` | top banner | `.regularMaterial` r`.cornerXLarge` + shadow(0.12, 8, y4) | light |
| 4 | `Views/Shared/HighlightReelBanner.swift:86-87` | top banner | same as #3 | light |
| 5 | `Views/Shared/MilestoneCelebrationBanner.swift:90-91` | top banner | same as #3 | light |
| 6 | `LoadingOverlay.swift:38-42` | full-screen HUD (sign-out, purchase) over black 0.4 | `.ultraThinMaterial` r`.cornerXLarge` + `.shadow(radius: 10)`, white text | dark |
| 7 | `Views/Coaches/ShareToCoachFolderView.swift:194` | upload HUD over black 0.35 | `.ultraThinMaterial` r16, white text | dark |
| 8 | `Views/Photos/BulkPhotoImportAttach.swift:148` | import HUD over black 0.4 | `.ultraThinMaterial` r16, white text | dark |
| 9 | `Views/Components/VideoClipCard.swift:216` | "Saving to Photos" HUD over black 0.4 | `.ultraThinMaterial` r`.cornerLarge` | dark |
| 10 | `SeasonDetailView.swift:386` | spinner HUD over black 0.3 | `.ultraThinMaterial` r12 | dark |

**Out of scope (and why):**
- `UploadStatusBanner`, `UntaggedClipsBanner`, `PhotoBackupBlockedBanner` are **inline** in a scroll view: content layer, no glass. UploadStatusBanner's 4 navy uses get a palette-only fix in Task 5, because it's the last navy on a banner.
- The thumbnail badges (`VideoThumbnailView`, `RemoteThumbnailView`, `PhotoThumbnailCell`, `PhotoHeroCell`, `AnnotationBadgeCluster`, the CoachFolderComponents "Viewed" pill) are many instances in scrolling grids. That's a performance and legibility question for a separate pass.
- The `PhotoDetailView` caption panel, the onboarding cards, `CurrentHoleStepper` and the telestration panel already have glass or belong to another surface.
- The solid colored toasts in `BulkImportAttach`/`BulkPhotoImportAttach` (`toastKind.color` capsules) are status colors, not material.
- The **highlight-reel gold** (HighlightReelBanner icon, TodaysReelHeroCard) is a deliberate highlights color family ("reel surfaces' brand gold", per MilestoneCelebrationBanner's header). Recoloring it is a design call, not part of this batch.

## Global Constraints

- Deployment target stays **iOS 17.0**. Every iOS 26 API goes through `GlassChrome.swift`, so call sites carry no `#available`.
- **Pre-26 fallbacks reproduce each site's current background verbatim.** The single exception is Task 2's toast fix, which is deliberate and applies on every OS.
- The app forces `.preferredColorScheme(.light)` (`MainAppView.swift:81`), so "light glass" means plain `.regular` glass with no scheme override. HUD glass forces dark (via `ppDarkGlassPanel`) because its copy is white.
- On iOS 26, glass draws its own depth, so drop the shadows there (the batch 1 precedent) and keep them in the fallbacks.
- Colors: `Theme` + `@Environment(\.ppAccent)` only. Never add `.brandNavy`.
- No Swift test target. "Test" = a clean build + the grep in each task + the stated simulator check.
- **Commit only the files each task names.** The working tree has unrelated edits (`Models/PlayResultAccumulator.swift`, `Views/Games/GameDetailView.swift`) that must NOT be staged. Commit directly to `main`, one commit per task. Never touch version/build numbers.

Build (every task):
```bash
cd /Users/Trey/Desktop/PlayerPath && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PlayerPath.xcodeproj \
  -scheme PlayerPath -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | head -20
```

## Verified facts (repo @ af35e79)

| Fact | Source |
|---|---|
| `ppDarkGlassPanel(in:tint:interactive:fallback:)` exists and forces `.colorScheme(.dark)` on 26 | `GlassChrome.swift` |
| The three top banners end with the identical pair `.background(.regularMaterial, in: RoundedRectangle(cornerRadius: .cornerXLarge))` + `.shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)`, followed by `.padding(.horizontal, 16)` | read ×3 |
| All three banners and the "Athlete created" toast are hosted in `UserMainFlow`'s top `.overlay` (`:199-259`) | read |
| **Toast bug:** `ToastModifier` sets `.foregroundStyle(.white)` on a `.ultraThinMaterial` capsule. In the forced-light app that material is near-cream over the cream surfaces most of its 18 call sites sit on (sheets, lists), so the message is white-on-light. `ToastType.color` (`.success`/`.info`/`.warning`) is defined but never used | `ToastModifier.swift:23-29, 50-55`; `DesignTokens.swift:104-107` |
| Toasts also appear over **dark video** (`VideoPlayerView.swift:826`, `CoachVideoPlayerView.swift:321-323`), where the old white text happened to work | grep `.toast(` |
| `Color.success` = `Color.green`, `Color.info` = `Color.blue` (system colors, off-palette) | `DesignTokens.swift:104-107` |
| `LoadingOverlay` preview uses `Color.brandNavy` (`:88`); `UploadStatusBanner` navy at `:76, 121, 131, 265` (`UploadBadge` at `:265` has no call sites) | grep |
| Counts at start: `.brandNavy` **165** | grep |

## Review Focus

1. **Toast over dark video vs over cream:** "Saved to Photos" in the video player (dark) and "Invitation Sent" in the Invite Coach sheet (cream) must both be readable, on iOS 26 (glass) and in the pre-26 fallback (`.regularMaterial`, which the sim can't show). If the iOS 26 glass over dark video renders dark text on dark glass, tint the toast glass `Theme.surface.opacity(0.5)` in `ppFloatingGlass`'s toast call and record it.
2. **Banner stack:** the Activity + Highlight Reel banners can show at once (stacked in the `VStack(spacing: 8)`). Two glass cards 8pt apart may visually merge/morph. They're separate `glassEffect`s with no `GlassEffectContainer`, so they shouldn't, but check it.
3. **HUD legibility over a light screen:** the dimmer (black 0.3–0.4) sits under dark glass, so the white copy and spinner must be clear on the Sign Out HUD (Profile) and the Season "processing" spinner.
4. **Tap targets on the banners:** the glass must not swallow taps. Tapping the banner body still navigates/opens the reel, and the ✕ still only dismisses.
5. **The toast's success icon color:** `Theme.chipGreenText` on glass should read as "success" without the bright system green. If it looks muddy, fall back to `.success` for the icon only.

---

### Task 1: Glass helpers + the three top banners + the creation toast

**Files:**
- Modify: `PlayerPath/Views/Navigation/GlassChrome.swift`
- Modify: `PlayerPath/Views/Shared/ActivityNotificationBanner.swift:63-64`
- Modify: `PlayerPath/Views/Shared/HighlightReelBanner.swift:86-87`
- Modify: `PlayerPath/Views/Shared/MilestoneCelebrationBanner.swift:90-91`
- Modify: `PlayerPath/Views/Athletes/UserMainFlow.swift:205`

**Produces:** `ppFloatingGlass(in:fallback:)`, `ppBannerGlass()` and `ppHUDGlass(cornerRadius:)`, all `View` extensions (Tasks 2–4 use them).

- [ ] **Step 1: Add the helpers** at the end of the `extension View` in `GlassChrome.swift`:

```swift
    /// A light surface floating over content — toasts, top banners. iOS 26:
    /// regular Liquid Glass in the app's (light) scheme; glass draws its own
    /// depth, so no shadow. Before 26: `fallback` applies the material + shadow
    /// the surface has always used.
    @ViewBuilder
    func ppFloatingGlass<S: Shape, Fallback: View>(
        in shape: S,
        fallback: (Self) -> Fallback
    ) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            fallback(self)
        }
    }

    /// The top-of-screen notification card (activity, highlight reel, milestone).
    /// iOS 26: floating glass. Before 26: the regular-material card with its soft
    /// drop shadow.
    func ppBannerGlass() -> some View {
        let shape = RoundedRectangle(cornerRadius: .cornerXLarge)
        return ppFloatingGlass(in: shape) {
            $0
                .background(.regularMaterial, in: shape)
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
        }
    }

    /// A progress HUD centered over a dimmed screen. iOS 26: dark Liquid Glass,
    /// so the white copy and spinner stay legible over whatever sits behind the
    /// dimmer. Before 26: the `.ultraThinMaterial` card these HUDs always used.
    func ppHUDGlass(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        return ppDarkGlassPanel(in: shape) {
            $0.background(.ultraThinMaterial, in: shape)
        }
    }
```

- [ ] **Step 2: The three banners.** In each of `ActivityNotificationBanner.swift`, `HighlightReelBanner.swift` and `MilestoneCelebrationBanner.swift`, replace the two lines

```swift
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: .cornerXLarge))
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
```
with
```swift
        .ppBannerGlass()
```
and leave the `.padding(.horizontal, 16)` that follows alone.

- [ ] **Step 3: The creation toast.** In `UserMainFlow.swift:205`, replace `.background(.ultraThinMaterial, in: Capsule())` with:

```swift
                        .ppFloatingGlass(in: Capsule()) { $0.background(.ultraThinMaterial, in: Capsule()) }
```

- [ ] **Step 4: Grep + build.**

```bash
cd /Users/Trey/Desktop/PlayerPath && grep -n "regularMaterial\|ultraThinMaterial" PlayerPath/Views/Shared/ActivityNotificationBanner.swift PlayerPath/Views/Shared/HighlightReelBanner.swift PlayerPath/Views/Shared/MilestoneCelebrationBanner.swift PlayerPath/Views/Athletes/UserMainFlow.swift
```
Expected: exactly one hit, the fallback inside `UserMainFlow.swift:205`. Build → `BUILD SUCCEEDED`.

- [ ] **Step 5: Sim check.**
  - End a game that has highlight-tagged clips: the reel banner slides in as a glass card over the Journal, the body opens the reel, and ✕ only dismisses.
  - A game with a personal best: the milestone banner follows as glass.
  - Create an athlete: the "Athlete created" capsule is glass.
  - Review Focus #2 and #4.

- [ ] **Step 6: Commit.**

```bash
git add PlayerPath/Views/Navigation/GlassChrome.swift PlayerPath/Views/Shared/ActivityNotificationBanner.swift PlayerPath/Views/Shared/HighlightReelBanner.swift PlayerPath/Views/Shared/MilestoneCelebrationBanner.swift PlayerPath/Views/Athletes/UserMainFlow.swift
git commit -m "Top banners + creation toast: floating Liquid Glass on iOS 26

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Shared toast — glass + the white-on-light fix

**Files:**
- Modify: `PlayerPath/Views/Components/ToastModifier.swift:23-29, 50-55`

**Interfaces:** consumes `ppFloatingGlass(in:fallback:)`.

This task deliberately changes the pre-26 look: `.ultraThinMaterial` + white text becomes `.regularMaterial` + primary text + a colored icon + the banner shadow, the same family as the top banners. The old combination was unreadable on light surfaces.

- [ ] **Step 1: On-palette icon colors.** Replace `ToastType.color` (lines 23-29) with:

```swift
    var color: Color {
        switch self {
        case .success: Theme.chipGreenText
        case .info: Theme.textSecondary
        case .warning: Theme.warning
        }
    }
```

- [ ] **Step 2: The capsule.** Replace lines 50-55 (from `Label(message, systemImage: type.icon)` through `.background(.ultraThinMaterial, in: Capsule())`) with:

```swift
                    Label {
                        Text(message).foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: type.icon).foregroundStyle(type.color)
                    }
                        .font(.headingMedium)
                        .padding(.horizontal, .spacingLarge)
                        .padding(.vertical, 10)
                        .ppFloatingGlass(in: Capsule()) {
                            $0
                                .background(.regularMaterial, in: Capsule())
                                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
                        }
```

(The following `.padding(.bottom, 100)`, `.transition` and `.task` lines are unchanged.)

- [ ] **Step 3: Grep + build.**

```bash
cd /Users/Trey/Desktop/PlayerPath && grep -n "foregroundStyle(.white)\|ultraThinMaterial" PlayerPath/Views/Components/ToastModifier.swift
```
Expected: no output. Build → `BUILD SUCCEEDED`.

- [ ] **Step 4: Sim check.** Review Focus #1 and #5:
  - More → Coaches → Invite: send, and the "Invitation Sent" toast is readable on cream.
  - Play a clip → Save to Photos: the toast is readable over the video.
  - Photos → an action that fires a warning toast: amber icon, dark text.

- [ ] **Step 5: Commit.**

```bash
git add PlayerPath/Views/Components/ToastModifier.swift
git commit -m "Toast: floating glass on iOS 26; fix white-on-light text with primary copy + on-palette icon

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: LoadingOverlay HUD

**Files:**
- Modify: `PlayerPath/LoadingOverlay.swift:37-42, 88`

**Interfaces:** consumes `ppDarkGlassPanel(in:tint:interactive:fallback:)` (existing).

`LoadingOverlay` keeps its `.shadow(radius: 10)` before 26, so it calls `ppDarkGlassPanel` directly instead of `ppHUDGlass`.

- [ ] **Step 1: Replace lines 37-42** (from `.padding(32)` through `.shadow(radius: 10)`) with:

```swift
            .padding(32)
            .ppDarkGlassPanel(in: RoundedRectangle(cornerRadius: .cornerXLarge)) {
                $0
                    .background(
                        RoundedRectangle(cornerRadius: .cornerXLarge)
                            .fill(.ultraThinMaterial)
                    )
                    .shadow(radius: 10)
            }
```

- [ ] **Step 2: The preview's navy.** Line 88: `Color.brandNavy.ignoresSafeArea()` → `Theme.surface.ignoresSafeArea()` (previewing it over the real app surface).

- [ ] **Step 3: Grep + build.**

```bash
cd /Users/Trey/Desktop/PlayerPath && grep -n "brandNavy" PlayerPath/LoadingOverlay.swift
```
Expected: no output. Build → `BUILD SUCCEEDED`.

- [ ] **Step 4: Sim check.** Profile → Sign Out → the "Signing out..." HUD is a dark glass card with a white spinner + text over the dimmed screen (Review Focus #3).

- [ ] **Step 5: Commit.**

```bash
git add PlayerPath/LoadingOverlay.swift
git commit -m "LoadingOverlay: dark Liquid Glass HUD on iOS 26

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: The four inline progress HUDs

**Files:**
- Modify: `PlayerPath/Views/Coaches/ShareToCoachFolderView.swift:194`
- Modify: `PlayerPath/Views/Photos/BulkPhotoImportAttach.swift:148`
- Modify: `PlayerPath/Views/Components/VideoClipCard.swift:216`
- Modify: `PlayerPath/SeasonDetailView.swift:386`

**Interfaces:** consumes `ppHUDGlass(cornerRadius:)`.

- [ ] **Step 1: Swap each background line** (keep the indentation of the line being replaced):
  - `ShareToCoachFolderView.swift:194` `.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))` → `.ppHUDGlass(cornerRadius: 16)`
  - `BulkPhotoImportAttach.swift:148` `.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))` → `.ppHUDGlass(cornerRadius: 16)`
  - `VideoClipCard.swift:216` `.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: .cornerLarge))` → `.ppHUDGlass(cornerRadius: .cornerLarge)`
  - `SeasonDetailView.swift:386` `.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))` → `.ppHUDGlass(cornerRadius: 12)`

- [ ] **Step 2: Grep + build.**

```bash
cd /Users/Trey/Desktop/PlayerPath && grep -n "ultraThinMaterial" PlayerPath/Views/Coaches/ShareToCoachFolderView.swift PlayerPath/Views/Photos/BulkPhotoImportAttach.swift PlayerPath/Views/Components/VideoClipCard.swift PlayerPath/SeasonDetailView.swift
```
Expected: no output. Build → `BUILD SUCCEEDED`.

- [ ] **Step 3: Sim check.**
  - Photos → bulk import ~5 photos: the import HUD is dark glass, with a legible progress bar, count and Cancel.
  - A clip card → Save to Photos: a dark glass HUD sits on the card.
  - Season detail → an edit that processes: a dark glass spinner.
  - Share to coach folder: the upload HUD, if a clip is at hand.

- [ ] **Step 4: Commit.**

```bash
git add PlayerPath/Views/Coaches/ShareToCoachFolderView.swift PlayerPath/Views/Photos/BulkPhotoImportAttach.swift PlayerPath/Views/Components/VideoClipCard.swift PlayerPath/SeasonDetailView.swift
git commit -m "Progress HUDs: dark Liquid Glass on iOS 26 (share upload, photo import, save to Photos, season)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: UploadStatusBanner palette + wrap-up

**Files:**
- Modify: `PlayerPath/Views/Components/UploadStatusBanner.swift:11-14, 76, 121, 131, 236-237, 265`
- Modify (memory, not the repo): `project_ios26_liquid_glass_chrome.md`, `MEMORY.md`

It's inline content, so no glass. Only the navy goes.

- [ ] **Step 1: Environment reads.** Add `@Environment(\.ppAccent) private var ppAccent` as a new line directly under `struct UploadStatusBanner: View {` and under `struct UploadBadge: View {`.

- [ ] **Step 2: Recolor** (match on the text, since the inserts shift lines):
  - `.fill(Color.brandNavy)` (progress fill) → `.fill(ppAccent)`
  - both `.foregroundColor(.brandNavy)` (pending icon, "Waiting...") → `.foregroundColor(ppAccent)`
  - `return .brandNavy` (in `UploadBadge.badgeColor`) → `return ppAccent`

- [ ] **Step 3: Grep (whole batch) + build.**

```bash
cd /Users/Trey/Desktop/PlayerPath && grep -c "brandNavy" PlayerPath/Views/Components/UploadStatusBanner.swift; grep -rn "brandNavy" PlayerPath | wc -l
```
Expected: `0`, then **160** (165 − 1 preview − 4 upload). Build → `BUILD SUCCEEDED`.

- [ ] **Step 4: Sim check.** Videos tab with an upload in flight (import a clip with auto-upload on): the progress bar and the "queued" icon + "Waiting..." are the sport accent (green on a golf athlete).

- [ ] **Step 5: Commit.**

```bash
git add PlayerPath/Views/Components/UploadStatusBanner.swift
git commit -m "Upload status banner: sport accent replaces navy

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 6: Run `/review`** on the batch range, fix what's real, and commit the fixes as "Batch 5 review fixes: …".

- [ ] **Step 7: Update memory.** Add a "Floating surfaces (batch 5 of 5)" paragraph to `project_ios26_liquid_glass_chrome.md`:
  - the commit range
  - the helper split: `ppFloatingGlass`/`ppBannerGlass` (light, floating), `ppHUDGlass` (dark, over a dimmer), inline banners get no glass
  - the toast fix (it was white-on-light)
  - the deferred items: thumbnail badges, the highlight-gold family, coach navy batch 4b
  - the navy count (160)
  - which sim checks are pending

Update the MEMORY.md hook to "batches 1–5/5 done".
