# Promo Video Pipeline — Design

**Date:** 2026-08-05
**Status:** Approved (brainstorming session)
**Approach:** Remotion-based render pipeline over real simulator screen captures

## Purpose

Produce three marketing videos for PlayerPath from one set of real screen recordings:

1. **App Store preview** — plays on the App Store listing
2. **Social promo** — Instagram/TikTok/X clip
3. **Web hero loop** — landing-page background/demo loop

Claude Design (claude.ai/design) is explicitly **not** the animation tool — it is a static
design-system reference. It informs the motion work (palette, type, easing) but all video is
produced by this pipeline.

## Deliverables

| Deliverable | Resolution | Length | Notes |
|---|---|---|---|
| App Store preview | 886×1920 portrait, 30fps, H.264 | 15–30s (target ~25s) | Footage-first per Apple rules. Light text overlays allowed; no device frames, no hands. |
| Social cut | 1080×1920 (9:16) | ~25–35s | Hook text in first 2s, baked captions, **no baked music** (user adds trending audio in-platform). |
| Web hero loop | 1920×1080 (16:9), mp4 + webm | ~10–15s seamless loop | No text — the landing page headline does that job. |

**Sport emphasis (decided):** baseball-led. Baseball/softball flows dominate; golf gets one
quick beat. A single App Store preview (not one-per-sport).

## Prerequisite: demo data

The footage is only as good as what's on screen. Before any capture, seed a demo athlete
profile with:

- Realistic name, photo, and season with several games (varied opponents/results)
- Real video clips (actual swings/pitches, not placeholders) tagged with play results
- Coach feedback on at least one clip, including telestration drawings and a note
- A generated highlight reel
- One golf round with a filled scorecard (for the golf beat)

This is the largest practical lift in the project and happens first.

## Capture workflow

All captures come from the iOS Simulator at native device resolution:

```bash
# Clean status bar before recording
xcrun simctl status_bar booted override --time "9:41" \
  --batteryLevel 100 --batteryState charged --cellularBars 4 --wifiBars 3

# Record a clip
xcrun simctl io booted recordVideo --codec h264 <shot-name>.mov
```

Each shot gets a scripted checklist entry: which screen, what to tap, target duration.
Raw captures land in `marketing/remotion/footage/`, which is **git-ignored** (multi-MB
binaries don't belong in the repo). A committed `footage/README.md` lists the expected
shot files so a future re-capture knows exactly what to record.

## Shot lists

### App Store preview (~25s, baseball-led)

| # | Time | Shot | Overlay text (draft) |
|---|---|---|---|
| 1 | 0–3s | Journal home feed scroll | "Every game. Every clip. One place." |
| 2 | 3–9s | Record a swing → tag the play result | "Record and tag every play" |
| 3 | 9–15s | Coach telestration drawing on a clip | "Real feedback from your coach" |
| 4 | 15–20s | Highlight reel playing | "Auto highlight reels" |
| 5 | 20–23s | Golf scorecard quick beat | "Plays golf too? Covered." |
| 6 | 23–25s | PlayerPath end card (logo, cream/terracotta) | — |

### Social cut

Same footage, re-ordered to lead with the telestration shot (most thumb-stopping/unusual),
then tagging, reel, journal, golf beat, end card. Baked captions throughout.

### Web hero loop

2–3 clean segments (journal scroll, clip playback, scorecard) cross-fading in a seamless
loop. No text overlays.

## Project structure

```
marketing/remotion/          # committed to the repo, excluded from the Xcode target
├── package.json             # plain Node project; Remotion
├── src/
│   ├── tokens.ts            # mirrors Theme.swift colors + motion easing/durations
│   ├── scenes/              # shared scene components (footage frame, caption, end card)
│   └── compositions/        # AppStorePreview.tsx, SocialCut.tsx, WebHeroLoop.tsx
└── footage/                 # raw .mov captures (git-ignored; README.md committed)
```

- **Committed to the repo** — the design-system generator was previously lost in a session
  scratchpad; this pipeline must be re-runnable when the app UI changes.
- `tokens.ts` values are hand-mirrored from `Theme.swift` / `Font+PlayerPath.swift`
  (canonical palette — never `DesignTokens.swift`'s deprecated navy/gold).
- Title cards use the bundled Fraunces/Inter font files from the app repo.

## Workflow

1. Seed demo data → capture shots per checklist
2. `npx remotion studio` — live browser preview for review/iteration
3. `npx remotion render` — produce the three finals
4. Verify App Store preview against Apple's checklist before upload: duration 15–30s,
   886×1920, H.264, footage-primary, no device frames/hands/rejected content

## Error handling & testing

- No automated tests — the review loop is visual (Remotion Studio preview, then rendered
  output review by Trey before any upload).
- Render failures surface directly from the Remotion CLI; nothing is uploaded automatically.
  App Store Connect upload is manual and done by Trey.

## Out of scope

- Music licensing / audio tracks (social audio added in-platform; App Store preview ships
  silent or with royalty-free audio chosen later)
- Localized previews and ASO copywriting
- A golf-led second App Store preview (possible later using Apple's multi-preview slots —
  the pipeline structure supports adding a composition)
