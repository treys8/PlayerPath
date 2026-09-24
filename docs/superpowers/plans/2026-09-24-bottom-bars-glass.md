# Bottom Action Bars: `ppBottomBar` + Glass Buttons — Implementation Plan (Batch 3 of 5)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (or subagent-driven-development). Steps use `- [ ]`.

**Goal:** Move the 7 pinned bottom action bars off their opaque `safeAreaInset` backgrounds and onto `safeAreaBar`, so content scrolls under them with the iOS 26 scroll-edge effect. Their primary buttons become `.glassProminent`, following the coach draft publish bar precedent (c7a8236).

**Architecture:** `GlassChrome.swift` gets four additions: a `ppBottomBar(fallbackBackground:)` overload, `ppGlassBarButton(tint:fallback:)`, `ppLegacyBarLabel(_:)` and `ppBarPanelGlass()`. Every bar drops its own `.background(...)`, and the helper applies that same background **only before iOS 26**. The helpers hold all the `#available` checks, so call sites carry none. Pre-26 the bars keep the exact `safeAreaInset` + background + button styling they have today.

**Tech stack:** SwiftUI; iOS 26 `safeAreaBar`, `.buttonStyle(.glassProminent)`, `glassEffect`. The deployment target stays iOS 17.

**Spec:** the 2026-09-23 palette/glass audit, batch #3 (`docs/superpowers/plans/2026-09-23-capture-overlays-glass.md`, "The 5-batch breakdown"). Trey's 2026-09-24 request names the 7 bars: SeasonComparisonView, GolfSeasonComparisonView, InviteCoachSheet, the GolfScorecardView editorPanel, HoleNavBar (via QuickScoreContent and ShotByShotContent) and BatchClipTagEditor. The 3 `.brandNavy` uses in GolfSeasonComparisonView are folded in, so that screen gets one test pass (the batch-1 precedent).

## Global Constraints

- Deployment target stays **iOS 17.0**. Every iOS 26 API goes through `GlassChrome.swift`, so call sites carry no `#available`.
- **The pre-26 look must render exactly as it does today.** The overload's fallback is `safeAreaInset(edge: .bottom) { bar().background(X) }`, where X is the background each bar has today. Every legacy label/button style moves into a `fallback`/`legacy` closure **verbatim**.
- The existing `ppBottomBar(isPresented:bar:)` (VStack fallback, used by `CoachVideoPlayerView`) is **not changed**.
- Colors: `Theme` + `@Environment(\.ppAccent)` only. Never add `.brandNavy`. Golf-only screens that already hardcode `Theme.golfAccent` keep that token.
- Type scale is out of scope. Leave `.headingMedium` etc. as they are (the type migration is separate).
- No Swift test target. "Test" = a clean build + the stated simulator check. All 7 bars are reachable in the sim (no camera involved).
- **Commit only the files each task names.** The working tree has unrelated edits (`Models/PlayResultAccumulator.swift`, `Views/Games/GameDetailView.swift`) that must NOT be staged. Commit directly to `main`, one commit per task. Never touch version/build numbers.

Build (every task):
```bash
cd /Users/Trey/Desktop/PlayerPath && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PlayerPath.xcodeproj \
  -scheme PlayerPath -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | head -20
```

## Verified facts (repo @ fea25a6)

| Fact | Source |
|---|---|
| The existing `ppBottomBar(isPresented:bar:)`: 26 → `safeAreaBar(edge: .bottom)`; pre-26 → `VStack { self; bar().background(Theme.surface) }`. Its only caller is `CoachVideoPlayerView.swift:593` | `GlassChrome.swift`, grep |
| All 7 bars pin with `.safeAreaInset(edge: .bottom)`, always visible, directly on a `List`/`ScrollView`, so `safeAreaBar` gets a scroll view to edge-effect | read |
| Bar backgrounds today: compare ×2 → `Theme.surface`; invite → `Theme.surface`; HoleNavBar → `.bar`; scorecard hint + editor → `.bar`; batch editor → `.ultraThinMaterial`. Each is the **last** modifier on the bar view | `SeasonComparisonView.swift:202`, `GolfSeasonComparisonView.swift:282`, `InviteCoachSheet.swift:227`, `HoleNavBar.swift:58`, `GolfScorecardView.swift:275, 349`, `BatchClipTagEditor.swift:112` |
| The pin sites: `SeasonComparisonView.swift:171`, `GolfSeasonComparisonView.swift:251`, `InviteCoachSheet.swift:182`, `QuickScoreContent.swift:247-257`, `ShotByShotContent.swift:209-215`, `GolfScorecardView.swift:131`, `BatchClipTagEditor.swift:103-113` | read |
| Button styling today: compare ×2 = default style + a filled `RoundedRectangle(.cornerLarge)` label; invite = `PremiumButtonStyle` + a filled `.cornerXLarge` label (54pt) + a shadow; HoleNavBar primary = `ScaleButtonStyle` + a filled Capsule (44pt); batch = `.borderedProminent` | read |
| `.brandNavy` in GolfSeasonComparisonView: `:182` (table header fill 0.1), `:385` (ACTIVE badge), `:404` (checkmark). The baseball twin uses `ppAccent` in all three places | read |
| `BatchClipTagEditor` already reads `ppAccent` (checkmarks, `:153`). Its presenters are golf-only (`HoleDetailView:264`, `ClubDetailView:102`) | grep |
| Precedent: `ClipReviewPublishBar` uses `.glassProminent` + `.tint(ppAccent)` + `.controlSize(.large)` with `.disabled(isBusy)` | `Views/Coach/Review/ClipReviewPublishBar.swift:44-48` |
| `.spacingSmall` = 8, `.spacingMedium` = 12, `.cornerXLarge` = 16 | `DesignTokens.swift:27-36` |

## Review Focus

1. **Disabled glass buttons (iOS 26):** Compare with 0–1 seasons picked, Send Invitation with an empty email, Save & Next at score 0, and Assign with 0 clips should all look clearly disabled and do nothing on tap. If `.glassProminent` greys them too faintly, that's acceptable only if the button still reads as a button.
2. **The scorecard editor panel over a scrolling scorecard (iOS 26):** the chip grid, segmented Par picker and toggles in a regular-glass card must stay legible while the OUT/IN rows scroll behind it. If they don't, tint the card with `Theme.surface.opacity(0.6)` in `ppBarPanelGlass` and record the value.
3. **Keyboard + the invite bar:** with the email field focused, Send Invitation must sit above the keyboard (as it does today), and interactive scroll-to-dismiss must still work.
4. **The last row is reachable:** in every screen, scroll to the bottom. The last list row, hole or chart must clear the bar (`safeAreaBar` insets the content; it must not be hidden underneath).
5. **Golf green vs terracotta:** HoleNavBar, the golf compare bar and the batch editor are green. The baseball compare bar is terracotta. The invite bar follows the athlete's sport.

---

### Task 1: Bar helpers + both season-compare bars (+ golf compare navy)

**Files:**
- Modify: `PlayerPath/Views/Navigation/GlassChrome.swift`
- Modify: `PlayerPath/SeasonComparisonView.swift:171, 184-203`
- Modify: `PlayerPath/Views/Stats/GolfSeasonComparisonView.swift:182, 251, 264-283, 385, 404`

**Produces:** `ppBottomBar(fallbackBackground:bar:)`, `ppGlassBarButton(tint:fallback:)`, `ppLegacyBarLabel(_:)` (all `View` extensions; Tasks 2–5 use them).

- [ ] **Step 1: Add the three helpers** to the `extension View` in `GlassChrome.swift`, directly after the existing `ppBottomBar(isPresented:bar:)`:

```swift
    /// Pins an always-visible bottom action bar over a List/ScrollView. iOS 26:
    /// `safeAreaBar`, so content scrolls under the bar with the system
    /// scroll-edge effect and the bar draws no background of its own. Before 26:
    /// `safeAreaInset` on `fallbackBackground` — the layout these bars had
    /// before iOS 26 (content scrolls under the translucent ones).
    @ViewBuilder
    func ppBottomBar<Bar: View, Background: ShapeStyle>(
        fallbackBackground: Background,
        @ViewBuilder bar: () -> Bar
    ) -> some View {
        if #available(iOS 26, *) {
            self.safeAreaBar(edge: .bottom) { bar() }
        } else {
            self.safeAreaInset(edge: .bottom) { bar().background(fallbackBackground) }
        }
    }

    /// The primary button in a `ppBottomBar`. iOS 26: large `.glassProminent`
    /// tinted `tint` (the system draws the disabled state). Before 26: `fallback`
    /// re-applies the button style the bar has always used.
    @ViewBuilder
    func ppGlassBarButton<Fallback: View>(
        tint: Color,
        fallback: (Self) -> Fallback
    ) -> some View {
        if #available(iOS 26, *) {
            self
                .buttonStyle(.glassProminent)
                .tint(tint)
                .controlSize(.large)
        } else {
            fallback(self)
        }
    }

    /// The label half of `ppGlassBarButton`: before 26, `legacy` adds the fill,
    /// padding and foreground the label has always drawn itself. On iOS 26 the
    /// label stays bare so the glass button supplies them.
    @ViewBuilder
    func ppLegacyBarLabel<Legacy: View>(_ legacy: (Self) -> Legacy) -> some View {
        if #available(iOS 26, *) {
            self
        } else {
            legacy(self)
        }
    }
```

- [ ] **Step 2: Baseball compare bar.** In `SeasonComparisonView.swift`, replace the whole `compareBar` (lines 184-203) with:

```swift
    private var compareBar: some View {
        Button {
            Haptics.light()
            isComparing = true
        } label: {
            Text(canCompare ? "Compare \(selectedSeasons.count) Seasons" : "Compare")
                .font(.headingMedium)
                .frame(maxWidth: .infinity)
                .ppLegacyBarLabel {
                    $0
                        .foregroundStyle(.white)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous)
                                .fill(canCompare ? ppAccent : Theme.textTertiary)
                        )
                }
        }
        .ppGlassBarButton(tint: ppAccent) { $0 }
        .disabled(!canCompare)
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
```

(Pre-26 this is the same modifier chain as before: `foregroundStyle` is environment-scoped, so moving it after `frame` changes nothing. `.background(Theme.surface)` moves to the pin site.)

Then change line 171 from `.safeAreaInset(edge: .bottom) { compareBar }` to:

```swift
            .ppBottomBar(fallbackBackground: Theme.surface) { compareBar }
```

- [ ] **Step 3: Golf compare bar.** In `GolfSeasonComparisonView.swift`, replace `compareBar` (lines 264-283) with the code below. This view has no `ppAccent` property, so it keeps the hardcoded golf token:

```swift
    private var compareBar: some View {
        Button {
            Haptics.light()
            isComparing = true
        } label: {
            Text(canCompare ? "Compare \(selectedSeasons.count) Seasons" : "Compare")
                .font(.headingMedium)
                .frame(maxWidth: .infinity)
                .ppLegacyBarLabel {
                    $0
                        .foregroundStyle(.white)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous)
                                .fill(canCompare ? Theme.golfAccent : Theme.textTertiary)
                        )
                }
        }
        .ppGlassBarButton(tint: Theme.golfAccent) { $0 }
        .disabled(!canCompare)
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
```

Change line 251 to:

```swift
            .ppBottomBar(fallbackBackground: Theme.surface) { compareBar }
```

- [ ] **Step 4: Golf compare navy → golf accent** (same file; this mirrors the baseball twin's `ppAccent` at the same three spots):
  - `:182` `.background(Color.brandNavy.opacity(0.1))` → `.background(Theme.golfAccent.opacity(0.1))`
  - `:385` `.background(Color.brandNavy)` → `.background(Theme.golfAccent)`
  - `:404` `.foregroundStyle(isSelected ? Color.brandNavy : Color.gray)` → `.foregroundStyle(isSelected ? Theme.golfAccent : Color.gray)`

- [ ] **Step 5: Verify no navy is left and the build passes.**

```bash
cd /Users/Trey/Desktop/PlayerPath && grep -n "brandNavy\|safeAreaInset" PlayerPath/SeasonComparisonView.swift PlayerPath/Views/Stats/GolfSeasonComparisonView.swift
```
Expected: no output. Then run the build. Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Sim check (iOS 26.4).** Stats tab → Compare Seasons, on a baseball athlete with ≥2 seasons: at 0/1 selected the button is disabled glass; at 2 it reads "Compare 2 Seasons" as terracotta glass and opens the comparison; the season rows scroll under the bar with the edge blur, and the last row clears it. Repeat on a golf athlete: the bar is green glass, the ACTIVE badge and checkmarks are green, and the table's header cells have a faint green fill.

- [ ] **Step 7: Commit.**

```bash
git add PlayerPath/Views/Navigation/GlassChrome.swift PlayerPath/SeasonComparisonView.swift PlayerPath/Views/Stats/GolfSeasonComparisonView.swift
git commit -m "Season compare bars: safeAreaBar + glass Compare on iOS 26; golf compare navy → golf accent

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Invite Coach send bar

**Files:**
- Modify: `PlayerPath/Views/Coaches/InviteCoachSheet.swift:182, 198-228`

**Interfaces:** consumes `ppBottomBar(fallbackBackground:bar:)`, `ppGlassBarButton(tint:fallback:)` and `ppLegacyBarLabel(_:)` from Task 1.

- [ ] **Step 1: Replace `sendButton`** (the doc comment + property, lines 198-228) with:

```swift
    /// Primary action, pinned to the bottom so it's always visible without
    /// scrolling. iOS 26: a glass button on a `safeAreaBar`, with the form
    /// scrolling under it. Before 26: the filled button on an opaque surface.
    private var sendButton: some View {
        Button(action: sendInvitation) {
            HStack(spacing: 10) {
                if isSending {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "paperplane.fill")
                }
                Text(isSending ? "Sending..." : "Send Invitation")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .ppLegacyBarLabel {
                $0
                    .frame(height: 54)
                    .foregroundColor(.white)
                    .background(
                        RoundedRectangle(cornerRadius: .cornerXLarge, style: .continuous)
                            .fill(canSend ? ppAccent : Theme.textTertiary)
                    )
                    .shadow(color: canSend ? ppAccent.opacity(0.3) : .clear, radius: 12, x: 0, y: 6)
            }
        }
        .ppGlassBarButton(tint: ppAccent) { $0.buttonStyle(PremiumButtonStyle()) }
        .disabled(!canSend)
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
```

- [ ] **Step 2: Change the pin** at line 182 from `.safeAreaInset(edge: .bottom) { sendButton }` to:

```swift
            .ppBottomBar(fallbackBackground: Theme.surface) { sendButton }
```

- [ ] **Step 3: Build.** Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Sim check.** More → Coaches → Invite: the button is disabled glass until a name and a valid email are entered, then terracotta glass (green on a golf athlete). Focus the email field: the button rides above the keyboard, and dragging the form down dismisses the keyboard. While sending, the white spinner shows on the prominent glass.

- [ ] **Step 5: Commit.**

```bash
git add PlayerPath/Views/Coaches/InviteCoachSheet.swift
git commit -m "Invite Coach: glass Send Invitation on a safeAreaBar (iOS 26)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: HoleNavBar (Quick + Shot-by-shot scoring)

**Files:**
- Modify: `PlayerPath/Views/Games/HoleNavBar.swift` (header comment `:5-11`, primary button `:42-54`, background `:58`)
- Modify: `PlayerPath/Views/Games/QuickScoreContent.swift:247`
- Modify: `PlayerPath/Views/Games/ShotByShotContent.swift:209`

**Interfaces:** consumes the Task 1 helpers.

- [ ] **Step 1: The HoleNavBar header comment.** Replace `` Pinned via
//  `.safeAreaInset(edge: .bottom)` by both scoring bodies `` with `` Pinned via
//  `ppBottomBar(fallbackBackground: .bar)` by both scoring bodies `` (re-wrap the line to keep the comment's width).

- [ ] **Step 2: The primary button.** Replace lines 42-54 with:

```swift
            Button(action: onPrimary) {
                Text(primaryTitle)
                    .font(.bodyLarge)
                    .fontWeight(.semibold)
                    .ppLegacyBarLabel {
                        $0
                            .foregroundColor(.white)
                            .padding(.horizontal, .spacingLarge)
                            .frame(height: 44)
                            .background(
                                Capsule().fill(primaryDisabled ? Color.secondary.opacity(0.5) : Theme.golfAccent)
                            )
                    }
            }
            .ppGlassBarButton(tint: Theme.golfAccent) { $0.buttonStyle(ScaleButtonStyle()) }
            .disabled(primaryDisabled)
```

The Prev chevron and the "Hole X of N" text stay as they are. They're plain glyphs/text, and the scroll-edge effect keeps them readable.

- [ ] **Step 3: Remove the bar's own background.** Delete line 58, `.background(.bar)`.

- [ ] **Step 4: The two pin sites.** In `QuickScoreContent.swift:247` and `ShotByShotContent.swift:209`, change `.safeAreaInset(edge: .bottom) {` to:

```swift
        .ppBottomBar(fallbackBackground: .bar) {
```

The closure bodies (comments + `HoleNavBar(...)`) are unchanged.

- [ ] **Step 5: Confirm nothing else pins HoleNavBar, then build.**

```bash
cd /Users/Trey/Desktop/PlayerPath && grep -rn "HoleNavBar(" PlayerPath
```
Expected: exactly the 2 call sites. Build → `BUILD SUCCEEDED`.

- [ ] **Step 6: Sim check.** A golf round → score a hole (Quick): at score 0 the primary is disabled glass; after picking a score it reads "Save & Next" as green glass and advances; Prev works from hole 2; on the last hole it reads "Save & Finish" and dismisses. Switch to shot-by-shot: "Next ›"/"Done" is always enabled. In both modes, the content's last card scrolls clear of the bar.

- [ ] **Step 7: Commit.**

```bash
git add PlayerPath/Views/Games/HoleNavBar.swift PlayerPath/Views/Games/QuickScoreContent.swift PlayerPath/Views/Games/ShotByShotContent.swift
git commit -m "HoleNavBar: safeAreaBar + glass primary on iOS 26 (quick + shot-by-shot scoring)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Golf scorecard editor panel

**Files:**
- Modify: `PlayerPath/Views/Navigation/GlassChrome.swift`
- Modify: `PlayerPath/Views/Games/GolfScorecardView.swift:131, 253-275, 349`

**Interfaces:** consumes `ppBottomBar(fallbackBackground:bar:)`. Produces `ppBarPanelGlass(cornerRadius:)`.

This bar isn't a button: it's a tall control panel (running total, par picker, score chips, toggles, optional putts/detail rows). On iOS 26, with no background at all, the chips would sit directly over scorecard rows. So on 26 it floats as an inset regular-glass card, the Liquid Glass idiom for a floating panel. Before 26 nothing changes.

- [ ] **Step 1: Add the helper** to the `extension View` in `GlassChrome.swift`, after `ppLegacyBarLabel`:

```swift
    /// A tall control panel pinned by `ppBottomBar(fallbackBackground:)` (the
    /// scorecard's hole editor). iOS 26: a regular-glass card inset from the
    /// screen edges, so the controls get their own surface while the content
    /// scrolls behind. No-op before 26 — the bar's fallback background covers it.
    @ViewBuilder
    func ppBarPanelGlass(cornerRadius: CGFloat = 24) -> some View {
        if #available(iOS 26, *) {
            self
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .padding(.horizontal, .spacingMedium)
                .padding(.bottom, .spacingSmall)
        } else {
            self
        }
    }
```

- [ ] **Step 2: Wrap `editorPanel`** (lines 252-260, including its `@ViewBuilder`) so both branches get the card:

```swift
    @ViewBuilder
    private var editorPanel: some View {
        Group {
            if isHoleShotLocked(selectedHole) {
                shotTrackedHint
            } else {
                scoreEditorPanel
            }
        }
        .ppBarPanelGlass()
    }
```

- [ ] **Step 3: Remove the two `.background(.bar)` lines.** Delete `.background(.bar)` at the end of `shotTrackedHint` (`:275`) and at the end of `scoreEditorPanel` (`:349`). Keep their `.padding(.spacingMedium)` (and the hint's `.frame(maxWidth: .infinity)`).

- [ ] **Step 4: Change the pin** at line 131 from `.safeAreaInset(edge: .bottom) { editorPanel }` to:

```swift
            .ppBottomBar(fallbackBackground: .bar) { editorPanel }
```

- [ ] **Step 5: Build.** Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Sim check.** A golf round → Scorecard: the editor is a floating glass card. Pick scores, flip Par, and toggle Putts and Details on (the card grows). Scroll the OUT/IN tables behind it: the chips, the segmented picker and the Round Total stay legible (Review Focus #2; if not, tint per that note). Select a shot-tracked hole: the hint shows in the same card. The IN table's last row can scroll clear of the card with Putts + Details on.

- [ ] **Step 7: Commit.**

```bash
git add PlayerPath/Views/Navigation/GlassChrome.swift PlayerPath/Views/Games/GolfScorecardView.swift
git commit -m "Golf scorecard: hole editor floats as a glass card on a safeAreaBar (iOS 26)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Batch clip tag editor + wrap-up

**Files:**
- Modify: `PlayerPath/Views/Games/BatchClipTagEditor.swift:103-113`
- Modify (memory, not the repo): `project_ios26_liquid_glass_chrome.md`

**Interfaces:** consumes `ppBottomBar(fallbackBackground:bar:)` and `ppGlassBarButton(tint:fallback:)`.

- [ ] **Step 1: Replace lines 103-113** (the `.safeAreaInset` block) with:

```swift
            .ppBottomBar(fallbackBackground: .ultraThinMaterial) {
                Button(action: apply) {
                    Text(applyLabel)
                        .font(.headingMedium)
                        .frame(maxWidth: .infinity)
                }
                .ppGlassBarButton(tint: ppAccent) { $0.buttonStyle(.borderedProminent) }
                .disabled(!canApply)
                .padding()
            }
```

(The label is the same on both OSes, so no `ppLegacyBarLabel`. Pre-26 keeps `.borderedProminent` with its inherited tint, exactly as today.)

- [ ] **Step 2: Build + verify every target site is converted.**

```bash
cd /Users/Trey/Desktop/PlayerPath && grep -n "safeAreaInset(edge: .bottom)" PlayerPath/SeasonComparisonView.swift PlayerPath/Views/Stats/GolfSeasonComparisonView.swift PlayerPath/Views/Coaches/InviteCoachSheet.swift PlayerPath/Views/Games/GolfScorecardView.swift PlayerPath/Views/Games/QuickScoreContent.swift PlayerPath/Views/Games/ShotByShotContent.swift PlayerPath/Views/Games/BatchClipTagEditor.swift
```
Expected: no output. Build → `BUILD SUCCEEDED`.

- [ ] **Step 3: Sim check.** A golf round with ≥2 clips → a hole's detail → batch tag (hole mode), then the Clubs detail → batch tag (club mode): "Assign to N clips" is disabled glass at 0 selected and green glass once clips are picked; applying tags works; the clip list scrolls under the bar.

- [ ] **Step 4: Commit.**

```bash
git add PlayerPath/Views/Games/BatchClipTagEditor.swift
git commit -m "Batch clip tag editor: glass Assign on a safeAreaBar (iOS 26)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 5: Run `/review`** on `fea25a6..HEAD`, fix what's real, and commit the fixes as "Batch 3 review fixes: …".

- [ ] **Step 6: Update memory** `project_ios26_liquid_glass_chrome.md` with a "Bottom bars (batch 3 of 5)" paragraph: the commit range, the four helpers and when to use which `ppBottomBar`, the scorecard card tint value if it changed, the `.brandNavy` count after the batch (`grep -rn "brandNavy" PlayerPath | wc -l`, expected 196; it was 199 at fea25a6), and which sim checks passed or are pending. Also update the MEMORY.md hook line to "batches 1–3/5 done".
