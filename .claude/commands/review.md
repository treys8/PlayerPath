---
description: PlayerPath code review — runs the project footgun reviewer over the diff, then a general correctness pass, and merges both into one severity-ordered list.
argument-hint: "[branch | PR# | path — defaults to the uncommitted diff]"
allowed-tools: Read, Grep, Glob, Bash, Agent, Skill
---

Review PlayerPath changes with **both** layers. Neither alone is sufficient: the generic reviewer doesn't know this repo's crash history, and the project reviewer doesn't do general correctness well.

## 1. Resolve the target

`$ARGUMENTS` may be a branch, a PR number, a path, or empty.

- **Empty** → the uncommitted diff: `git diff HEAD` plus untracked Swift/TS files (`git status --porcelain`). If that is empty, fall back to the last commit (`git diff HEAD~1`) and say which you reviewed.
- **Branch** → `git diff main...<branch>`
- **PR number** → `gh pr diff <n>`
- **Path** → `git diff HEAD -- <path>`, or review the file whole if it is untracked

State the resolved target and the file count before reviewing. If the diff is empty, stop and say so — do not invent a target.

## 2. Project footgun pass

Dispatch the **`playerpath-reviewer`** agent (`.claude/agents/playerpath-reviewer.md`) with the resolved diff. Give it the actual diff text, not just a description of it, plus the paths it may need to read for context.

That agent is the single source of truth for this repo's footguns — SwiftData `#Predicate` traps, model-access-after-`await`, schema-bump call sites, the 9-site sync parity checklist, `HTTPSCallable`, coach limit enforcement, MainActor-by-default. Do not restate its rules here; they drift.

Run this pass **even when the diff looks unrelated to SwiftData or Firebase** — the sync-parity and schema-bump classes are exactly the ones that look unrelated right up until they lose data.

## 3. General correctness pass

Invoke the **`code-review`** skill on the same resolved target, at the effort level in `$ARGUMENTS` if one is given, otherwise `medium`.

## 4. Merge

Produce **one** list, not two reports:

- Dedupe where both passes found the same defect. Keep the project-reviewer's wording — it cites the incident that makes the severity real.
- Order by severity. A confirmed footgun outranks a generic finding of nominally equal severity, because these have each already shipped a bug here.
- Tag each finding `[footgun]` or `[general]` so the source is visible.
- Drop anything on the reviewer's do-not-flag list (`[weak self]` in SwiftUI structs, `import Combine`, deliberate `.orange` chart colors). If a pass raises one of these, discard it silently — do not report it as considered-and-dismissed.

Report findings only: `file:line`, why it is a real problem, the minimal fix. No praise, no summary of correct code.

## Notes

- For a fast generic-only pass, use `/code-review` directly — this command is the thorough one.
- `/audit` is a different tool: repo-wide code quality against a tracked baseline, not a diff review.
- The `swift-footgun-check.sh` hook already catches a narrow subset on every edit. Overlap is expected and fine.
