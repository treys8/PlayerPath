# Firestore rules tests

Tests `firestore.rules` against the Firestore emulator. Currently covers
`recruitingProfiles` (the collection behind the public recruiting page).

## Prerequisite: Java

The Firestore emulator is a Java program. Homebrew on this machine lacks write
permission to `/opt/homebrew`, so `brew install openjdk` fails without `sudo` —
install a JDK into your home directory instead. **No sudo required:**

```bash
curl -sL -o /tmp/jdk.tar.gz \
  "https://api.adoptium.net/v3/binary/latest/21/ga/mac/aarch64/jdk/hotspot/normal/eclipse"
mkdir -p ~/.local/jdk && tar xzf /tmp/jdk.tar.gz -C ~/.local/jdk
```

Then export it for the shell that runs the tests (add to `~/.zshrc` to persist):

```bash
export JAVA_HOME="$(echo ~/.local/jdk/*/Contents/Home)"
export PATH="$JAVA_HOME/bin:$PATH"
```

Verify with `java -version` before running the tests. Installed 2026-07-25:
Temurin 21.0.11 at `~/.local/jdk/jdk-21.0.11+10/`.

## Run

```bash
cd firebase/rules-tests
npm install
npm test
```

Note the `test` script resolves `node` to an absolute path *before* invoking
`firebase emulators:exec`. That's load-bearing: `emulators:exec` prepends its own
bundled runtime (`~/.cache/firebase/runtime/node`) to `PATH`, and that binary is a
`pkg`-packaged build that treats `--test` as a module path and dies with
`Cannot find module '--test'`.

`emulators:exec` boots Firestore on port 8080 (per the `emulators` block in
`firebase.json`), runs the suite, and shuts the emulator down. Nothing touches a
real project — the tests use the throwaway project id
`playerpath-rules-test` and load `../../firestore.rules` directly, so they always
test the rules as committed.

## What's covered

`recruitingProfiles.test.mjs` — 31 cases across create / read / update / delete, plus the recruitingTokens claim.

**The bug this suite caught on its first real run (2026-07-25):** the read rule was
`resource.data.userId == request.auth.uid` with no null guard. On a *missing* doc
`resource` is null, so `resource.data` raises a Null value error and the rule
denies. `publish()` reads the profile doc before creating it (to reuse an existing
`shareToken`) and deliberately doesn't swallow that failure — so **every first
publish failed for every user**, while all 29 original cases passed, because each
one seeded a doc first. Fixed with `resource == null ||`; the regression case is
"allows the owner to read a profile that does NOT exist yet". Don't delete it.

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
