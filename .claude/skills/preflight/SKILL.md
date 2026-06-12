---
name: preflight
description: Ship-state dashboard for PlayerPath — checks git status, iOS build, functions tsc, deploy drift, build number, and the device-test backlog in one pass.
disable-model-invocation: true
---

# Preflight — ship-state dashboard

Produce a single dashboard answering: what's uncommitted, do both builds pass, what's changed but not deployed, is the build number bumped, and what still needs device testing.

Run the independent checks in parallel where possible. Long builds should run in the background while you gather the cheap facts.

## Checks

### 1. Git state (always read fresh — never trust memory labels)
Trey commits and pushes outside Claude Code, so any "UNCOMMITTED" note in memory may be stale. Run:
```bash
git status --porcelain
git log --oneline -8
git log -1 --format=%cd --date=relative
```
Summarize uncommitted changes **grouped by feature area** (e.g. "golf scoring", "coach invitations", "firebase backend") rather than listing raw paths. Note whether anything is committed but not pushed (`git status -sb` ahead count).

### 2. iOS build
```bash
DEVELOPER_DIR=/Applications/Xcode.app xcodebuild -project PlayerPath.xcodeproj -scheme PlayerPath -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -20
```
Run this in the background (it takes minutes). Report GREEN, or the first compile errors.

### 3. Cloud Functions typecheck
```bash
cd firebase/functions && npx tsc --noEmit
```
Report GREEN or errors.

### 4. Deploy drift (Firebase)
There is no reliable remote diff, so detect *local change recency* instead:
```bash
git log -3 --oneline -- firestore.rules
git log -3 --oneline -- firebase/functions/
git status --porcelain firestore.rules firebase/functions/
```
If `firestore.rules` or `firebase/functions/` have uncommitted changes OR commits newer than the last known deploy, flag them as **"changed locally — verify deployed"**. Cross-check memory files in `~/.claude/projects/-Users-Trey-Desktop-PlayerPath/memory/` for "NOT deployed" / "DEPLOYED" notes, but treat them as hints, not truth.

### 5. Version / build number
Read fresh — never use a remembered number (App Store requires monotonic increase):
```bash
grep -m2 "CURRENT_PROJECT_VERSION\|MARKETING_VERSION" PlayerPath.xcodeproj/project.pbxproj
```
Report both. If there is substantial uncommitted/unarchived work, remind that the build number has not been bumped since the last archive. Note: CLAUDE.md mentions `./increment_build_number.sh` but that script does not exist at repo root — bump `CURRENT_PROJECT_VERSION` in the pbxproj (all occurrences) if asked.

### 6. Device-test backlog
```bash
grep -l "NEEDS device test\|over-the-top" ~/.claude/projects/-Users-Trey-Desktop-PlayerPath/memory/*.md
```
List the features still flagged as needing on-device testing (one line each, from the memory file descriptions). Caveat each with its date — older entries may already be tested.

## Output format

One compact dashboard, then details only for anything red/yellow:

```
## Preflight — <date>

| Check            | Status |
|------------------|--------|
| Git              | N files uncommitted (areas: …) / clean; ahead by N |
| iOS build        | ✅ GREEN / ❌ errors |
| Functions tsc    | ✅ GREEN / ❌ errors |
| Deploy drift     | ⚠️ rules+functions changed locally / ✅ nothing pending |
| Version          | 6.0.3 (183) — bump needed? |
| Device tests     | N features pending |
```

End with a short "suggested next actions" list (commit grouping, deploy command, bump) — suggestions only, do not execute them.
