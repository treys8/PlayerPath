# Kill Switches — Runbook

Switch a feature OFF for every user, in seconds, with no App Store build.
Code: `PlayerPath/Services/KillSwitchService.swift` + `KillSwitchPolicy.swift`.

## The switches

| Key | What stops | What users see |
|---|---|---|
| `bulkVideoImport` | Importing videos from Photos (all 5 entry points) | "Import Paused" alert on tap |
| `bulkPhotoImport` | Importing photos from Photos | "Import Paused" alert on tap |
| `reelGeneration` | Rendering NEW highlight reels (already-rendered reels still play and share) | "Couldn't Build Reel" + paused message |
| `engagementNudges` | Weekly summary, weekend prep, inactivity, clip-tagging and milestone local notifications; pending ones are cleared | Nothing (they just stop) |

Not switchable, on purpose: recruiting (see `RecruitingFeature.swift`), uploads,
game reminders, coach review reminders.

## Flip one

Firebase console → Firestore → `appConfig` → `killSwitches` (create the doc if
missing) → add a **map** field named after the key:

```
bulkVideoImport  (map)
  off          (boolean) true
  upToVersion  (string)  "6.4.5"        ← optional: only builds ≤ this; the fix build is unaffected
  message      (string)  "…"            ← optional: ≤200 chars, shown instead of the default copy
```

- `off` as the string `"true"` also works. A bare `bulkVideoImport: true` (not a map) is **ignored**.
- A mistyped `upToVersion` kills **every** version (safe direction).
- To lift: set `off` to `false`, or delete the field.
- `upToVersion` is the marketing version only (not the build number). A fix shipped as a new build of the same version is still covered, so lift it by hand.

## What it can't do

- It reaches a device only when the app next opens or comes to the foreground.
- `engagementNudges` can't pull back notifications already scheduled on a device whose owner never opens the app. The inactivity nudge in particular can keep firing for up to about a week on idle devices.
- Everyone can read this doc once signed in. Never put UIDs or internal notes in it.

## How fast it lands

When the app is next foregrounded or signed into. A user already inside the app
picks it up on the next background → foreground. Offline users keep their last
fetched state.

## Test without touching prod

Xcode → Edit Scheme → Run → Arguments → `-KillSwitchForce bulkVideoImport,reelGeneration`
(DEBUG builds only).
