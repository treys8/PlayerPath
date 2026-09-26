# Journal Fixes + Three Features — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (or subagent-driven-development). Steps use `- [ ]`.

**Goal:** Fix the five issues from the 2026-09-25 Journal review and add three features: scroll-to-top on Home re-tap, a "Watch Reel" button on event cards, and an "On This Day" memory card.

**What changes for the user:**
- Scheduled games and practices move out of the feed into a compact **Up Next** strip, soonest first. Today's game gets a Start button.
- An athlete whose only activity is live or scheduled no longer sees the first-run example screen.
- The Highlights filter includes favorited photos.
- A single photo opens in the same full-screen swipe viewer as everywhere else.
- Re-tapping the Home tab pops back to the Journal root, and a second tap scrolls to the top.
- For Plus users, game and practice cards with 2+ highlights show a **Watch Reel** button that plays the stitched reel. Free users don't see it in the feed (decided 2026-09-25); they still get the post-event banner and the game screen's gated Generate Reel.
- The feed opens with one "On This Day / A Year Ago This Week" card when a past entry matches. It can be hidden for the day.

**Architecture:** All changes sit in `Views/Journal/`, plus a small tab-reselect hook in `MainTabView` and one notification name. There are four new small files:
- `JournalUpNextStrip.swift`: the strip, plus the `JournalUpcoming` rule for what counts as scheduled.
- `JournalEventReel.swift`: which clips go in a card's reel, its cache key and its title.
- `JournalAnniversary.swift`: pure Foundation date math, so it can be checked with `swiftc`.
- `JournalMemoryPicker.swift`: picks the one entry to resurface.

There are no schema changes, no sync changes and no new Firestore fields.

**Tech stack:** SwiftUI, SwiftData `@Query`, `ScrollViewReader`, `@AppStorage`. Reuses `GameService.start`, `GolfHighlightUnion`, `GenerateReelView`, `.photoViewer`/`.photoTransitionSource`, `PPCard`, `smallCapsLabel`.

**Spec:** the Journal review in this conversation (2026-09-25): issues #1–#5 and missing features #1 (scroll-to-top), #2 (reels in the feed) and #4 (On This Day).

## Global Constraints

- Deployment target **iOS 17.0**; `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. The project uses Xcode 16 synchronized folders, so new files compile automatically with no pbxproj edit.
- Colors come from `Theme` / `@Environment(\.ppAccent)` only. Type comes from the `.pp*` scale or the existing `Inter18pt-Bold` pill font. **Never use legacy tokens** (`.brandGold`, `.bodySmall`, …) in new code.
- **Scroll-perf invariants stay intact** (see `project_journal_design_and_perf` memory). No per-row relationship walks beyond what's specified here, and nothing on the per-body path that scales with the whole feed unless it's memoized.
- A `NavigationLink` row in the feed keeps `.contentShape(Rectangle())` on its label. Buttons nested inside a link's label use `.buttonStyle(.borderless)`, the pattern `LiveGameCard` uses. See the `project_journal_navlink_hittest` memory.
- The `JournalEmptyState.sampleCard` "keep in sync" contract: none of these tasks changes the always-present row layout. The reel button is conditional, so the sample card is **not** edited.
- Edit by matching the text. Line numbers are for orientation only (repo @ `ee2a987`).
- There's no Swift test target. "Test" means a clean build, plus the task's grep, plus the task's simulator check (plus the `swiftc` check in Task 7). Checks that need data the sim may lack are marked **[device/data]**. Record any you can't run as device-test pending. Don't skip them silently.
- Commit only the files each task names, one commit per task, directly to `main`. Never `git add -A`. **Never touch version/build numbers.**
- Commit message trailer: `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`

Build (every task):
```bash
cd /Users/Trey/Desktop/PlayerPath && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PlayerPath.xcodeproj \
  -scheme PlayerPath -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | head -20
```

## Verified facts (repo @ ee2a987)

| Fact | Source |
|---|---|
| Feed = games + practices (minus live) + orphan clips/photos + coach feedback, sorted by **descending** date, so future games sort to the top, furthest-future first | `JournalView.swift:166-174`, `JournalFeedBuilder.swift:92-94` |
| `Game.displayStatus` calls a nil-date, incomplete game `.scheduled`. Practices have no `isComplete` | `Models.swift:262-272`, `Models.swift:365-391` |
| Every game gets a `GameStatistics` at creation, so `gameStats == nil` means nothing. `countsTowardStats` (with `isComplete == false`) is the "any stats entered" test | `GameService.swift:259-262`, `Models.swift:251-256` |
| `GameService.end` sets `isComplete = true`, so an ended game leaves Up Next | `GameService.swift:~470` |
| GameDetailView's Start = `GameService(modelContext:).start(game)` with no season guard. It ends other live games itself | `GameDetailView.swift:628,867-869`; `GameService.swift:416-445` |
| `hasContent = !feed.isEmpty`, and live items are excluded from `feed`, so a live-only athlete gets `JournalEmptyState` | `JournalView.swift:275,307,336` |
| `containsHighlight` checks clips only. Photos have `isHighlight` ("Mark as favorite", star icon) | `JournalEntry.swift:114-121`; `Photo.swift:39-43`; `PhotoDetailView.swift:150-155` |
| A single orphan photo pushes `PhotoDetailView`. The grids use `.photoViewer` (fullScreenCover pager; it dismisses itself before calling `onDelete`) | `JournalView.swift:642-646`; `PhotoDetailView.swift:208-222,356-365` |
| `JournalFeedBuilder.build(filter:)` is only called with `.all`. The header comment in `JournalView` mentions a Golf pill and "DashboardView is preserved" | `JournalView.swift:5-13,172` |
| Both TabViews bind `$selectedTab`. The Home stack binds `homePath` | `MainTabView.swift:575,584,599` |
| Reels: golf uses `HighlightReel` rows plus starred clips, via `GolfHighlightUnion.highlightClips(from:gameID:practiceID:reels:)`, which has a deterministic order. Baseball has no reel rows: starred clips only. Needs 2+ clips | `GolfHighlightUnion.swift:86-97,124-140`; `GameDetailView.swift:85-107` |
| Reel cache scopes: `game_<id>`, `round_<id>`, `practice_<id>`, `round_practice_<id>`. The cache file name is scope + clip content hash; **the title isn't part of the key** | `UserMainFlow.swift:505-555`; `GameDetailView.swift:618`; `StitchedReelCache.swift:42-60` |
| Reel tier gate: `SubscriptionGate.effectiveAthleteTier.hasAutoHighlights` → `GenerateReelView`, otherwise `ImprovedPaywallView(user:requiredTier: .plus)` | `GameDetailView.swift:114-121`; `UserMainFlow.swift:192-197` |
| `PPMediaTile` overlay slots: center = play, topLeading = outcome chip, topTrailing = star, bottomTrailing = duration. **bottomLeading is free** | `PPMediaTile.swift:68-71` |
| All `MilestoneEngine` milestones carry a `gameID` | `MilestoneEngine.swift:47-229` |

## Review Focus

1. **Taps inside a card must not open the card, and the card must still open.** This covers the Up Next Start pill, the Watch Reel button, and the On This Day ✕. Tapping each does only its own action. Tapping anywhere else on the card still pushes the detail screen, and the filter pills above still work. (Checks 1c, 6c, 7d.)
2. **Game timing edge cases:** a game later today (in Up Next with Start). The same game after its start time, never touched (still in Up Next). The same game once a clip or stats exist (moves to the feed). Starting it (it moves to Live Now, never shown in both places). A past game never marked complete (stays in the feed). (Checks 1b, 1d.)
3. **Tab re-tap:** re-tap with a pushed detail pops to root. Re-tap at the root scrolls to the top. A normal tab switch never scrolls the Journal. Re-tapping *other* tabs changes nothing. (Check 5b.)
4. **Reel tier gating and cache sharing:** a free user never sees the button. An upgrade shows it without relaunching (observed tier). A Plus user gets the reel, and opening the same game's reel from GameDetailView afterward doesn't re-stitch (same scope and same clip order means a cache hit). (Check 6d **[device/data]**.)
5. **On This Day on filters and dates:** the card only shows on the All pill. Hiding it keeps it hidden after leaving and returning to the tab, and it comes back tomorrow. An entry with no date (`.distantPast`) never matches. Feb 29 → Feb 28. (Check 7d + the `swiftc` check 7b.)

---

### Task 1: Up Next strip (review issue #1)

**Files:**
- Create: `PlayerPath/Views/Journal/JournalUpNextStrip.swift`
- Modify: `PlayerPath/Views/Journal/JournalView.swift`

**Interfaces:**
- Produces: `enum JournalUpcomingItem` (`.game(Game)`, `.practice(Practice)`, `id: String`, `date: Date`). `enum JournalUpcoming` with `isScheduled(_ game: Game, now: Date = .now, calendar: Calendar = .current) -> Bool`, `isScheduled(_ practice: Practice, now: Date = .now) -> Bool`, `items(games:practices:now:) -> [JournalUpcomingItem]`. `struct JournalUpNextStrip: View` with `init(items:isGolfProfile:onStart:)`. In `JournalView`: `buildFeed(now: Date)` and the body locals `now` and `upcoming` (Task 2 reads `upcoming`).

- [ ] **Step 1: Create `JournalUpNextStrip.swift`**

```swift
//
//  JournalUpNextStrip.swift
//  PlayerPath
//
//  The Journal's "Up Next" strip: the next few scheduled games/practices,
//  soonest first. Scheduled events used to sit in the feed itself, sorted
//  newest-first — so a pre-loaded season schedule put the LAST game of the
//  season at the top of Home and buried everything the athlete had actually
//  done. The feed is a record of what happened; what's coming lives here.
//

import SwiftUI

/// One scheduled item in the strip.
enum JournalUpcomingItem: Identifiable {
    case game(Game)
    case practice(Practice)

    var id: String {
        switch self {
        case .game(let g):     return "upcoming-game-\(g.id.uuidString)"
        case .practice(let p): return "upcoming-practice-\(p.id.uuidString)"
        }
    }

    /// Always non-nil in practice — `JournalUpcoming.isScheduled` requires a date.
    var date: Date {
        switch self {
        case .game(let g):     return g.date ?? .distantFuture
        case .practice(let p): return p.date ?? .distantFuture
        }
    }
}

/// The single rule for "scheduled" on the Journal. The feed EXCLUDES exactly
/// what the strip INCLUDES, so an item can never show in both or neither.
enum JournalUpcoming {
    /// Not live, not finished, and either dated later than `now`, or dated
    /// today and still untouched.
    ///
    /// Deliberately NOT `Game.displayStatus == .scheduled`: that also calls a
    /// nil-date game "scheduled", and such a game belongs in the feed (sorted by
    /// createdAt), not in a strip ordered by a date it doesn't have.
    static func isScheduled(_ game: Game, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard !game.isLive, !game.isComplete, let date = game.date else { return false }
        if date > now { return true }
        // Past its start time today but never started or touched: the athlete is
        // probably running late, so keep the Start button up until midnight
        // instead of dropping an empty card into the feed. Anything with media,
        // entered stats, or a golf score was logged after the fact and belongs in
        // the feed. (Every game gets a GameStatistics at creation, so "has stats"
        // is `countsTowardStats`, not `gameStats != nil`.)
        return calendar.isDate(date, inSameDayAs: now)
            && (game.videoClips ?? []).isEmpty
            && (game.photos ?? []).isEmpty
            && !game.countsTowardStats
            && game.effectiveTotalScore == nil
    }

    /// Practices have no completed flag, and are often logged the same day
    /// after the fact — so only a strictly future-dated one counts as scheduled.
    static func isScheduled(_ practice: Practice, now: Date = .now) -> Bool {
        !practice.isLive && (practice.date ?? .distantPast) > now
    }

    /// Every scheduled game/practice, soonest first. The id breaks date ties so
    /// the order can't shuffle between renders (Swift's sort isn't stable).
    static func items(games: [Game], practices: [Practice], now: Date = .now) -> [JournalUpcomingItem] {
        let scheduled = games.filter { isScheduled($0, now: now) }.map(JournalUpcomingItem.game)
            + practices.filter { isScheduled($0, now: now) }.map(JournalUpcomingItem.practice)
        return scheduled.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }
}

struct JournalUpNextStrip: View {
    /// Already sorted soonest-first (`JournalUpcoming.items`).
    let items: [JournalUpcomingItem]
    /// The profile's pinned sport. A seasonless game can't answer `isGolf`
    /// itself, so the Start label falls back to this.
    let isGolfProfile: Bool
    let onStart: (Game) -> Void

    @Environment(\.ppAccent) private var ppAccent

    /// Enough to see what's next without the strip turning back into the flood
    /// it replaced. The full schedule lives on the Games tab.
    private static let visibleLimit = 3

    var body: some View {
        VStack(spacing: .spacingMedium) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                Text("Up Next").smallCapsLabel()
                Spacer()
                if items.count > Self.visibleLimit {
                    Button {
                        Haptics.light()
                        postSwitchTab(.games)
                    } label: {
                        Text("See all \(items.count)")
                            .font(.ppFootnote)
                            .foregroundStyle(ppAccent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)

            ForEach(items.prefix(Self.visibleLimit)) { item in
                NavigationLink {
                    destination(item)
                } label: {
                    row(item)
                        .padding(.horizontal, 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func row(_ item: JournalUpcomingItem) -> some View {
        HStack(alignment: .center, spacing: .spacingMedium) {
            VStack(alignment: .leading, spacing: 4) {
                Text(whenText(item.date)).smallCapsLabel()
                Text(title(item))
                    .font(.ppHeadline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: .spacingSmall)
            // Start is offered only for TODAY's game: that's the one you're about
            // to play. Future games open their detail screen, which has Start too.
            // A seasonless game gets no Start here: the Games tab refuses to
            // start one ("needs a season"), and clips recorded into it would
            // land seasonless. Its detail screen is one tap away.
            if case .game(let game) = item, game.season != nil, Calendar.current.isDateInToday(item.date) {
                Button {
                    Haptics.medium()
                    onStart(game)
                } label: {
                    Text(isGolf(game) ? "Start Round" : "Start Game")
                        .font(.custom("Inter18pt-Bold", size: 13, relativeTo: .footnote))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(ppAccent))
                }
                // Borderless keeps the tap on this button instead of bubbling to
                // the row's NavigationLink — same as LiveGameCard's pills.
                .buttonStyle(.borderless)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.spacingLarge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ppCard()
    }

    private func isGolf(_ game: Game) -> Bool {
        (game.season?.sport).map { $0 == .golf } ?? isGolfProfile
    }

    /// "Today · 6:30 PM" / "Tomorrow · 6:30 PM" / "Sat, Sep 27 · 6:30 PM".
    private func whenText(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "Today · \(time)" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow · \(time)" }
        return "\(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(time)"
    }

    /// Same wording the feed card would use — one source for event titles.
    private func title(_ item: JournalUpcomingItem) -> String {
        switch item {
        case .game(let g):     return JournalEntry.game(g).fallbackHeadline
        case .practice(let p): return JournalEntry.practice(p).fallbackHeadline
        }
    }

    @ViewBuilder
    private func destination(_ item: JournalUpcomingItem) -> some View {
        switch item {
        case .game(let g):     GameDetailView(game: g)
        case .practice(let p): PracticeDetailView(practice: p)
        }
    }
}
```

- [ ] **Step 2: Keep scheduled items out of the feed.** In `JournalView.swift`, change the `buildFeed` signature and its two filters.

Replace:
```swift
    /// games/practices are excluded here: they appear only in the pinned live
    /// strip, never as a duplicate feed row — so they never inflate the pills or
    /// the content check. Computed once per body.
    private func buildFeed() -> [JournalEntry] {
```
with:
```swift
    /// games/practices are excluded here: they appear only in the pinned live
    /// strip, never as a duplicate feed row — so they never inflate the pills or
    /// the content check. Scheduled ones are excluded the same way: they live in
    /// the Up Next strip (`JournalUpcoming` is the one rule for both). `now` is
    /// shared with the strip so an item crossing its start time mid-render can't
    /// land in both or neither. Computed once per body.
    private func buildFeed(now: Date) -> [JournalEntry] {
```
Replace:
```swift
            games: games.filter { !$0.isLive },
            practices: practices.filter { !$0.isLive },
```
with:
```swift
            games: games.filter { !$0.isLive && !JournalUpcoming.isScheduled($0, now: now) },
            practices: practices.filter { !$0.isLive && !JournalUpcoming.isScheduled($0, now: now) },
```

- [ ] **Step 3: Compute `upcoming` in the body.** Replace:
```swift
        let hasLiveActivity = !liveGames.isEmpty || !livePractices.isEmpty

        let feed = buildFeed()
```
with:
```swift
        let hasLiveActivity = !liveGames.isEmpty || !livePractices.isEmpty

        let now = Date()
        let upcoming = JournalUpcoming.items(
            games: games.filter { sportMatches($0.season?.sport) },
            practices: practices.filter { sportMatches($0.season?.sport) },
            now: now
        )
        let feed = buildFeed(now: now)
```

- [ ] **Step 4: Render the strip under Live Now.** Replace:
```swift
                if hasLiveActivity {
                    liveStrip(games: liveGames, practices: livePractices)
                }
```
with:
```swift
                if hasLiveActivity {
                    liveStrip(games: liveGames, practices: livePractices)
                }

                if !upcoming.isEmpty {
                    JournalUpNextStrip(
                        items: upcoming,
                        isGolfProfile: activeSport == .golf,
                        onStart: startScheduledGame
                    )
                }
```

- [ ] **Step 5: Add the Start action.** Directly above `    // MARK: - Log-event flow`, insert:
```swift
    // MARK: - Up Next

    /// Same path as GameDetailView's Start button (`GameService.start`): it ends
    /// any other live game, stamps liveStartDate, syncs, and schedules the
    /// end-game reminder. Once `isLive` flips, the game leaves Up Next and shows
    /// up in the Live Now strip on its own.
    private func startScheduledGame(_ game: Game) {
        let service = GameService(modelContext: modelContext)
        Task { await service.start(game) }
    }

```

- [ ] **Step 6: Build.** Expected: `BUILD SUCCEEDED`. Grep: `grep -n "buildFeed()" PlayerPath/Views/Journal/JournalView.swift` returns nothing.

- [ ] **Step 7: Simulator checks.**
  - **1a:** Add 5 future games (Games tab, dates over the next weeks). Home shows "Up Next" with the **3 soonest**, soonest first, plus "See all 5", which switches to the Games tab. None of the 5 appears in the feed.
  - **1b:** Add a game today, 1 hour from now. It shows first with "Today · h:mm" and **Start Game**. Tap Start: it moves to Live Now and is gone from Up Next. End it: it appears in the feed as a finished game.
  - **1c:** Tap an Up Next row outside the Start pill: GameDetailView opens. Tapping Start does **not** open the detail screen. The filter pills below still filter.
  - **1d:** Add a game today dated 1 hour *ago*: it's in Up Next with Start. Record or import one clip into it: it moves to the feed. A game dated last week that was never marked complete stays in the feed, not in Up Next.
  - **1e:** On a golf profile the pill reads "Start Round".
  - **1f:** A game today with no season shows a chevron, not Start (matches `GamesView.startGame`'s season guard, `GamesView.swift:664-669`).

- [ ] **Step 8: Commit**
```bash
git add PlayerPath/Views/Journal/JournalUpNextStrip.swift PlayerPath/Views/Journal/JournalView.swift
git commit -m "Journal: move scheduled games into an Up Next strip, soonest first" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: No first-run screen when only live/scheduled activity exists (review issue #2)

**Files:** Modify `PlayerPath/Views/Journal/JournalView.swift`

**Interfaces:** Consumes `upcoming` and `hasLiveActivity` from Task 1. Produces the body local `hasFeed: Bool` (Task 7 uses the `if hasFeed` block).

- [ ] **Step 1: Split "has a feed" from "has anything".** Replace:
```swift
        let hasContent = !feed.isEmpty
```
with:
```swift
        // `hasFeed` drives the pills and rows; `hasContent` drives the first-run
        // screen and the nav title. A brand-new athlete who has started a game or
        // scheduled one isn't new anymore — they must not get the ghosted example
        // page (with its own "The Journal." title) under their live/Up Next card.
        let hasFeed = !feed.isEmpty
        let hasContent = hasFeed || hasLiveActivity || !upcoming.isEmpty
```

- [ ] **Step 2: Show pills only when there's a feed.** Replace:
```swift
                if hasContent {
                    PPFilterPillRow(
                        options: filters,
                        title: pillTitle,
                        selection: $filter
                    )

                    if visibleEntries.isEmpty {
```
with:
```swift
                if hasContent {
                    if hasFeed {
                    PPFilterPillRow(
                        options: filters,
                        title: pillTitle,
                        selection: $filter
                    )

                    if visibleEntries.isEmpty {
```
Then close the new `if` and add the else. Replace:
```swift
                        if hasMore {
                            ProgressView()
                                .padding(.vertical, .spacingMedium)
                        }
                    }
                } else {
```
with:
```swift
                        if hasMore {
                            ProgressView()
                                .padding(.vertical, .spacingMedium)
                        }
                    }
                    } else {
                        // Only live/scheduled activity so far — nothing finished.
                        feedPlaceholder
                    }
                } else {
```
Re-indent the block between those two edits by one level (4 spaces) so it reads cleanly.

- [ ] **Step 3: Add the placeholder.** Directly above `    /// Shown when the athlete HAS content but the active filter excluded all of`, insert:
```swift
    /// Shown under the Live Now / Up Next strips before anything has finished.
    /// Deliberately independent of `filter`: `.onChange(of: filters)` resets a
    /// stranded pill to All only AFTER the render, so reusing
    /// `filteredEmptyState` would flash e.g. "No photos yet." for one frame when
    /// the last feed item disappears under a non-All pill.
    private var feedPlaceholder: some View {
        VStack(spacing: .spacingSmall) {
            Image(systemName: "book.closed")
                .font(.system(size: 28))
                .foregroundStyle(Theme.textTertiary)
            Text("Clips, photos, and finished \(eventNoun.lowercased())s collect here.")
                .font(.ppSubheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, .spacingXLarge)
        .padding(.horizontal, 18)
        .padding(.top, 24)
    }

```

- [ ] **Step 4: Build.** Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Simulator checks.**
  - **2a:** Create a new athlete profile and start a game from the Games tab. Home shows Live Now, then the short "Clips, photos, and finished games collect here." message. There's **no** ghosted example card and **no** duplicate "The Journal." title. The large nav title is visible.
  - **2b:** Same with only a future game: Up Next plus the message.
  - **2c:** A new profile with nothing at all still shows the first-run `JournalEmptyState`.

- [ ] **Step 6: Commit**
```bash
git add PlayerPath/Views/Journal/JournalView.swift
git commit -m "Journal: skip the first-run page when a game is live or scheduled" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Highlights filter includes favorited photos (review issue #3)

**Files:** Modify `PlayerPath/Views/Journal/JournalEntry.swift`, `PlayerPath/Views/Journal/JournalView.swift`

- [ ] **Step 1:** In `JournalEntry.swift`, replace the whole `containsHighlight` property and its doc comment:
```swift
    /// True when any contained clip is starred. Cross-cuts entry type, so it's
    /// used by the feed's Highlights filter (`JournalFilter.matches`) and the
    /// row's type tag — the only media accessor the row still reads off the
    /// entry directly; counts + representatives come from `mediaSummary`.
    var containsHighlight: Bool {
        // A coach-feedback card stands in for its orphan clip (the plain clip card
        // is deduped out of the feed once feedback arrives), so it MUST still count
        // as a highlight when that clip is starred — otherwise a coach comment would
        // silently drop a starred clip out of the Highlights pill.
        if case .coachFeedback(let item) = self { return item.clip.isHighlight }
        return clips.contains { $0.isHighlight }
    }
```
with:
```swift
    /// True when any contained clip is starred or any contained photo is
    /// favorited (`Photo.isHighlight`, the star in the photo viewer). Cross-cuts
    /// entry type, so it's used by the feed's Highlights filter
    /// (`JournalFilter.matches`) and the row's type tag — the only media accessor
    /// the row still reads off the entry directly; counts + representatives come
    /// from `mediaSummary`. Clips are checked first so the common case never
    /// faults the photos relationship.
    var containsHighlight: Bool {
        // A coach-feedback card stands in for its orphan clip (the plain clip card
        // is deduped out of the feed once feedback arrives), so it MUST still count
        // as a highlight when that clip is starred — otherwise a coach comment would
        // silently drop a starred clip out of the Highlights pill.
        if case .coachFeedback(let item) = self { return item.clip.isHighlight }
        return clips.contains { $0.isHighlight } || photos.contains { $0.isHighlight }
    }
```

Perf note, accepted: for an athlete with **no** highlights, `availableFilters` scans the whole feed for `.highlights`, which now also faults each event's `photos` relationship once (after that, SwiftData keeps it loaded). Clips are still checked first, so this only matters for athletes with zero starred clips.

- [ ] **Step 2:** In `JournalView.swift`, replace `case .highlights: return "No highlights yet — star a clip to add one."` with:
```swift
        case .highlights: return "No highlights yet — star a clip or photo to add one."
```

- [ ] **Step 3: Build.** Expected: `BUILD SUCCEEDED`. The `typeTag` `.clip` branch is unaffected, since a clip entry has no photos.

- [ ] **Step 4: Simulator checks.**
  - **3a:** On a profile with no starred clips, favorite one standalone photo (open it, tap ☆). The Highlights pill appears, and selecting it shows that photo's card.
  - **3b:** Un-favorite it. The pill disappears and the feed falls back to All.

- [ ] **Step 5: Commit**
```bash
git add PlayerPath/Views/Journal/JournalEntry.swift PlayerPath/Views/Journal/JournalView.swift
git commit -m "Journal: count favorited photos as highlights" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: A single photo opens in the swipe viewer (review issue #4)

**Files:** Modify `PlayerPath/Views/Journal/JournalView.swift`

- [ ] **Step 1: State.** Under `@State private var selectedPhotoDay: JournalPhotoDay?` add:
```swift

    /// Standalone photo tapped in the feed — opens the same full-screen swipe
    /// viewer the photo grids use (`.photoViewer`), not a push.
    @State private var viewerPhoto: Photo?
    @Namespace private var photoNS
```

- [ ] **Step 2: Route the tap.** In `entryCell`, directly above `        case .coachFeedback(let item):`, insert:
```swift
        case .photo(let photo):
            // One way to view a photo app-wide: the full-screen pager, with the
            // iOS 18 zoom transition from this card.
            Button {
                Haptics.light()
                viewerPhoto = photo
            } label: {
                feedRow(entry, milestone: milestone)
                    .photoTransitionSource(photo.id, in: photoNS)
            }
            .buttonStyle(.plain)
```

- [ ] **Step 3: Present it.** Directly after the `.sheet(item: $selectedPhotoDay) { … }` modifier, add:
```swift
        .photoViewer($viewerPhoto, in: viewerPhoto.map { [$0] } ?? [], namespace: photoNS) { photo in
            PhotoPersistenceService().deletePhoto(photo, context: modelContext)
            Haptics.light()
        }
```

- [ ] **Step 4: Retire the push destination.** In `destination(for:)`, replace:
```swift
        case .photo(let p):
            PhotoDetailView(photo: p) {
                PhotoPersistenceService().deletePhoto(p, context: modelContext)
                Haptics.light()
            }
```
with:
```swift
        // Standalone photos open the full-screen viewer (see `viewerPhoto`), not a
        // push, so they never route through here.
        case .photo:           EmptyView()
```

- [ ] **Step 5: Build.** Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Simulator checks.**
  - **4a:** Tap a single-photo card. The full-screen viewer opens, covering the tab bar, with no nav back chevron. ✕ dismisses it back to the feed at the same scroll position.
  - **4b:** Delete from the viewer. It dismisses and the card disappears from the feed.
  - **4c:** A photo-group card still opens the day grid sheet.

- [ ] **Step 7: Commit**
```bash
git add PlayerPath/Views/Journal/JournalView.swift
git commit -m "Journal: open standalone photos in the full-screen viewer" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Re-tap Home to pop / scroll to top (feature #1)

**Files:** Modify `PlayerPath/AppNotifications.swift`, `PlayerPath/Views/Navigation/MainTabView.swift`, `PlayerPath/Views/Journal/JournalView.swift`

- [ ] **Step 1: Check what the system already does.** Build and run. On Home, scroll down a few screens and re-tap the Journal tab. Then open a game and re-tap the tab. Record both behaviors in the task report.
  - If **both** already work natively (pop, then scroll), **stop this task**, report it, and skip to Task 6.
  - Otherwise continue. Step 4 confirms the binding setter actually fires on re-tap before anything else relies on it.

- [ ] **Step 2: Notification name.** In `AppNotifications.swift`, directly after `    static let switchTab = Notification.Name("switchTab")`, add:
```swift
    /// Posted by MainTabView when the Home tab is re-tapped while the Journal is
    /// already at its root. JournalView scrolls its feed back to the top.
    static let journalScrollToTop = Notification.Name("journalScrollToTop")
```

- [ ] **Step 3: Detect the re-tap in `MainTabView`.** Directly above `    @ViewBuilder\n    private var tabViewContent: some View {`, insert:
```swift
    /// TabView selection that also catches a tap on the ALREADY-selected tab
    /// (the setter fires with an unchanged value). Standard iOS behavior for Home:
    /// the first re-tap pops to the Journal root, and a re-tap at the root scrolls
    /// the feed to the top. Other tabs behave as before.
    private var tabSelection: Binding<Int> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == selectedTab { handleTabReselect(newValue) }
                selectedTab = newValue
            }
        )
    }

    private func handleTabReselect(_ tab: Int) {
        guard tab == MainTab.home.rawValue else { return }
        if homePath.isEmpty {
            NotificationCenter.default.post(name: .journalScrollToTop, object: nil)
        } else {
            homePath = NavigationPath()
        }
    }

```
Then in `tabViewContent`, replace **both** occurrences of `TabView(selection: $selectedTab) {` with `TabView(selection: tabSelection) {`. Check with `grep -n 'TabView(selection:' PlayerPath/Views/Navigation/MainTabView.swift`: two lines, both `tabSelection`.

- [ ] **Step 4: Confirm the setter fires on re-tap.** Temporarily add `print("reselect", tab)` as the first line of `handleTabReselect`. Build, run, re-tap Home, and look for the print in the Xcode console (or `xcrun simctl spawn booted log stream --predicate 'process == "PlayerPath"'`).
  - If it **never prints** on re-tap (iOS 26 may not re-set an unchanged selection), **revert Steps 2–3 and stop**. Report "re-tap not observable via the TabView binding on iOS 26". Do **not** reach into `UITabBarController` delegates.
  - If it prints, remove the `print` and continue.

- [ ] **Step 5: Scroll target in `JournalView`.** Add a static next to `pageSize`:
```swift
    /// Scroll target for Home-tab re-tap (`.journalScrollToTop`).
    private static let scrollTopID = "journal-scroll-top"
```
Replace the start of the returned view:
```swift
        return ScrollView {
            LazyVStack(spacing: .spacingLarge) {
```
with:
```swift
        return ScrollViewReader { proxy in
        ScrollView {
            // Zero-height anchor ABOVE the LazyVStack (in a spacing-0 VStack), so
            // it adds no gap and is never lazily unloaded.
            VStack(spacing: 0) {
            Color.clear.frame(height: 0).id(Self.scrollTopID)
            LazyVStack(spacing: .spacingLarge) {
```
Then replace the end of the scroll content plus the first three modifiers:
```swift
            .padding(.vertical, .spacingLarge)
        }
        .background(Theme.surface)
        // Photo-led feed: the default soft edge left the clock and header
        // unreadable over dark images scrolled under the nav bar.
        .ppHardTopScrollEdge()
        .refreshable { await refreshFeed() }
```
with:
```swift
            .padding(.vertical, .spacingLarge)
            }
        }
        // Photo-led feed: the default soft edge left the clock and header
        // unreadable over dark images scrolled under the nav bar.
        .ppHardTopScrollEdge()
        .refreshable { await refreshFeed() }
        .onReceive(NotificationCenter.default.publisher(for: .journalScrollToTop)) { _ in
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo(Self.scrollTopID, anchor: .top)
            }
        }
        }
        .background(Theme.surface)
```
(`.ppHardTopScrollEdge` and `.refreshable` stay on the `ScrollView` itself. Everything from `.navigationTitle` down stays on the outer view, unchanged.)

- [ ] **Step 6: Build.** Expected: `BUILD SUCCEEDED`.

- [ ] **Step 7: Simulator checks.**
  - **5a:** Scroll the feed several screens down, then re-tap Journal. It animates to the top. The large "The Journal." title shows, or collapses no worse than before; note which.
  - **5b:** Open a game, then re-tap Journal: it pops to the feed at its old scroll position. Re-tap again: it scrolls to the top. Switch to Videos and back to Journal: the scroll position is kept (no scroll). Re-tapping Videos/Stats/More does nothing new.
  - **5c:** Pull-to-refresh still works, and the top edge still has the hard edge on iOS 26.

- [ ] **Step 8: Commit**
```bash
git add PlayerPath/AppNotifications.swift PlayerPath/Views/Navigation/MainTabView.swift PlayerPath/Views/Journal/JournalView.swift
git commit -m "Journal: re-tapping Home pops to the feed, then scrolls to top" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Watch Reel on game/practice cards (feature #2)

**Files:**
- Create: `PlayerPath/Views/Journal/JournalEventReel.swift`
- Modify: `PlayerPath/Views/Journal/JournalEntryRow.swift`, `PlayerPath/Views/Journal/JournalView.swift`

**Interfaces:**
- Produces: `struct JournalEventReel: Identifiable` (`clips: [VideoClip]`, `scopeKey: String`, `title: String`, `id == scopeKey`), and `static func make(for entry: JournalEntry, reels: [HighlightReel]) -> JournalEventReel?`. `JournalEntryRow` gains `var onWatchReel: (() -> Void)? = nil`, declared **after** `milestone`.

**Design note:** there's no separate "reel" feed entry. A round with three birdies would otherwise add three cards next to the round card it came from. The reel is an honest action on the event card itself: unlike a ▶ on a "3 CLIPS" card, it says exactly what it plays. It uses the same clip set and cache scope as the post-event banner and GameDetailView, so all three share one cached file.

- [ ] **Step 1: Create `JournalEventReel.swift`**

```swift
//
//  JournalEventReel.swift
//  PlayerPath
//
//  The reel behind a Journal game/practice card's "Watch Reel" button. Same
//  clip set, cache scope and threshold as the post-event banner (UserMainFlow)
//  and GameDetailView's Generate Reel, so every surface lands on ONE cached
//  stitched file per event instead of re-stitching.
//

import Foundation

struct JournalEventReel: Identifiable {
    let clips: [VideoClip]
    /// StitchedReelCache scope — must match the banner / GameDetailView keys.
    let scopeKey: String
    let title: String
    var id: String { scopeKey }

    /// A reel needs at least two clips — one clip is just a clip.
    static let minimumClips = 2

    /// The reel for a `.game`/`.practice` entry, or nil when it's another entry
    /// type or has fewer than two highlight clips. Golf unions starred clips
    /// with the event's birdie-reel clips; baseball has no reel rows, so passing
    /// no reels reduces the union to its starred clips. `GolfHighlightUnion`
    /// owns the filter + ordering for both, so the clip order (part of the cache
    /// hash) is deterministic.
    static func make(for entry: JournalEntry, reels: [HighlightReel]) -> JournalEventReel? {
        switch entry {
        case .game(let game):
            let isGolf = game.season?.sport == .golf
            let clips = GolfHighlightUnion.highlightClips(
                from: game.videoClips ?? [],
                gameID: game.id,
                practiceID: nil,
                reels: isGolf ? reels : []
            )
            guard clips.count >= minimumClips else { return nil }
            return JournalEventReel(
                clips: clips,
                scopeKey: isGolf ? "round_\(game.id.uuidString)" : "game_\(game.id.uuidString)",
                title: title(for: game)
            )
        case .practice(let practice):
            let isGolf = practice.season?.sport == .golf
            let clips = GolfHighlightUnion.highlightClips(
                from: practice.videoClips ?? [],
                gameID: nil,
                practiceID: practice.id,
                reels: isGolf ? reels : []
            )
            guard clips.count >= minimumClips else { return nil }
            return JournalEventReel(
                clips: clips,
                scopeKey: isGolf ? "round_practice_\(practice.id.uuidString)" : "practice_\(practice.id.uuidString)",
                title: title(for: practice)
            )
        default:
            return nil
        }
    }

    /// "Tigers · Sep 3, 2026", or just the date when there's no opponent. The
    /// title is display/caption only; it isn't part of the cache key.
    private static func title(for game: Game) -> String {
        guard let date = game.date else { return game.opponent.isEmpty ? game.eventNoun : game.opponent }
        let d = DateFormatter.mediumDate.string(from: date)
        return game.opponent.isEmpty ? d : "\(game.opponent) · \(d)"
    }

    private static func title(for practice: Practice) -> String {
        let base = practice.course ?? (PracticeType(rawValue: practice.practiceType)?.displayName ?? "Practice")
        guard let date = practice.date else { return base }
        return "\(base) · \(DateFormatter.mediumDate.string(from: date))"
    }
}
```

- [ ] **Step 2: Add the button to the row.** In `JournalEntryRow.swift`, directly after `    var milestone: Milestone? = nil`, add:
```swift

    /// Set by the feed only when this event card has a reel (2+ highlight
    /// clips). Draws the "Watch Reel" button over the media.
    var onWatchReel: (() -> Void)? = nil
```
In `body`, replace:
```swift
            media(summary)

            footer(summary)
```
with:
```swift
            media(summary)
                // bottomLeading is PPMediaTile's one free overlay slot (play /
                // outcome / star / duration take the others).
                .overlay(alignment: .bottomLeading) { reelButton }

            footer(summary)
```
Directly above `    /// True for a single-clip, play-on-tap card`, insert:
```swift
    /// "Watch Reel" over an event card's media. Unlike a ▶ on a "3 CLIPS" card,
    /// this says exactly what it plays: the event's highlight reel.
    @ViewBuilder
    private var reelButton: some View {
        if let onWatchReel {
            Button {
                Haptics.light()
                onWatchReel()
            } label: {
                Label("Watch Reel", systemImage: "play.fill")
                    .font(.custom("Inter18pt-Bold", size: 12, relativeTo: .caption))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(ppAccent))
            }
            // Borderless keeps the tap here instead of bubbling to the card's
            // NavigationLink — the pattern LiveGameCard's pills use.
            .buttonStyle(.borderless)
            .padding(.spacingSmall)
            .accessibilityLabel("Watch highlight reel")
        }
    }

```

- [ ] **Step 3: Query reels in `JournalView`.** After `    @Query private var photos: [Photo]` add:
```swift
    /// This athlete's live golf birdie reels — feeds the card "Watch Reel"
    /// union (`JournalEventReel`). Tiny: one row per birdie-or-better hole.
    @Query private var reels: [HighlightReel]
```
In `init`, after the `self._photos = Query(...)` statement, add:
```swift
        self._reels = Query(
            filter: #Predicate<HighlightReel> { $0.athleteID == id && !$0.isDeletedRemotely }
        )
```
(`athleteID` is a non-optional `UUID`, so UUID-to-UUID is safe in `#Predicate`.)

- [ ] **Step 4: State and presentation.** Under the `viewerPhoto`/`photoNS` state from Task 4, add:
```swift

    /// Reel opened from a card's "Watch Reel".
    @State private var playingReel: JournalEventReel?

    /// Observed so the Watch Reel buttons appear the moment a purchase or comp
    /// lands. `SubscriptionGate.effectiveAthleteTier` has the same value but is
    /// a plain static read that no view observes. Both objects are injected
    /// above MainTabView (`MainAppView.swift:54,76`), and JournalView's only
    /// call site is `MainTabView.swift:600`.
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @ObservedObject private var storeKit = StoreKitManager.shared

    /// Plus-only in the FEED (product decision 2026-09-25): free baseball users
    /// get highlights auto-starred, so a paywall button would sit on most game
    /// cards on Home. Free users still get the post-event banner nudge and
    /// GameDetailView's gated Generate Reel. Same max() as
    /// `SubscriptionGate.effectiveAthleteTier` (StoreKit entitlement vs comp).
    private var canWatchReels: Bool {
        max(storeKit.currentTier, authManager.currentTier).hasAutoHighlights
    }
```
After the `.photoViewer(...)` modifier from Task 4, add:
```swift
        .fullScreenCover(item: $playingReel) { reel in
            GenerateReelView(clips: reel.clips, scopeKey: reel.scopeKey, title: reel.title)
        }
```

- [ ] **Step 5: Thread it through `feedRow` and `entryCell`.** Replace the `feedRow` function:
```swift
    private func feedRow(_ entry: JournalEntry, milestone: Milestone?) -> some View {
        JournalEntryRow(entry: entry, milestone: milestone)
            .padding(.horizontal, 18)
            .contentShape(Rectangle())
    }
```
with:
```swift
    private func feedRow(_ entry: JournalEntry, milestone: Milestone?, onWatchReel: (() -> Void)? = nil) -> some View {
        JournalEntryRow(entry: entry, milestone: milestone, onWatchReel: onWatchReel)
            .padding(.horizontal, 18)
            .contentShape(Rectangle())
    }
```
In `entryCell`, replace:
```swift
        default:
            NavigationLink { destination(for: entry) } label: { feedRow(entry, milestone: milestone) }
                .buttonStyle(.plain)
```
with:
```swift
        default:
            // Resolved only for realized (on-screen) rows — LazyVStack never
            // builds off-screen cells — so the per-event clip walk stays small.
            // Free tier: no button, and no clip walk at all.
            let reel = canWatchReels ? JournalEventReel.make(for: entry, reels: reels) : nil
            NavigationLink { destination(for: entry) } label: {
                feedRow(entry, milestone: milestone, onWatchReel: reel.map { r -> () -> Void in { playingReel = r } })
            }
            .buttonStyle(.plain)
```
(No separate tier-routing function: the button only exists for Plus, so the tap just presents the reel.)

- [ ] **Step 6: Build.** Expected: `BUILD SUCCEEDED`.

- [ ] **Step 7: Simulator checks.**
  - **6a:** (Plus account, or a StoreKit sandbox Plus purchase in the sim via `PlayerPathStoreKit.storekit`.) A baseball game with 2+ starred clips shows "▶ Watch Reel" at the bottom-left of its media. A game with 0 or 1 starred clip shows no button.
  - **6b:** Star a second clip in a game: the button appears after returning to the feed. Un-star one: it disappears.
  - **6c:** Tapping the button does **not** push GameDetailView. Tapping elsewhere on the card still does.
  - **6d [device/data]:** On a free account, **no** card shows the button, even games with 2+ highlights. Buy Plus in the sandbox: the buttons appear without relaunching. As Plus, the reel generates and plays. Then open the same game and tap its Generate Reel: it loads **without** re-stitching (cache hit). Exception, accepted: a baseball game whose starred clips share an identical `createdAt` (bulk import) can re-stitch once. GameDetailView's baseball sort has no id tiebreak, so the order and cache hash can differ; GolfHighlightUnion's order is the deterministic one. For golf: a round with two birdie-hole clips (no stars) shows the button. Its reel matches the post-round banner's.

- [ ] **Step 8: Commit**
```bash
git add PlayerPath/Views/Journal/JournalEventReel.swift PlayerPath/Views/Journal/JournalEntryRow.swift PlayerPath/Views/Journal/JournalView.swift
git commit -m "Journal: Watch Reel button on game and practice cards with 2+ highlights" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: On This Day (feature #4)

**Files:**
- Create: `PlayerPath/Views/Journal/JournalAnniversary.swift` (Foundation only; **no model types**, so it compiles standalone)
- Create: `PlayerPath/Views/Journal/JournalMemoryPicker.swift`
- Modify: `PlayerPath/Views/Journal/JournalView.swift`

**Interfaces:**
- Produces: `struct JournalAnniversary: Equatable` (`yearsAgo: Int`, `dayDistance: Int`, `isExactDay`, `title`, `static let windowDays = 3`, `static func of(_:now:calendar:) -> JournalAnniversary?`, `static func dayKey(for:calendar:) -> String`). `struct JournalMemory` (`entry`, `anniversary`). `enum JournalMemoryPicker` with `static func pick(from:now:calendar:) -> JournalMemory?`.
- Consumes: the `hasFeed` block from Task 2, and `entryCell` / `milestonesByGame`.

- [ ] **Step 1: Create `JournalAnniversary.swift`**

```swift
//
//  JournalAnniversary.swift
//  PlayerPath
//
//  Pure date math for the Journal's "On This Day" card: how close a past date's
//  anniversary is to today. Foundation-only on purpose (no model types), so it
//  can be compiled and checked on its own.
//

import Foundation

struct JournalAnniversary: Equatable {
    let yearsAgo: Int
    /// Days between this year's anniversary of the date and today (0 = exact).
    let dayDistance: Int

    var isExactDay: Bool { dayDistance == 0 }

    /// "On This Day · 1 Year Ago" for an exact match, else "1 Year Ago This Week".
    var title: String {
        let years = yearsAgo == 1 ? "1 Year Ago" : "\(yearsAgo) Years Ago"
        return isExactDay ? "On This Day · \(years)" : "\(years) This Week"
    }

    /// An anniversary within ±3 days of today still counts ("this week"), so
    /// the card isn't limited to rare exact-day hits.
    static let windowDays = 3

    /// nil when `date` is today or later, is the `.distantPast` "undated"
    /// sentinel, or its nearest anniversary is outside the window. Both
    /// neighboring anniversaries are tried, so a date 2 days short of a full
    /// year still matches as "1 year ago this week". Feb 29 lands on Feb 28 in
    /// common years (`Calendar.date(byAdding:)` clamps).
    static func of(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> JournalAnniversary? {
        guard date != .distantPast else { return nil }
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        guard day < today else { return nil }
        let fullYears = calendar.dateComponents([.year], from: day, to: today).year ?? 0
        var best: JournalAnniversary?
        for years in [fullYears, fullYears + 1] where years >= 1 {
            guard let anniversary = calendar.date(byAdding: .year, value: years, to: day),
                  let signed = calendar.dateComponents([.day], from: today, to: anniversary).day
            else { continue }
            let distance = abs(signed)
            guard distance <= windowDays else { continue }
            if best.map({ distance < $0.dayDistance }) ?? true {
                best = JournalAnniversary(yearsAgo: years, dayDistance: distance)
            }
        }
        return best
    }

    /// Local-calendar day key ("2026-09-25") for "hide for today".
    static func dayKey(for now: Date = .now, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
```

- [ ] **Step 2: Check it standalone (this is the test).** Write `<scratchpad>/anniversary/main.swift`. Use the executing session's own scratchpad directory, e.g. `/private/tmp/claude-502/-Users-Trey-Desktop-PlayerPath/50a05212-9e97-4ae1-8471-d19938a63ccb/scratchpad`, and never the repo:
```swift
import Foundation

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "America/Chicago")!
func d(_ s: String) -> Date {
    let f = DateFormatter()
    f.calendar = cal; f.timeZone = cal.timeZone; f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.date(from: s)!
}
var failures = 0
func check(_ label: String, _ got: JournalAnniversary?, _ want: JournalAnniversary?) {
    let ok = got == want
    if !ok { failures += 1 }
    print(ok ? "PASS" : "FAIL", label, "got:", String(describing: got), "want:", String(describing: want))
}
let now = d("2026-09-25 10:00")
func a(_ s: String) -> JournalAnniversary? { JournalAnniversary.of(d(s), now: now, calendar: cal) }

check("exact, 1y, later hour",       a("2025-09-25 19:00"), .init(yearsAgo: 1, dayDistance: 0))
check("exact, 3y",                   a("2023-09-25 08:00"), .init(yearsAgo: 3, dayDistance: 0))
check("anniv in 2 days (<1 full yr)", a("2025-09-27 12:00"), .init(yearsAgo: 1, dayDistance: 2))
check("anniv 3 days ago",            a("2025-09-22 12:00"), .init(yearsAgo: 1, dayDistance: 3))
check("4 days out -> nil",           a("2025-09-21 12:00"), nil)
check("4 days ahead -> nil",         a("2025-09-29 12:00"), nil)
check("today -> nil",                a("2026-09-25 07:00"), nil)
check("earlier this year -> nil",    a("2026-03-01 07:00"), nil)
check("future -> nil",               a("2027-09-25 07:00"), nil)
check("undated sentinel -> nil",     JournalAnniversary.of(.distantPast, now: now, calendar: cal), nil)
check("Feb 29 -> Feb 28",            JournalAnniversary.of(d("2024-02-29 12:00"), now: d("2027-02-28 09:00"), calendar: cal),
                                     .init(yearsAgo: 3, dayDistance: 0))
let key = JournalAnniversary.dayKey(for: now, calendar: cal)
if key != "2026-09-25" { failures += 1 }
print(key == "2026-09-25" ? "PASS" : "FAIL", "dayKey", key)
print(JournalAnniversary(yearsAgo: 1, dayDistance: 0).title, "|", JournalAnniversary(yearsAgo: 2, dayDistance: 2).title)
exit(failures == 0 ? 0 : 1)
```
Run:
```bash
cd <scratchpad>/anniversary && swiftc -o check main.swift /Users/Trey/Desktop/PlayerPath/PlayerPath/Views/Journal/JournalAnniversary.swift && ./check; echo "exit $?"
```
Expected: every line `PASS`, titles `On This Day · 1 Year Ago | 2 Years Ago This Week`, and `exit 0`. If the Feb 29 case fails, fix `of` (not the test). The contract is "clamped anniversary counts as exact".

- [ ] **Step 3: Create `JournalMemoryPicker.swift`**

```swift
//
//  JournalMemoryPicker.swift
//  PlayerPath
//
//  Chooses the one past Journal entry worth resurfacing today ("On This Day").
//

import Foundation

struct JournalMemory {
    let entry: JournalEntry
    let anniversary: JournalAnniversary
}

enum JournalMemoryPicker {
    /// The best entry whose anniversary is within the window, or nil.
    ///
    /// Candidates come from the built feed (already sport-scoped, with no live
    /// or scheduled rows). Coach-feedback cards are skipped: their date is when
    /// the feedback arrived, not a moment from the athlete's past. Ranking:
    /// exact day, then nearer day, then contains a highlight, then more media,
    /// then the most recent year. Ties keep feed order (newest first), which is
    /// deterministic. The media walk runs only for date-matched candidates, a
    /// handful at most.
    static func pick(from feed: [JournalEntry], now: Date = .now, calendar: Calendar = .current) -> JournalMemory? {
        var best: (memory: JournalMemory, rank: (Int, Int, Int, Int, Int))?
        for entry in feed {
            if case .coachFeedback = entry { continue }
            guard let anniversary = JournalAnniversary.of(entry.date, now: now, calendar: calendar) else { continue }
            let summary = entry.mediaSummary
            let rank = (
                anniversary.isExactDay ? 1 : 0,
                -anniversary.dayDistance,
                entry.containsHighlight ? 1 : 0,
                summary.clipCount + summary.photoCount,
                -anniversary.yearsAgo
            )
            if let current = best, !(current.rank < rank) { continue }
            best = (JournalMemory(entry: entry, anniversary: anniversary), rank)
        }
        return best?.memory
    }
}
```

- [ ] **Step 4: Memoize and hide in `JournalView`.** Directly after the `@State private var milestoneCache = MilestoneCache()` line, add:
```swift

    /// Memo for the On This Day pick. Same pattern as MilestoneCache: the pick
    /// does calendar math per feed entry, so it runs only when the feed's
    /// dates/count or the day change, not on every body pass. (Starring a
    /// clip doesn't re-rank until the feed changes; the rendered card itself is
    /// always live.)
    private final class MemoryCache {
        var token: Int?
        var memory: JournalMemory?
    }
    @State private var memoryCache = MemoryCache()

    /// "athleteUUID|2026-09-25" of the last On This Day card hidden. One slot,
    /// shared by all profiles: hiding on profile B re-shows A's card today, at
    /// worst.
    @AppStorage("journal.onThisDay.hidden") private var hiddenMemoryKey = ""

    private var todayMemoryKey: String {
        "\(athleteID.uuidString)|\(JournalAnniversary.dayKey())"
    }

    private func onThisDayMemory(from feed: [JournalEntry]) -> JournalMemory? {
        var hasher = Hasher()
        hasher.combine(JournalAnniversary.dayKey())
        // Dates + count only, no `entry.id`: building ids allocates a
        // uuidString per entry (and a Calendar call per photo group) on every
        // body pass. Swapping one entry for another with the exact same
        // timestamp is the only change this misses, and it can't happen in
        // practice.
        hasher.combine(feed.count)
        for entry in feed {
            hasher.combine(entry.date)
        }
        let token = hasher.finalize()
        if memoryCache.token == token { return memoryCache.memory }
        let memory = JournalMemoryPicker.pick(from: feed)
        memoryCache.token = token
        memoryCache.memory = memory
        return memory
    }
```

- [ ] **Step 5: Compute it in the body.** Directly after `let milestonesByGame = milestoneIndex()`, add:
```swift
        // All pill only: it's a memory, not a filter result. Hidden for the rest
        // of today once dismissed.
        let memory = (hasFeed && filter == .all && hiddenMemoryKey != todayMemoryKey)
            ? onThisDayMemory(from: feed)
            : nil
```

- [ ] **Step 6: Render it above the first section, below the pills.** (Below the pills, so it disappearing on a pill change doesn't make the pills jump.) Task 2 re-indented this block by 4 spaces, so match these lines by content, not by exact indentation. Replace:
```swift
                    } else {
                        ForEach(sections) { section in
```
with:
```swift
                    } else {
                        if let memory {
                            onThisDayCard(memory, milestonesByGame: milestonesByGame)
                        }
                        ForEach(sections) { section in
```
Directly above `    /// A lightweight date-section header`, insert:
```swift
    /// The On This Day card: an accent header ("On This Day · 1 Year Ago") with
    /// a hide-for-today ✕, over the entry's normal feed card, which taps through
    /// exactly like it does in the feed.
    private func onThisDayCard(_ memory: JournalMemory, milestonesByGame: [UUID: Milestone]) -> some View {
        VStack(alignment: .leading, spacing: .spacingSmall) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ppAccent)
                Text(memory.anniversary.title).smallCapsLabel(color: ppAccent)
                Spacer()
                Button {
                    Haptics.light()
                    withAnimation(.easeOut(duration: 0.2)) { hiddenMemoryKey = todayMemoryKey }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide for today")
            }
            .padding(.horizontal, 18)

            entryCell(memory.entry, milestone: memory.entry.gameID.flatMap { milestonesByGame[$0] })
        }
    }

```

- [ ] **Step 7: Build.** Expected: `BUILD SUCCEEDED`. Re-run the Step 2 `swiftc` check: still `exit 0`.

- [ ] **Step 8: Simulator checks.**
  - **7a:** Add a game dated exactly one year ago today, with one clip or photo. Home shows "On This Day · 1 Year Ago" above the first section, with that game's card. Tapping the card opens the game.
  - **7b:** Change that game's date to 2 days later than a year ago: the header reads "1 Year Ago This Week". Change it to 5 days away: the card disappears.
  - **7c:** Select the Games pill: the card disappears and the pills don't move. Back to All: it's back.
  - **7d:** Tap ✕: the card hides (tapping ✕ does **not** open the game). Switch tabs and come back, and kill and relaunch the app: it stays hidden. Then run `xcrun simctl spawn booted defaults delete RZR.DT3 journal.onThisDay.hidden` and relaunch: it's back. (That's the same as the key no longer matching tomorrow's date.)
  - **7e:** With no matching entries, no card appears and there's no empty gap above the first section header.

- [ ] **Step 9: Commit**
```bash
git add PlayerPath/Views/Journal/JournalAnniversary.swift PlayerPath/Views/Journal/JournalMemoryPicker.swift PlayerPath/Views/Journal/JournalView.swift
git commit -m "Journal: On This Day card resurfaces a moment from past years" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Cleanup (review issue #5)

**Files:** Modify `PlayerPath/Views/Journal/JournalView.swift`, `PlayerPath/Views/Journal/JournalFeedBuilder.swift`

The fixed 150ms wait in `startLogEventFlow` is **left as-is on purpose**. The same fire-once pattern is shared with `QuickActionsManager`, `UserMainFlow` (250ms) and `DashboardView`. Making it robust means a pending-request flag in `GamesView` covering all four callers, which is a separate change. Mention it in the task report.

- [ ] **Step 1: Replace the stale header** in `JournalView.swift`:
```swift
//  Visual overhaul — the Journal landing tab.
//  A calm, reverse-chronological feed of the athlete's games, practices, and
//  standalone clips. A compact "Live Now" strip pins to the top when an
//  activity is live: tapping a card opens its detail screen, and the card's own
//  pills run the activity in place (Score Hole / Record / End) via the shared
//  `LiveActivityController`. Filter pills scope the feed: All / Games / Golf /
//  Highlights.
//
//  This is a NEW screen; DashboardView is preserved and reachable elsewhere.
//
```
with:
```swift
//  The athlete Home tab. A calm, reverse-chronological record of what happened:
//  games, practices, standalone clips/photos, and coach feedback, scoped to the
//  profile's pinned sport. Above it: pending coach invitations, a "Live Now"
//  strip (cards run Score Hole / Record / End in place via the shared
//  `LiveActivityController`) and an "Up Next" strip for scheduled events
//  (`JournalUpNextStrip`). Content-type pills (All / Games-or-Rounds /
//  Practices / Photos / Highlights / Feedback) appear only when they match
//  something. On the All pill an "On This Day" card can lead the feed.
//
//  Replaced DashboardView as the athlete home; DashboardView is retired.
//
```

- [ ] **Step 2: Drop the dead `filter:` parameter.** In `JournalFeedBuilder.swift`, replace:
```swift
        coachFeedback: [CoachFeedbackFeedItem] = [],
        filter: JournalFilter
    ) -> [JournalEntry] {
```
with:
```swift
        coachFeedback: [CoachFeedbackFeedItem] = []
    ) -> [JournalEntry] {
```
and replace:
```swift
        return entries
            .filter { filter.matches($0) }
            .sorted { $0.date == $1.date ? $0.id > $1.id : $0.date > $1.date }
```
with:
```swift
        // Pill filtering happens in JournalView on the built feed (the pills,
        // the empty checks and On This Day all need the unfiltered list).
        return entries
            .sorted { $0.date == $1.date ? $0.id > $1.id : $0.date > $1.date }
```
In `JournalView.buildFeed`, replace:
```swift
            coachFeedback: feedbackItems,
            filter: .all
        )
```
with:
```swift
            coachFeedback: feedbackItems
        )
```

- [ ] **Step 3: Build.** Expected: `BUILD SUCCEEDED`. Grep: `grep -n "filter: .all\|Golf /" PlayerPath/Views/Journal/*.swift` returns nothing.

- [ ] **Step 4: Commit**
```bash
git add PlayerPath/Views/Journal/JournalView.swift PlayerPath/Views/Journal/JournalFeedBuilder.swift
git commit -m "Journal: refresh header docs, drop unused feed-builder filter parameter" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

## After all tasks

- Run the `playerpath-reviewer` agent over `git diff ee2a987..HEAD -- PlayerPath/`. Nothing here touches sync, schema or Firestore, so `/sync-field-check` isn't needed.
- Update the `project_journal_design_and_perf` memory. Record: Up Next plus the `JournalUpcoming` rule (the feed excludes exactly what the strip includes), the Watch Reel button (shares cache scopes with the banner and GameDetailView), On This Day (memoized; hidden for the day via `@AppStorage`), the re-tap behavior, and which checks are device-test pending. Mark backlog items "Scroll-to-top" and "On This Day" done.
