# Stream B — HighlightReel Cross-Device Edits (S1) + Orphan Cleanup (S2)

_Plan grounded in full reads of every touched file and every `VideoClip.delete(in:)` call site. **No schema change** — methods/params aren't part of the SwiftData schema, and S1 deliberately reconciles on `version` alone so no new stored property is needed._

## The bugs

**S1** — `syncHighlightReels` (SyncCoordinator+HighlightReels.swift) is **insert-only**: the download loop skips any remote reel whose `firestoreId` already exists locally (`if existingFirestoreIds.contains(remoteId) { continue }`, line 91). Only *create* and *soft-delete* cross devices. A reel whose `clipIDs`/`score`/`displayName` were corrected on Device A (each edit does `version += 1; needsSync = true` in `ScoreHoleSheet.upsertReelIfNeeded`) never updates Device B. Unlike `reconcileHoles`, there is no version/`updatedAt` comparison.

**S2** — `VideoClip.delete(in:)` (Models/VideoClip.swift:198) cleans up the file, thumbnail, cloud object, Firestore metadata, and `PlayResult`, but never touches `HighlightReel.clipIDs` (denormalized `[String]` of clip UUIDs, no SwiftData relationship). Delete every clip on a birdie hole → an empty reel card the user **cannot remove** (Highlights filters non-deleted reels, but an empty reel is still non-deleted). Only cleaned today if the user happens to re-save that hole's score (which re-runs `upsertReelIfNeeded` and demotes the now-clipless reel).

---

## S1 — clean-row reconcile in `syncHighlightReels`

Mirror `reconcileHoles` (SyncCoordinator+HoleScores.swift:143-201)'s *shape* — clean-guard → newer-wins → field copy — but resolve the tie via **"a clean local row mirrors the server"** instead of `updatedAt`.

**Why clean-absorb, not version-only and not version + `updatedAt`:** `reconcileHoles` tiebreaks equal versions on `updatedAt` because `HoleScore` *stores* one. The local `HighlightReel` model (Models/HighlightReel.swift:49-54) has **no `updatedAt` stored property** — only `firestoreId / needsSync / version / isDeletedRemotely / lastSyncDate`. Every VersionedSchema in this repo returns the *live* class list (`SchemaV1.models`), so adding a stored `updatedAt` would be a real schema change (new `SchemaV27` + container bump + TestFlight migration on heavy accounts; PlayerPathSchema.swift header: "ANY change to a @Model class requires a new schema version"). Not worth it.

A strict `remote.version > local.version` would avoid the schema bump but leaves a real divergence gap: two devices that edit the *same reel offline* can reach equal version numbers with different content, and strict `>` never resolves it. The key insight closes that gap for free: **the `!local.needsSync` guard already guarantees the local row has pushed everything it holds, so a clean local row can never be newer than the server.** We can therefore absorb the remote whenever the local row is clean — converging the equal-version case that strict `>` leaves broken, with no `updatedAt` and no schema change. The `>=` check is belt-and-suspenders; the content-diff guard avoids reassigning identical values every sync pass (which would churn SwiftData observation → needless HighlightsView re-renders).

**Edit — SyncCoordinator+HighlightReels.swift, replace the `existingFirestoreIds` guard (lines 88-91) with a lookup + reconcile branch:**

```swift
// Build a firestoreId → local reel map for both the exists-check and the
// S1 reconcile branch below.
let localByFirestoreId = Dictionary(
    athleteReels.compactMap { reel in reel.firestoreId.map { ($0, reel) } },
    uniquingKeysWith: { first, _ in first }
)
for remote in remoteReels {
    guard let remoteId = remote.id else { continue }

    if let local = localByFirestoreId[remoteId] {
        // S1: absorb remote field edits onto an existing local reel. A clean
        // local row (!needsSync) has already pushed everything it holds, so it
        // can never be newer than the server — taking the remote is always
        // correct and converges the equal-version case strict `>` would leave
        // diverged. HighlightReel stores no `updatedAt`, so this replaces the
        // reconcileHoles version/updatedAt tiebreak. The fetch already excludes
        // remote-soft-deleted reels, so every `remote` here is alive —
        // tombstones are handled below. Content-diff before assigning to avoid
        // churning SwiftData observation on no-op sync passes.
        guard !local.needsSync else { continue }
        guard (remote.version ?? 0) >= local.version else { continue }
        let differs = local.clipIDs != remote.clipIDs
            || local.score != remote.score
            || local.par != remote.par
            || local.displayName != remote.displayName
            || local.courseOrOpponent != remote.courseOrOpponent
        if differs {
            local.clipIDs = remote.clipIDs
            local.score = remote.score
            local.par = remote.par
            local.displayName = remote.displayName
            local.courseOrOpponent = remote.courseOrOpponent
            local.date = remote.date
            local.version = remote.version ?? 0
            local.lastSyncDate = Date()
        }
        continue
    }

    // ... existing insert-new-local-reel path unchanged ...
}
```

The insert path (lines 92-116) is untouched; the tombstone-reconciliation block below it (lines 118-133) is untouched. Net change is the addition of the `if let local` reconcile branch.

---

## S2 — strip deleted clip from referencing reels in `VideoClip.delete`

Add a private helper plus a **`cleanupReels: Bool = true`** parameter to `VideoClip.delete(in:)`. The helper does a flat `FetchDescriptor<HighlightReel>` fetch + in-memory `clipIDs.contains` filter — matching `ScoreHoleSheet.upsertReelIfNeeded`'s lookup idiom (line 329) — because reels carry no SwiftData relationship to clips and SwiftData `#Predicate` can't equate optional UUIDs.

**Behavior:** for each reel referencing this clip's id → remove the id, `version += 1`, `needsSync = true`; if `clipIDs` is then empty → `isDeletedRemotely = true` (soft-delete, same as `ScoreHoleSheet`'s demotion at lines 377-381). No `save()` — every user-delete caller saves immediately after `delete(in:)` (verified: VideoClipsView.swift:372/423, HighlightsView.swift:454/513, PracticeDetailView.swift:293).

**Edit 1 — Models/VideoClip.swift, signature (line 198):**
```swift
@MainActor func delete(in context: ModelContext, cleanupReels: Bool = true) {
```

**Edit 2 — Models/VideoClip.swift, add the cleanup call just before the PlayResult deletion (before line 281 `if let playResult = playResult`):**
```swift
// v6.1 S2: drop this clip from any HighlightReel that references it, and
// soft-delete a reel left with no clips so it stops rendering an empty,
// user-undeletable card. Skipped on cascade/sync deletes (cleanupReels ==
// false) that already manage reels wholesale — see those call sites.
if cleanupReels {
    removeFromReferencingReels(in: context)
}
```

**Edit 3 — Models/VideoClip.swift, new private method (after `delete`, before the closing brace):**
```swift
/// Removes this clip's id from every HighlightReel that references it and
/// soft-deletes any reel left empty. Reels store clip ids as a denormalized
/// `[String]` with no SwiftData relationship, so we fetch flat and filter in
/// memory — the same idiom as ScoreHoleSheet.upsertReelIfNeeded. Each touched
/// reel is re-dirtied (version bump + needsSync) so the edit propagates; the
/// caller's save() persists it.
@MainActor
private func removeFromReferencingReels(in context: ModelContext) {
    let clipIDString = id.uuidString
    let referencing: [HighlightReel]
    do {
        let all = try context.fetch(FetchDescriptor<HighlightReel>())
        referencing = all.filter { $0.clipIDs.contains(clipIDString) }
    } catch {
        modelsLog.error("Failed to fetch HighlightReels for clip-delete cleanup: \(error.localizedDescription)")
        return
    }
    for reel in referencing {
        reel.clipIDs.removeAll { $0 == clipIDString }
        reel.version += 1
        reel.needsSync = true
        if reel.clipIDs.isEmpty {
            reel.isDeletedRemotely = true
        }
    }
}
```
(`modelsLog` is already used throughout `VideoClip.delete` — lines 210/222/228/262.)

### Why the `cleanupReels` parameter is required (not just an optimization)

Every `clip.delete(in:)` call site was audited. The **default (`true`)** covers all five user-initiated paths with **no edit** needed. Seven cascade/sync sites must opt **out**:

| Call site | Pass | Reason |
|---|---|---|
| VideoClipsView.swift:372, :423 | default `true` | user single/bulk delete — want cleanup |
| HighlightsView.swift:454, :513 | default `true` | user delete — want cleanup |
| PracticeDetailView.swift:293 | default `true` | user delete — want cleanup |
| **GameService.swift:54** (`deleteGameDeep`) | **`false`** | reels for the game are hard-deleted + Firestore-soft-deleted explicitly at lines 33-43/118-133 |
| **Athlete.swift:150, :162, :173** (`delete`) | **`false`** | athlete's reels hard-deleted at lines 138-145 before the clip loops |
| **Models.swift:375** (`Practice.delete`) | **`false`** | practice's reels hard-deleted at lines 396-405 |
| **SyncCoordinator+Games.swift:149** (remote game tombstone) | **`false`** | **correctness:** the other device already deleted the game+reels; running cleanup here re-dirties local reels → resurrect/churn against the inbound tombstone |
| **SyncCoordinator+Videos.swift:198** (remote clip tombstone) | **`false`** | **correctness:** the originating device's clip-delete already stripped+synced the reel; running it again here double-bumps version + needsSync → sync ping-pong |

The two sync paths are the load-bearing reason for the flag — without it, S2 introduces a cross-device write race. The cascade paths are correctness-neutral (their reels are deleted in the same transaction, so a flat fetch would return nothing anyway) but passing `false` avoids N wasted reel-table fetches per cascade. `SyncCoordinator+Practices.swift:144` calls `localPractice.delete(in:)`, which routes through the `Practice.delete` → `cleanupReels: false` clip calls, so it's covered transitively.

**7 call-site edits** (append `, cleanupReels: false`) + the 3 edits in VideoClip.swift.

---

## Full edit list

1. `SyncCoordinator+HighlightReels.swift` — replace lines 88-91 with the lookup + reconcile branch (S1).
2. `Models/VideoClip.swift` — `delete` signature gains `cleanupReels: Bool = true`; add the guarded cleanup call; add `removeFromReferencingReels(in:)` (S2).
3. `GameService.swift:54` — `clip.delete(in: modelContext, cleanupReels: false)`.
4. `Models/Athlete.swift:150, :162, :173` — `clip.delete(in: context, cleanupReels: false)` (×3).
5. `Models.swift:375` — `videoClip.delete(in: context, cleanupReels: false)`.
6. `SyncCoordinator+Games.swift:149` — `clip.delete(in: context, cleanupReels: false)`.
7. `SyncCoordinator+Videos.swift:198` — `localClip.delete(in: context, cleanupReels: false)`.

No new files. No schema bump. Stream A's totalScore files are untouched.

## Out of scope (other streams)
- C1 export, A2 rescan-strips-highlights → Stream C.
- Adding a stored `updatedAt` to `HighlightReel` → deliberately avoided (schema cost > tiebreak value).

## Accepted minor costs
- Bulk user-delete of N clips does N flat `HighlightReel` fetches (reel table is tiny; correctness > a per-batch API). Mirrors the per-clip granularity of the existing `delete(in:)` contract.
- A never-synced (`firestoreId == nil`) reel emptied by S2 is soft-deleted (`isDeletedRemotely = true`) and will be *created* in Firestore already-tombstoned on next sync — one wasted write, identical to how `ScoreHoleSheet` demotion already behaves for never-synced reels. Not worth special-casing.

## Verification
1. `xcodebuild ... -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` → grep for `BUILD SUCCEEDED`, no `error:`.
2. S1: edit a synced reel's score/clip set on Device A → Device B's pull updates the existing reel (no duplicate, no stale card).
3. S2: birdie hole with ≥2 clips → reel shows 2; delete one clip → reel shows 1; delete the last → reel disappears (soft-deleted), card is gone and stays gone after sync.
4. Regression: delete a whole golf game (`deleteGameDeep`) → no reel churn / no resurrected reels; remote game/clip tombstones don't double-process reels.
</content>
</invoke>
