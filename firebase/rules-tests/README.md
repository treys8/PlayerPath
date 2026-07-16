# Firestore rules tests

Tests `firestore.rules` against the Firestore emulator. Currently covers
`recruitingProfiles` (the collection behind the public recruiting page).

## Prerequisite: Java

The Firestore emulator is a Java program. **This machine has no JRE**, so the
tests cannot run until one is installed:

```bash
# Homebrew on this machine currently lacks write permission, so fix that first:
sudo chown -R $(whoami) /opt/homebrew
brew install openjdk
sudo ln -sfn /opt/homebrew/opt/openjdk/libexec/openjdk.jdk \
             /Library/Java/JavaVirtualMachines/openjdk.jdk
```

Verify with `java -version` before running the tests.

## Run

```bash
cd firebase/rules-tests
npm install
npm test
```

`emulators:exec` boots Firestore on port 8080 (per the `emulators` block in
`firebase.json`), runs the suite, and shuts the emulator down. Nothing touches a
real project — the tests use the throwaway project id
`playerpath-rules-test` and load `../../firestore.rules` directly, so they always
test the rules as committed.

## What's covered

`recruitingProfiles.test.mjs` — 29 cases across create / read / update / delete, plus the recruitingTokens claim.

The two that matter most, because they look like one rule and are two:

- **A non-Pro account CANNOT publish** (or re-publish).
- **A non-Pro account CAN unpublish.** The kill switch is never paywalled — if a
  family's subscription lapses, they must still be able to take their kid's
  public page down. Inverting this is invisible in the app until it's a real
  problem for a real family.

Then the path-forgery cases: `headshotPath` must live under the caller's own
`recruiting_headshots/{uid}/` prefix. `serveRecruitingProfile` signs that path
with the Admin SDK, which **bypasses `storage.rules`**, so an unconstrained path
would let a user publish someone else's private object and read back a signed URL
for it. (The paths inside `highlights[]` can't be checked in rules — rules can't
iterate a list — so the CF's `ownedPath()` is the real defense there. These cases
cover the one path a rule can see.)

Also covered: no anonymous reads (the page is served by the CF via the Admin SDK,
never by a client read), `shareToken`/`userId` immutability, doc id pinned to
`athleteId`, the 8-highlight cap, and owner-only access.

## Adding coverage

The high-risk rules that still have no tests are `invitations/` and
`sharedFolders/` (see `docs/` for their invariants). Same pattern: seed with
`testEnv.withSecurityRulesDisabled`, then assert with
`assertSucceeds`/`assertFails` from an `authenticatedContext`.
