---
name: sync-field-check
description: Verify a VideoClip/Firestore field is wired through ALL sync sites (writers, parsers, merge, dirty-check). Run after adding or modifying any synced field — missed sites cause silent data loss (the holeNumber bug).
---

# Sync field parity check

A field on a synced model must appear at **every** site below or it silently breaks: missed writers mean edits never upload (the `holeNumber` retag bug), missed parsers mean downloads silently drop the field, a missed dirty-check means changes never mark the clip for re-sync.

Input: a field name (e.g. `holeNumber`). If invoked without an argument, check every field added/changed in the current `git diff` touching `Models/VideoClip.swift`, `FirestoreModels.swift`, or the files below.

## VideoClip checklist — grep each site for the field

| # | Site | File / function |
|---|------|-----------------|
| 1 | Upload writer (initial) | `VideoCloudManager+Metadata.swift` → `saveVideoMetadataToFirestore` |
| 2 | Upload writer (pending/athlete) | `VideoCloudManager+Metadata.swift` → `createPendingAthleteVideoMetadata` |
| 3 | **Update writer** (retag path) | `VideoCloudManager+Metadata.swift` → `updateVideoMetadata` — both the function signature AND the `data[...]` write |
| 4 | Update caller | `SyncCoordinator+Videos.swift` → the `updateVideoMetadata(...)` call site must pass the field |
| 5 | Download parser | `VideoCloudManager.swift` → `struct VideoClipMetadata` property + `init?(from data:)` |
| 6 | Merge into existing clip | `SyncCoordinator+Videos.swift` → remote→local merge block (where `localClip.X = remoteVideo.X`) |
| 7 | New-clip creation from remote | `SyncCoordinator+Videos.swift` → `newClip.X = remoteVideo.X` block |
| 8 | **Dirty-check** | `SyncCoordinator+Videos.swift` → `videoMetadataMatches` — field must be compared or local edits never re-upload |
| 9 | Firestore model (if coach-shared) | `FirestoreModels.swift` → `FirestoreVideoMetadata` (and remember it has its own encode + decode) |

Note from past incidents: the round-trip has **two parsers** (the `VideoClipMetadata` init and the FirestoreVideoMetadata path) — a field present in one and not the other "works" in testing and fails in the other direction.

## Other synced entities

For Athlete/Season/Game/Practice/Note/Photo fields, the analogous sites live in `FirestoreManager+EntitySync.swift` (writer + parser pairs) plus the SyncCoordinator merge/dirty paths. Apply the same writer/parser/merge/dirty-check audit.

## Output

A table: site → ✅ present / ❌ MISSING (with file:line for each ✅ so they're clickable). If anything is missing, say exactly what write/read/compare line to add — but do not edit unless asked.
