# Visual Overhaul — COMPLETE (all 12 commits)

Branch `visual-overhaul` (do NOT touch `main`). All 12 commits done, each built green. HEAD = `f6d35a4`.

| # | Commit | Hash |
|---|---|---|
| 1 | Token layer (cream/terracotta `Theme`, small-caps helper, app-wide light lock) | `500e0be` |
| 2 | Core components A (`PPCard`, `PPSectionHeader`, `PPFilterPill`) | `d63619d` |
| 3 | Core components B (media tile, date tile, outcome chip, milestone marker, profile pill) | `f801e53` |
| 4 | Journal landing screen (Home→Journal) | `008ac6c` |
| 5 | Games reskin (cream scorebook) | `dfde381` |
| 6 | Clips reskin (cream grid) | `927153f` |
| 7 | Stats "The Numbers." + RBI/runs removed from UI | `395bdad` |
| 8 | Player detail (parent, read-only) — cream editorial chrome | `448da46` |
| 9 | Player detail (coach authoring) — cue/send/receipt | `372aac4` |
| 10 | Milestone engine (pure, read-only) | `7d29b95` |
| 11 | Headline rule + derivable-stat allowlist | `fb3b461` |
| 12 | Wire milestones + auto-headlines into UI | `f6d35a4` |

## Decisions made during 8–12
- **Commit 8 bottom bar:** athlete side has no "Add to drill" action, so it uses Highlight · Save · Share.
- **Commit 9 mic:** omitted (note stays text-only; keyboard already has system dictation). Audio voice notes would need a new Storage path + Firestore field — a separate backend change.
- **Commit 9 net-new UI:** built the inline cue picker (writes `video.tags`); drill authoring stays in the existing restyled `DrillCardView` sheet.
- **No new Firestore fields** anywhere in 8–12. Send-to-athlete = `markReviewed`; view receipt reads `video.viewedBy`; cues = `updateVideoTags` + `QuickCue`.

## Still to do (manual, not code)
On-device eyeball pass per the plan's §6: player chrome in portrait+landscape, coach cue/send/receipt, Journal headlines/markers, Stats milestones list. No automated tests exist.

---

## Original prompt (commits 8–12) — for reference

---

## PROMPT (copy everything below)

I'm continuing a visual overhaul on the `visual-overhaul` branch (already checked out; do NOT touch `main`). Seven commits are done and building green — token layer, core PP components, and reskins of Journal, Games, Clips, and Stats. HEAD is `395bdad`. The full approved plan is at `~/.claude/plans/starry-sprouting-quail.md` — read it first.

Work the remaining commits **one at a time, in order**, and after EACH: build with
`xcodebuild -project PlayerPath.xcodeproj -scheme PlayerPath -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
then commit only if it succeeds. Use small, labeled commits ending with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

Remaining commits:
- **8 — Player detail (parent, read-only):** restyle `VideoPlayerView.swift` chrome only (don't touch playback/cloud state): `tileNavyDark` surround, accent scrubber, outcome chip + duration overlays, existing `DrawingAnnotationOverlay` for telestration; below the player add milestone marker + serif outcome headline + context subline + coach review card (avatar, name, "Reviewed Nd ago", note, read-only drill stars) + quick-cue chips + bottom bar (Highlight · Add to drill · Share).
- **9 — Player detail (coach authoring):** restyle `CoachVideoPlayerView.swift`: floating `TelestrationToolbar`, editable note + mic, tappable drill ratings, cue picker (accent fill selected / dashed unselected / "+ add"), full-width accent "Send to [Athlete]" + "they'll be notified · you'll see when viewed", view-receipt on this coach side. **STOP and ask if anything seems to need a new Firestore field** — backend is shared with live users; reuse existing coach session/comment services.
- **10 — Milestone engine:** new `Services/MilestoneEngine.swift` + `Models/Milestone.swift` (plain struct, NOT @Model). Pure, read-only compute over Games/Practices/PlayResults/HoleScores. Baseball: first HR of season, season-high hits in a game, hit streak, Nth double/HR, personal bests (via `PlayResultAccumulator`). Golf: first eagle (`HoleScore.diff <= -2`), personal-low round (`Game.effectiveTotalScore`). **Never read `runs`/`rbis`.** Zero Firestore/schema changes.
- **11 — Headline rule + stats allowlist:** new `Services/HeadlineBuilder.swift` — priority milestone > standout-day line ("3-for-4 vs Opponent") > matchup fallback. **Baseball: never invent a team score** (no such field). Golf may use the round score. Add a documented derivable-stat allowlist (AVG/OBP/SLG/OPS/AB/H/1B/2B/3B/HR/BB/K/Games) so RBI/runs can never re-enter a grid.
- **12 — Wire logic into UI:** surface milestones/headlines in the Journal feed (`JournalEntry.fallbackHeadline` → headline rule), the Stats milestones list, and the clip-level star marker. Reuse `PPMilestoneMarker`.

Key conventions already established: new palette is the `Theme` enum (`PlayerPath/Theme/Theme.swift`); `.smallCapsLabel()`, `.ppCard()`, `PPMediaTile`, `PPOutcomeChip`, `PPDateTile`, `PPMilestoneMarker`, `PPFilterPillRow`, `PPProfilePill` already exist under `PlayerPath/Views/Components/PP/`. Fonts are Fraunces/Inter/Archivo via `Font+PlayerPath.swift` (`.ppTitle2`, `.ppStat(_:)`, etc.). The app is light-locked at the root. **Note:** SourceKit "new-diagnostics" reporting "Cannot find 'Theme'/type X in scope" are index-lag false positives — trust the `xcodebuild` result, not those.
