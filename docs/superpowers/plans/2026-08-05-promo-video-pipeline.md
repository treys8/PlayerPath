# Promo Video Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Status: SHELVED FOR FUTURE USE (2026-08-05).** Approved but deliberately deferred — execute when there is a distribution moment (App Store push, recruiting-feature announcement, ads). Spec: `docs/superpowers/specs/2026-08-05-promo-video-pipeline-design.md`.

**Goal:** A committed, re-runnable Remotion project at `marketing/remotion/` that renders three marketing videos (App Store preview, social cut, web hero loop) from real simulator screen captures, styled with PlayerPath's actual design tokens.

**Architecture:** Plain Node/React project, fully outside the Xcode target (no pbxproj changes). Footage files are git-ignored; everything else — code, tokens, fonts, capture runbook — is committed so the pipeline survives and re-renders after app UI changes. Scenes render a labeled placeholder when a footage file is missing, so the entire pipeline is buildable and verifiable before any capture session happens.

**Tech Stack:** Remotion 4 (`remotion`, `@remotion/cli`, `@remotion/fonts`), React 18, TypeScript. Verification via `npx remotion still` (visual stills Claude can Read) and macOS `mdls` (resolution/duration checks on rendered files).

## Global Constraints

- **Node 20** (`nvm use 20` — same version used for CF deploys).
- **Palette comes ONLY from `src/tokens.ts`**, which mirrors `PlayerPath/Theme/Theme.swift`. NEVER use `DesignTokens.swift`'s deprecated `brandNavy`/`brandGold`/gradients.
- **App Store preview spec:** 886×1920 portrait, 30fps, H.264, 15–30s total (this plan: exactly 25s). Text overlays allowed; no device frames, no hands.
- **No external URLs** in any composition — fonts and footage load via `staticFile()` from `public/`.
- **`marketing/remotion/public/footage/*.mov` is git-ignored**; its `README.md` (capture runbook) is committed. `node_modules/` and `out/` are git-ignored.
- All shell commands below run from `/Users/Trey/Desktop/PlayerPath` unless a `cd` is shown.
- There are no automated tests in this repo; each task's verify steps (stills + `mdls`) are the test cycle. Commit only after the verify step passes.

---

### Task 1: Scaffold the Remotion project

**Files:**
- Create: `marketing/remotion/package.json`
- Create: `marketing/remotion/tsconfig.json`
- Create: `marketing/remotion/remotion.config.ts`
- Create: `marketing/remotion/.gitignore`
- Create: `marketing/remotion/src/index.ts`
- Create: `marketing/remotion/src/Root.tsx`
- Modify: `docs/superpowers/specs/2026-08-05-promo-video-pipeline-design.md` (footage path: `footage/` → `public/footage/`, required by Remotion's `staticFile()`)

**Interfaces:**
- Consumes: nothing (first task).
- Produces: a working Remotion CLI (`npx remotion compositions` resolves `src/index.ts` via config); `Root.tsx` exports `Root: React.FC`, where later tasks register `<Composition>` entries.

- [ ] **Step 1: Write the project files**

`marketing/remotion/package.json`:

```json
{
  "name": "playerpath-promo-video",
  "private": true,
  "scripts": {
    "studio": "remotion studio",
    "render:appstore": "remotion render AppStorePreview out/appstore-preview.mp4",
    "render:social": "remotion render SocialCut out/social-cut.mp4",
    "render:web": "remotion render WebHeroLoop out/web-hero.mp4",
    "render:web:webm": "remotion render WebHeroLoop out/web-hero.webm --codec=vp9"
  },
  "dependencies": {
    "@remotion/cli": "^4.0.0",
    "@remotion/fonts": "^4.0.0",
    "react": "^18.3.1",
    "react-dom": "^18.3.1",
    "remotion": "^4.0.0"
  },
  "devDependencies": {
    "@types/react": "^18.3.3",
    "typescript": "^5.5.0"
  }
}
```

`marketing/remotion/tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "jsx": "react-jsx",
    "strict": true,
    "skipLibCheck": true,
    "noEmit": true
  },
  "include": ["src", "remotion.config.ts"]
}
```

`marketing/remotion/remotion.config.ts`:

```ts
import {Config} from '@remotion/cli/config';

Config.setEntryPoint('./src/index.ts');
Config.setVideoImageFormat('jpeg');
Config.setOverwriteOutput(true);
```

`marketing/remotion/.gitignore`:

```gitignore
node_modules/
out/
public/footage/*.mov
```

`marketing/remotion/src/index.ts`:

```ts
import {registerRoot} from 'remotion';
import {Root} from './Root';

registerRoot(Root);
```

`marketing/remotion/src/Root.tsx` (placeholder composition so the CLI has something to list; replaced in later tasks):

```tsx
import {AbsoluteFill, Composition} from 'remotion';

const Placeholder: React.FC = () => (
  <AbsoluteFill style={{backgroundColor: '#F4EFE6'}} />
);

export const Root: React.FC = () => (
  <Composition
    id="Placeholder"
    component={Placeholder}
    width={886}
    height={1920}
    fps={30}
    durationInFrames={30}
  />
);
```

- [ ] **Step 2: Update the spec's footage path**

In `docs/superpowers/specs/2026-08-05-promo-video-pipeline-design.md`, replace both occurrences of `marketing/remotion/footage/` with `marketing/remotion/public/footage/` (Remotion can only serve assets under `public/` via `staticFile()`), and in the project-structure tree move `footage/` under a `public/` entry.

- [ ] **Step 3: Install and verify the CLI works**

```bash
cd marketing/remotion && npm install && npx remotion compositions
```

Expected: dependency install succeeds; output lists a composition table containing `Placeholder  30fps  886x1920  30 (1.00 sec)`.

- [ ] **Step 4: Verify the Xcode project is untouched**

```bash
git status --porcelain PlayerPath.xcodeproj
```

Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add marketing/remotion docs/superpowers/specs/2026-08-05-promo-video-pipeline-design.md
git commit -m "marketing: scaffold Remotion promo-video project"
```

Note: `package-lock.json` should be included in the `git add` (it lands under `marketing/remotion/`).

---

### Task 2: Capture runbook (demo data + shot list)

**Files:**
- Create: `marketing/remotion/public/footage/README.md`

**Interfaces:**
- Consumes: nothing (documentation task; can run in parallel with Tasks 3–7).
- Produces: the shot IDs and filenames (`journal-scroll.mov`, `record-tag.mov`, `coach-telestration.mov`, `highlight-reel.mov`, `golf-scorecard.mov`) that Task 4's manifest and Task 8's integration reference. These names are load-bearing — do not change them in one place only.

- [ ] **Step 1: Write the runbook**

`marketing/remotion/public/footage/README.md`:

```markdown
# Footage Capture Runbook

Raw `.mov` captures live here (git-ignored). This README is the committed
record of what to capture and how, so a future re-capture session needs no
archaeology.

## Prerequisite: demo data (do this FIRST — it is the biggest lift)

Seed a demo athlete profile in the app before recording anything:

- [ ] Athlete with a realistic name + profile photo
- [ ] A season with several games (varied opponents and results)
- [ ] Real video clips imported (actual swings/pitches — use Bulk Video
      Import; the simulator has no camera, so clips must be imported files)
- [ ] Play results tagged on those clips
- [ ] Coach feedback on at least one clip: telestration drawing + a note
      (requires a demo coach account connected to the athlete)
- [ ] A generated highlight reel
- [ ] One golf round with a filled scorecard (second linked athlete profile)

## Simulator capture

Boot the iPhone 17 Pro simulator with the app built and demo data seeded, then:

    # Clean status bar (run once per boot)
    xcrun simctl status_bar booted override --time "9:41" \
      --batteryLevel 100 --batteryState charged --cellularBars 4 --wifiBars 3

    # Record one shot (Ctrl-C to stop)
    xcrun simctl io booted recordVideo --codec h264 <shot-name>.mov

Record 5–10s per shot — trimming happens in Remotion, so err long. Slow,
deliberate scrolls and taps read better at final size than quick ones.

## Shot list

| File name                 | Screen / flow                                   | Action to perform                                              | Min length |
|---------------------------|--------------------------------------------------|----------------------------------------------------------------|-----------|
| `journal-scroll.mov`      | Home tab (Journal feed)                          | Slow scroll through a feed with games, clips, coach feedback   | 6s        |
| `record-tag.mov`          | Camera → play-result tagging                     | See device note below — capture on a PHYSICAL device           | 8s        |
| `coach-telestration.mov`  | Coach video player (coach account)               | Draw a telestration line/circle on a paused clip               | 8s        |
| `highlight-reel.mov`      | Highlights tab                                   | Play a stitched highlight reel (let it run)                    | 7s        |
| `golf-scorecard.mov`      | Golf game scorecard                              | Scroll the filled scorecard, tap into one hole                 | 6s        |

## Device note for `record-tag.mov`

The simulator has NO camera, so the record-a-swing flow must be screen-recorded
on a physical iPhone: Settings → Control Center → add Screen Recording, record
the flow (point the camera at anything swing-like, then tag the play result),
AirDrop the file to the Mac, rename it `record-tag.mov`, drop it here. The
device status bar will show real time/battery — acceptable; `FootageScene`
crops with `objectFit: cover`, and Apple does not require 9:41 in previews.

## After capture

Drop all five files in this directory, then follow Task 8 of
`docs/superpowers/plans/2026-08-05-promo-video-pipeline.md` to wire them in
and render finals.
```

- [ ] **Step 2: Verify git sees the README but will ignore future .mov files**

```bash
git check-ignore -v marketing/remotion/public/footage/test.mov; git status --porcelain marketing/remotion/public/footage/
```

Expected: `check-ignore` prints the `.gitignore` rule match for `test.mov`; `status` shows the README as untracked (only).

- [ ] **Step 3: Commit**

```bash
git add marketing/remotion/public/footage/README.md
git commit -m "marketing: footage capture runbook (demo data + shot list)"
```

---

### Task 3: Brand tokens and fonts

**Files:**
- Create: `marketing/remotion/src/tokens.ts`
- Create: `marketing/remotion/src/fonts.ts`
- Create: `marketing/remotion/public/fonts/` (5 copied .ttf files)
- Create: `marketing/remotion/src/compositions/BrandSample.tsx`
- Modify: `marketing/remotion/src/Root.tsx` (register BrandSample, drop Placeholder)

**Interfaces:**
- Consumes: `Root.tsx` from Task 1.
- Produces: `colors` (keys: `surface`, `card`, `textPrimary`, `textSecondary`, `textTertiary`, `divider`, `accent`, `accentLight`, `golfAccent`, `golfAccentLight`, `warning`, `tileNavyDark` — all `string` hex), `springs` (keys `selection`, `celebrate` — Remotion `SpringConfig` objects), and `loadBrandFonts(): Promise<void[]>` which registers font families `'Fraunces'` (600/700), `'Inter'` (500/600), `'Archivo Condensed'` (900). Later tasks import from `'../tokens'` and call families by these exact names.

- [ ] **Step 1: Copy the font files**

```bash
mkdir -p marketing/remotion/public/fonts
cp "PlayerPath/Fonts/Archivo,Fraunces,Inter/Fraunces/static/Fraunces_72pt-Bold.ttf" \
   "PlayerPath/Fonts/Archivo,Fraunces,Inter/Fraunces/static/Fraunces_72pt-SemiBold.ttf" \
   "PlayerPath/Fonts/Archivo,Fraunces,Inter/Inter/static/Inter_18pt-SemiBold.ttf" \
   "PlayerPath/Fonts/Archivo,Fraunces,Inter/Inter/static/Inter_18pt-Medium.ttf" \
   "PlayerPath/Fonts/Archivo,Fraunces,Inter/Archivo/static/Archivo_Condensed-Black.ttf" \
   marketing/remotion/public/fonts/
```

- [ ] **Step 2: Write tokens.ts**

```ts
// Mirrors PlayerPath/Theme/Theme.swift — the canonical palette.
// NEVER add values from DesignTokens.swift (brandNavy/brandGold are deprecated).

export const colors = {
  surface: '#F4EFE6',       // app background (cream)
  card: '#FFFFFF',
  textPrimary: '#1F1B16',
  textSecondary: '#8A7F6F',
  textTertiary: '#A89D8B',
  divider: '#E3DACB',
  accent: '#C8693E',        // terracotta — baseball/softball + neutral base
  accentLight: '#F0997B',   // accent on dark surfaces
  golfAccent: '#357A57',    // fairway green
  golfAccentLight: '#84CBA6',
  warning: '#C0852E',
  tileNavyDark: '#20303F',  // video player surface
} as const;

// SwiftUI springs from DesignTokens.swift converted for Remotion's spring():
// response R, dampingFraction d, mass 1 → stiffness = (2π/R)², damping = d·2·√stiffness
export const springs = {
  selection: {mass: 1, stiffness: 322, damping: 29}, // .spring(response: 0.35, dampingFraction: 0.8)
  celebrate: {mass: 1, stiffness: 195, damping: 17}, // .spring(response: 0.45, dampingFraction: 0.6)
} as const;
```

- [ ] **Step 3: Write fonts.ts**

```ts
import {loadFont} from '@remotion/fonts';
import {staticFile} from 'remotion';

// Families/weights match the app's usage in Font+PlayerPath.swift:
// Fraunces = display/titles, Inter = body/captions, Archivo Condensed = stat numerals.
export const loadBrandFonts = () =>
  Promise.all([
    loadFont({family: 'Fraunces', url: staticFile('fonts/Fraunces_72pt-Bold.ttf'), weight: '700'}),
    loadFont({family: 'Fraunces', url: staticFile('fonts/Fraunces_72pt-SemiBold.ttf'), weight: '600'}),
    loadFont({family: 'Inter', url: staticFile('fonts/Inter_18pt-SemiBold.ttf'), weight: '600'}),
    loadFont({family: 'Inter', url: staticFile('fonts/Inter_18pt-Medium.ttf'), weight: '500'}),
    loadFont({family: 'Archivo Condensed', url: staticFile('fonts/Archivo_Condensed-Black.ttf'), weight: '900'}),
  ]);
```

- [ ] **Step 4: Write the BrandSample composition** (kept permanently as the visual regression card for tokens)

`marketing/remotion/src/compositions/BrandSample.tsx`:

```tsx
import {AbsoluteFill} from 'remotion';
import {colors} from '../tokens';

const Swatch: React.FC<{name: string; value: string}> = ({name, value}) => (
  <div style={{display: 'flex', alignItems: 'center', gap: 16}}>
    <div style={{width: 64, height: 64, borderRadius: 12, backgroundColor: value, border: `1px solid ${colors.divider}`}} />
    <div style={{fontFamily: 'Inter', fontWeight: 500, fontSize: 24, color: colors.textPrimary}}>
      {name} <span style={{color: colors.textTertiary}}>{value}</span>
    </div>
  </div>
);

export const BrandSample: React.FC = () => (
  <AbsoluteFill style={{backgroundColor: colors.surface, padding: 60, gap: 20}}>
    <div style={{fontFamily: 'Fraunces', fontWeight: 700, fontSize: 64, color: colors.textPrimary}}>
      PlayerPath
    </div>
    <div style={{fontFamily: 'Inter', fontWeight: 600, fontSize: 32, color: colors.textSecondary}}>
      Inter SemiBold caption style
    </div>
    <div style={{fontFamily: 'Archivo Condensed', fontWeight: 900, fontSize: 56, color: colors.accent}}>
      0123456789
    </div>
    {Object.entries(colors).map(([name, value]) => (
      <Swatch key={name} name={name} value={value} />
    ))}
  </AbsoluteFill>
);
```

- [ ] **Step 5: Register it in Root.tsx** (full replacement — Placeholder is gone)

```tsx
import {Composition} from 'remotion';
import {loadBrandFonts} from './fonts';
import {BrandSample} from './compositions/BrandSample';

loadBrandFonts();

export const Root: React.FC = () => (
  <Composition
    id="BrandSample"
    component={BrandSample}
    width={1080}
    height={1400}
    fps={30}
    durationInFrames={30}
  />
);
```

- [ ] **Step 6: Render a still and inspect it**

```bash
cd marketing/remotion && npx remotion still BrandSample out/brand-sample.png
```

Then Read `marketing/remotion/out/brand-sample.png` and verify: cream background, serif "PlayerPath" headline (Fraunces, not a fallback serif), condensed numerals, 12 swatches matching their printed hex labels. Font fallback (generic serif/sans) = `loadBrandFonts` failed — fix before committing.

- [ ] **Step 7: Commit**

```bash
git add marketing/remotion/src marketing/remotion/public/fonts
git commit -m "marketing: brand tokens, fonts, BrandSample regression card"
```

---

### Task 4: Shot manifest and scene components

**Files:**
- Create: `marketing/remotion/src/shots.ts`
- Create: `marketing/remotion/src/scenes/FootageScene.tsx`
- Create: `marketing/remotion/src/scenes/CaptionOverlay.tsx`
- Create: `marketing/remotion/src/scenes/EndCard.tsx`

**Interfaces:**
- Consumes: `colors`, `springs` from `src/tokens.ts` (Task 3).
- Produces:
  - `type Shot = {id: string; file: string | null; seconds: number; caption: string | null}`
  - `APP_STORE_SHOTS: Shot[]` and `SOCIAL_SHOTS: Shot[]` (same shots, social order)
  - `FootageScene: React.FC<{file: string | null; shotId: string}>`
  - `CaptionOverlay: React.FC<{text: string}>`
  - `EndCard: React.FC` (2s = 60 frames assumed by compositions)

- [ ] **Step 1: Write shots.ts** (file names MUST match Task 2's runbook table)

```ts
export type Shot = {
  id: string;
  file: string | null; // filename under public/footage/; null until captured (Task 8 fills these in)
  seconds: number;
  caption: string | null;
};

// Baseball-led App Store order (spec: golf gets one quick beat). 23s + 2s end card = 25s.
export const APP_STORE_SHOTS: Shot[] = [
  {id: 'journal-scroll', file: null, seconds: 3, caption: 'Every game. Every clip. One place.'},
  {id: 'record-tag', file: null, seconds: 6, caption: 'Record and tag every play'},
  {id: 'coach-telestration', file: null, seconds: 6, caption: 'Real feedback from your coach'},
  {id: 'highlight-reel', file: null, seconds: 5, caption: 'Auto highlight reels'},
  {id: 'golf-scorecard', file: null, seconds: 3, caption: 'Plays golf too? Covered.'},
];

// Social leads with the thumb-stopping telestration shot (spec decision).
export const SOCIAL_SHOTS: Shot[] = [
  APP_STORE_SHOTS[2], // coach-telestration
  APP_STORE_SHOTS[1], // record-tag
  APP_STORE_SHOTS[3], // highlight-reel
  APP_STORE_SHOTS[0], // journal-scroll
  APP_STORE_SHOTS[4], // golf-scorecard
];
```

- [ ] **Step 2: Write FootageScene.tsx**

```tsx
import {AbsoluteFill, OffthreadVideo, staticFile} from 'remotion';
import {colors} from '../tokens';

// Renders a labeled placeholder until the shot's footage file exists,
// so every composition is buildable before any capture session.
export const FootageScene: React.FC<{file: string | null; shotId: string}> = ({file, shotId}) => (
  <AbsoluteFill style={{backgroundColor: colors.tileNavyDark, justifyContent: 'center', alignItems: 'center'}}>
    {file ? (
      <OffthreadVideo
        src={staticFile(`footage/${file}`)}
        muted
        style={{width: '100%', height: '100%', objectFit: 'cover'}}
      />
    ) : (
      <div style={{fontFamily: 'Inter', fontWeight: 500, fontSize: 48, color: colors.textTertiary}}>
        [{shotId}]
      </div>
    )}
  </AbsoluteFill>
);
```

- [ ] **Step 3: Write CaptionOverlay.tsx**

```tsx
import {AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {colors, springs} from '../tokens';

// Caption card springs up from the bottom using the app's "selection" spring.
export const CaptionOverlay: React.FC<{text: string}> = ({text}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const progress = spring({frame, fps, config: springs.selection});
  return (
    <AbsoluteFill style={{justifyContent: 'flex-end', alignItems: 'center', paddingBottom: 120}}>
      <div
        style={{
          transform: `translateY(${interpolate(progress, [0, 1], [40, 0])}px)`,
          opacity: progress,
          backgroundColor: colors.surface,
          color: colors.textPrimary,
          fontFamily: 'Inter',
          fontWeight: 600,
          fontSize: 44,
          padding: '20px 36px',
          borderRadius: 16,
          borderBottom: `6px solid ${colors.accent}`,
          maxWidth: '85%',
          textAlign: 'center',
        }}
      >
        {text}
      </div>
    </AbsoluteFill>
  );
};
```

- [ ] **Step 4: Write EndCard.tsx**

```tsx
import {AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {colors, springs} from '../tokens';

// Logo card on cream with the app's "celebrate" spring. Sized for 60 frames (2s).
export const EndCard: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const scale = spring({frame, fps, config: springs.celebrate});
  const underline = interpolate(frame, [10, 25], [0, 220], {extrapolateRight: 'clamp'});
  return (
    <AbsoluteFill style={{backgroundColor: colors.surface, justifyContent: 'center', alignItems: 'center'}}>
      <div style={{transform: `scale(${scale})`, textAlign: 'center'}}>
        <div style={{fontFamily: 'Fraunces', fontWeight: 700, fontSize: 96, color: colors.textPrimary}}>
          PlayerPath
        </div>
        <div style={{height: 8, width: underline, backgroundColor: colors.accent, borderRadius: 4, margin: '16px auto 0'}} />
        <div style={{fontFamily: 'Inter', fontWeight: 500, fontSize: 34, color: colors.textSecondary, marginTop: 24}}>
          Every game. Every swing.
        </div>
      </div>
    </AbsoluteFill>
  );
};
```

- [ ] **Step 5: Verify via temporary registration + stills**

Temporarily add to `Root.tsx` (removed again in this same step after verifying — Task 5 registers the real compositions):

```tsx
import {EndCard} from './scenes/EndCard';
// inside Root's returned fragment:
<Composition id="EndCardPreview" component={EndCard} width={886} height={1920} fps={30} durationInFrames={60} />
```

```bash
cd marketing/remotion && npx remotion still EndCardPreview out/endcard-f45.png --frame=45
```

Read `marketing/remotion/out/endcard-f45.png`: Fraunces "PlayerPath" at full scale, terracotta underline fully drawn, Inter tagline below. Then remove the temporary registration.

- [ ] **Step 6: Commit**

```bash
git add marketing/remotion/src
git commit -m "marketing: shot manifest and scene components"
```

---

### Task 5: AppStorePreview composition

**Files:**
- Create: `marketing/remotion/src/compositions/AppStorePreview.tsx`
- Modify: `marketing/remotion/src/Root.tsx` (register AppStorePreview)

**Interfaces:**
- Consumes: `APP_STORE_SHOTS`, `FootageScene`, `CaptionOverlay`, `EndCard` (Task 4).
- Produces: `AppStorePreview: React.FC` and `APP_STORE_DURATION_FRAMES: number` (= 750); composition id `"AppStorePreview"` used by the `render:appstore` script.

- [ ] **Step 1: Write the composition**

```tsx
import {Series} from 'remotion';
import {APP_STORE_SHOTS} from '../shots';
import {FootageScene} from '../scenes/FootageScene';
import {CaptionOverlay} from '../scenes/CaptionOverlay';
import {EndCard} from '../scenes/EndCard';

const FPS = 30;
const END_CARD_FRAMES = 60; // 2s

export const APP_STORE_DURATION_FRAMES =
  APP_STORE_SHOTS.reduce((sum, s) => sum + s.seconds * FPS, 0) + END_CARD_FRAMES; // 750 = 25s

export const AppStorePreview: React.FC = () => (
  <Series>
    {APP_STORE_SHOTS.map((shot) => (
      <Series.Sequence key={shot.id} durationInFrames={shot.seconds * FPS}>
        <FootageScene file={shot.file} shotId={shot.id} />
        {shot.caption ? <CaptionOverlay text={shot.caption} /> : null}
      </Series.Sequence>
    ))}
    <Series.Sequence durationInFrames={END_CARD_FRAMES}>
      <EndCard />
    </Series.Sequence>
  </Series>
);
```

- [ ] **Step 2: Register in Root.tsx**

Add alongside BrandSample (Root returns a fragment `<>...</>` once there are 2+ compositions):

```tsx
import {AppStorePreview, APP_STORE_DURATION_FRAMES} from './compositions/AppStorePreview';
// inside the fragment:
<Composition
  id="AppStorePreview"
  component={AppStorePreview}
  width={886}
  height={1920}
  fps={30}
  durationInFrames={APP_STORE_DURATION_FRAMES}
/>
```

- [ ] **Step 3: Verify stills at scene boundaries**

```bash
cd marketing/remotion \
  && npx remotion still AppStorePreview out/as-f000.png --frame=0 \
  && npx remotion still AppStorePreview out/as-f110.png --frame=110 \
  && npx remotion still AppStorePreview out/as-f700.png --frame=700
```

Read the three PNGs: f0 = `[journal-scroll]` placeholder with caption mid-spring; f110 = `[record-tag]` placeholder with its caption settled; f700 = end card.

- [ ] **Step 4: Render and check the file**

```bash
cd marketing/remotion && npm run render:appstore \
  && mdls -name kMDItemPixelWidth -name kMDItemPixelHeight -name kMDItemDurationSeconds out/appstore-preview.mp4
```

Expected: render completes; `kMDItemPixelWidth = 886`, `kMDItemPixelHeight = 1920`, `kMDItemDurationSeconds = 25` (±0.1).

- [ ] **Step 5: Commit**

```bash
git add marketing/remotion/src
git commit -m "marketing: AppStorePreview composition (886x1920, 25s)"
```

---

### Task 6: SocialCut composition

**Files:**
- Create: `marketing/remotion/src/scenes/HookOverlay.tsx`
- Create: `marketing/remotion/src/compositions/SocialCut.tsx`
- Modify: `marketing/remotion/src/Root.tsx` (register SocialCut)

**Interfaces:**
- Consumes: `SOCIAL_SHOTS`, `FootageScene`, `CaptionOverlay`, `EndCard` (Task 4); `colors`, `springs` (Task 3).
- Produces: composition id `"SocialCut"` (1080×1920) used by the `render:social` script; `HookOverlay: React.FC<{text: string}>`.

- [ ] **Step 1: Write HookOverlay.tsx** (big Fraunces hook for the first 2 seconds)

```tsx
import {AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {colors, springs} from '../tokens';

// Full-width hook text over the opening shot; fades out over frames 50–60.
export const HookOverlay: React.FC<{text: string}> = ({text}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const inProgress = spring({frame, fps, config: springs.celebrate});
  const fadeOut = interpolate(frame, [50, 60], [1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  return (
    <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center', opacity: fadeOut}}>
      <div
        style={{
          transform: `scale(${inProgress})`,
          fontFamily: 'Fraunces',
          fontWeight: 700,
          fontSize: 76,
          color: colors.surface,
          textShadow: '0 4px 24px rgba(0,0,0,0.55)',
          textAlign: 'center',
          maxWidth: '85%',
        }}
      >
        {text}
      </div>
    </AbsoluteFill>
  );
};
```

- [ ] **Step 2: Write SocialCut.tsx**

```tsx
import {Sequence, Series} from 'remotion';
import {SOCIAL_SHOTS} from '../shots';
import {FootageScene} from '../scenes/FootageScene';
import {CaptionOverlay} from '../scenes/CaptionOverlay';
import {EndCard} from '../scenes/EndCard';
import {HookOverlay} from '../scenes/HookOverlay';

const FPS = 30;
const END_CARD_FRAMES = 60;

export const SOCIAL_DURATION_FRAMES =
  SOCIAL_SHOTS.reduce((sum, s) => sum + s.seconds * FPS, 0) + END_CARD_FRAMES; // 750 = 25s

export const SocialCut: React.FC = () => (
  <>
    <Series>
      {SOCIAL_SHOTS.map((shot) => (
        <Series.Sequence key={shot.id} durationInFrames={shot.seconds * FPS}>
          <FootageScene file={shot.file} shotId={shot.id} />
          {shot.caption ? <CaptionOverlay text={shot.caption} /> : null}
        </Series.Sequence>
      ))}
      <Series.Sequence durationInFrames={END_CARD_FRAMES}>
        <EndCard />
      </Series.Sequence>
    </Series>
    <Sequence durationInFrames={60}>
      <HookOverlay text="Your coach, on every clip" />
    </Sequence>
  </>
);
```

- [ ] **Step 3: Register in Root.tsx**

```tsx
import {SocialCut, SOCIAL_DURATION_FRAMES} from './compositions/SocialCut';
// inside the fragment:
<Composition id="SocialCut" component={SocialCut} width={1080} height={1920} fps={30} durationInFrames={SOCIAL_DURATION_FRAMES} />
```

- [ ] **Step 4: Verify hook still + render**

```bash
cd marketing/remotion && npx remotion still SocialCut out/social-f020.png --frame=20 \
  && npm run render:social \
  && mdls -name kMDItemPixelWidth -name kMDItemPixelHeight -name kMDItemDurationSeconds out/social-cut.mp4
```

Read `out/social-f020.png`: hook text at full scale over the `[coach-telestration]` placeholder, caption card also visible. `mdls`: 1080×1920, ~25s.

- [ ] **Step 5: Commit**

```bash
git add marketing/remotion/src
git commit -m "marketing: SocialCut composition with hook overlay"
```

---

### Task 7: WebHeroLoop composition

**Files:**
- Create: `marketing/remotion/src/compositions/WebHeroLoop.tsx`
- Modify: `marketing/remotion/src/Root.tsx` (register WebHeroLoop)

**Interfaces:**
- Consumes: `APP_STORE_SHOTS`, `FootageScene` (Task 4); `colors` (Task 3). No text overlays (spec).
- Produces: composition id `"WebHeroLoop"` (1920×1080, 360 frames) used by `render:web` and `render:web:webm`.

- [ ] **Step 1: Write the composition** — three 4s segments, dip-to-cream at both ends so the loop point is invisible

```tsx
import {AbsoluteFill, Series, interpolate, useCurrentFrame} from 'remotion';
import {APP_STORE_SHOTS} from '../shots';
import {FootageScene} from '../scenes/FootageScene';
import {colors} from '../tokens';

const FPS = 30;
const SEGMENT_FRAMES = 4 * FPS;
const DIP_FRAMES = 12;
export const WEB_LOOP_DURATION_FRAMES = 3 * SEGMENT_FRAMES; // 360 = 12s

const LOOP_SHOT_IDS = ['journal-scroll', 'highlight-reel', 'golf-scorecard'];

// Cream overlay: opaque at frame 0 and the final frame, transparent between —
// first and last frames are identical solid cream, so the loop point is seamless.
const LoopDip: React.FC = () => {
  const frame = useCurrentFrame();
  const opacity = interpolate(
    frame,
    [0, DIP_FRAMES, WEB_LOOP_DURATION_FRAMES - DIP_FRAMES, WEB_LOOP_DURATION_FRAMES - 1],
    [1, 0, 0, 1],
    {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'}
  );
  return <AbsoluteFill style={{backgroundColor: colors.surface, opacity, pointerEvents: 'none'}} />;
};

export const WebHeroLoop: React.FC = () => {
  const shots = LOOP_SHOT_IDS.map((id) => {
    const shot = APP_STORE_SHOTS.find((s) => s.id === id);
    if (!shot) throw new Error(`WebHeroLoop: unknown shot id ${id}`);
    return shot;
  });
  return (
    <>
      <Series>
        {shots.map((shot) => (
          <Series.Sequence key={shot.id} durationInFrames={SEGMENT_FRAMES}>
            <FootageScene file={shot.file} shotId={shot.id} />
          </Series.Sequence>
        ))}
      </Series>
      <LoopDip />
    </>
  );
};
```

- [ ] **Step 2: Register in Root.tsx**

```tsx
import {WebHeroLoop, WEB_LOOP_DURATION_FRAMES} from './compositions/WebHeroLoop';
// inside the fragment:
<Composition id="WebHeroLoop" component={WebHeroLoop} width={1920} height={1080} fps={30} durationInFrames={WEB_LOOP_DURATION_FRAMES} />
```

- [ ] **Step 3: Verify loop-point stills match**

```bash
cd marketing/remotion \
  && npx remotion still WebHeroLoop out/web-f000.png --frame=0 \
  && npx remotion still WebHeroLoop out/web-f359.png --frame=359 \
  && npx remotion still WebHeroLoop out/web-f180.png --frame=180
```

Read all three: f0 and f359 must both be solid cream (identical — that's the seamless loop); f180 shows the `[highlight-reel]` placeholder with no text overlay.

- [ ] **Step 4: Render both formats and check**

```bash
cd marketing/remotion && npm run render:web && npm run render:web:webm \
  && mdls -name kMDItemPixelWidth -name kMDItemPixelHeight -name kMDItemDurationSeconds out/web-hero.mp4 \
  && ls -lh out/web-hero.webm
```

Expected: 1920×1080, ~12s; webm file exists and is non-trivial in size (vp9 renders are slow — minutes, not seconds; that's normal).

- [ ] **Step 5: Commit**

```bash
git add marketing/remotion/src
git commit -m "marketing: WebHeroLoop seamless loop composition"
```

---

### Task 8: Footage integration and final renders (AFTER the capture session)

**Files:**
- Modify: `marketing/remotion/src/shots.ts` (fill in `file` values)
- Requires: all five `.mov` files present in `marketing/remotion/public/footage/` per the Task 2 runbook

**Interfaces:**
- Consumes: everything above, plus captured footage.
- Produces: the three shippable videos in `marketing/remotion/out/`.

- [ ] **Step 1: Confirm footage exists**

```bash
ls marketing/remotion/public/footage/*.mov
```

Expected: exactly `journal-scroll.mov`, `record-tag.mov`, `coach-telestration.mov`, `highlight-reel.mov`, `golf-scorecard.mov`. If any are missing, stop — run the Task 2 runbook first.

- [ ] **Step 2: Fill in the manifest**

In `src/shots.ts`, set each shot's `file` from `null` to its filename, e.g. `{id: 'journal-scroll', file: 'journal-scroll.mov', ...}` — all five entries in `APP_STORE_SHOTS` (`SOCIAL_SHOTS` reuses the same objects).

- [ ] **Step 3: Review in Studio, trim via manifest timings**

```bash
cd marketing/remotion && npm run studio
```

Scrub all three compositions with Trey. If a capture's interesting moment starts late, trim the source in QuickTime (Edit → Trim) rather than adding offset props — keeps the pipeline simple. Adjust per-shot `seconds` in the manifest only if pacing feels wrong; keep the App Store total within 15–30s (`APP_STORE_DURATION_FRAMES` recomputes automatically).

- [ ] **Step 4: Render all three finals**

```bash
cd marketing/remotion && npm run render:appstore && npm run render:social && npm run render:web && npm run render:web:webm
```

- [ ] **Step 5: App Store compliance check**

```bash
mdls -name kMDItemPixelWidth -name kMDItemPixelHeight -name kMDItemDurationSeconds -name kMDItemCodecs marketing/remotion/out/appstore-preview.mp4
```

Verify each item: 886×1920 · duration 15–30s · codec includes H.264 (`avc1`) · watch the video end-to-end confirming footage-first content, no device frames, no hands, no competitor references. Upload to App Store Connect is manual (Trey).

- [ ] **Step 6: Commit the manifest**

```bash
git add marketing/remotion/src/shots.ts
git commit -m "marketing: wire captured footage into shot manifest"
```
