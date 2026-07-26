/**
 * Public recruiting-profile web page.
 *
 * Serves the athlete-facing product's one outward surface: a college coach opens
 * https://profiles.playerpath.net/p/{shareToken} in a browser — no account, no
 * app, no login — and watches the athlete's game film.
 *
 * Two routes, both behind the same published + Pro checks (loadPublishedProfile):
 *   /p/{shareToken}           the page
 *   /p/{shareToken}/avatar    the headshot, proxied — a permanent URL for og:image
 *                             because unfurl caches outlive a signed URL
 *
 * SETUP (manual, one-time): Firebase Console → Hosting → add the custom domain
 * `profiles.playerpath.net` and create the TXT (verification) + A records it
 * issues. Until DNS propagates the same page is served at
 * https://<project>.web.app/p/{token}; the iOS client's link base is the single
 * constant RecruitingProfileService.publicBaseURL.
 *
 * SETUP (also required): the functions runtime service account needs the
 * "Service Account Token Creator" role (iam.serviceAccounts.signBlob) or
 * getSignedUrl() fails for every object and the page renders with no film.
 *
 * Security notes:
 * • This is the ONLY reader of `recruitingProfiles`. firestore.rules grants no
 *   public read — the Admin SDK bypasses rules, which is why the collection can
 *   stay owner-only while this page stays anonymous.
 * • THE PATHS IN THE DOC ARE UNTRUSTED INPUT. The Admin SDK bypasses
 *   storage.rules too, so signing a client-supplied path unchecked would turn
 *   this function into a signed-URL oracle for the whole bucket: publish
 *   `headshotPath: "athlete_videos/<victim>/x.mov"`, open your own page, get a
 *   working link to someone else's private video. Every path is therefore
 *   re-derived against the doc's `userId` (which rules pin immutable) by
 *   ownedPath() before it reaches signPath(). Only the PII keys are safe by
 *   construction — the client gates those; nothing gates the paths.
 * • Firestore stores Storage PATHS, never URLs. Every media URL on the page is
 *   signed here with a SIGNED_URL_HOURS expiry, so a scraped page's links go dead.
 * • Publishing requires Pro, and rules can only enforce that at write time — an
 *   at-rest doc outlives the subscription. So the tier is re-checked here on
 *   every render; a lapsed account's page goes unavailable without a cron.
 * • Everything interpolated into the HTML goes through esc(). The bio, school,
 *   and clip labels are athlete-authored free text — this is a real XSS surface.
 * • Profiles belong to high-school minors, so the page is noindex'd. An
 *   unguessable token is not a reason to let it be searchable.
 */

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import { createHash } from 'crypto';
import { sendPushNotification } from './push';

/**
 * Signed media URLs live long enough to survive a triage session, short enough
 * that a scraped page rots. One hour was too short: grid clips are
 * `preload="none"`, so their URL is first fetched on click — a coach who opened
 * the link at 9:05 and clicked the third clip at 10:40 got a black box with no
 * explanation (the page has no JS to recover with; CSP forbids it). The share
 * token in the URL is the real gate, and the page is `no-store`, so the marginal
 * exposure of a longer window is small.
 */
const SIGNED_URL_HOURS = 8;

/**
 * How long a profile must go un-notified before a view earns an INSTANT push;
 * anything inside the window rolls into the daily digest instead.
 */
const NOTIFY_QUIET_MS = 24 * 60 * 60 * 1000;

/**
 * How long the render path will wait on the instant push before serving the page
 * anyway. The page is the product; the push is a nicety.
 */
const PUSH_SEND_BUDGET_MS = 1500;

/** How many trailing days of per-day view buckets the doc keeps. */
const DAILY_VIEWS_RETENTION_DAYS = 14;

/** "2026-07-25" — dailyViews map keys. UTC everywhere; the app only sums them. */
function utcDayKey(date: Date): string {
  return date.toISOString().slice(0, 10);
}

/** Mirrors RecruitingProfileService.maxHighlights and the firestore.rules cap. */
const MAX_HIGHLIGHTS = 8;

/**
 * Link unfurlers (iMessage, Slack, WhatsApp…) fetch the page to build a preview.
 * Every shared link triggers at least one, so counting them would make viewCount
 * a measure of sharing rather than of coaches actually looking.
 */
const BOT_UA = /bot|crawler|spider|preview|facebookexternalhit|slackbot|whatsapp|telegram|discord|twitterbot|linkedinbot|embedly|quora|pinterest|vkshare|redditbot|applebot|skypeuripreview/i;

/**
 * Whether this request should be counted as a human opening the page.
 *
 * Errs toward NOT counting, because the two failure modes are not symmetric.
 * An uncounted view costs one data point. A counted non-view costs more than a
 * wrong number: it fires "your recruiting profile was viewed" at an athlete
 * when nobody looked, AND it burns the 24 h quiet window — so the real coach
 * who opens the link an hour later is silently folded into that night's digest.
 * Over-counting therefore suppresses the exact notification the feature exists
 * to send.
 *
 * Two signals beyond the UA blocklist:
 * • An empty/absent User-Agent. Every browser sends one; anything that doesn't
 *   is a script. (This was previously counted as human.)
 * • An `Accept` header that doesn't ask for HTML. A browser navigating to a page
 *   always sends `text/html,…`; a wildcard-only header, or none at all, is curl,
 *   a library, or a scanner. This is the one that catches the enterprise mail
 *   scanners (Defender Safe Links, Proofpoint, Mimecast) that fetch every link
 *   in an inbound mail with an ordinary desktop Chrome UA — and coachEmailURL
 *   puts this link in a mail addressed to a college program, so those scanners
 *   are on the main path, not an edge case.
 *
 * ⚠️ Testing note: curl sends a wildcard Accept header and so no longer counts as
 * a view. Add `-H 'Accept: text/html'` to exercise the counting path by hand.
 */
function looksLikeBot(req: functions.Request): boolean {
  const ua = String(req.headers['user-agent'] || '').trim();
  if (!ua) return true;
  if (BOT_UA.test(ua)) return true;
  const accept = String(req.headers['accept'] || '');
  return !accept.includes('text/html');
}

/**
 * Per-viewer view-count dedup, keyed by a hash of (client IP + token + UTC hour).
 *
 * The counter is what the athlete sees as "Profile Activity" and what the digest
 * push describes, so a reload has to be worth less than a coach. Best-effort by
 * construction: this is per-instance memory, so with several warm instances the
 * same viewer can still be counted more than once an hour — it collapses the
 * pathological case (one client reloading in a loop) without pretending to be
 * exact. The IP is hashed, never stored raw, and never leaves the instance.
 *
 * A suppressed request skips the instant push too: the push exists to say
 * "someone just opened your page", and a reload is the same someone.
 */
const recentViewers = new Map<string, number>();
const VIEW_DEDUP_WINDOW_MS = 60 * 60 * 1000;
const VIEW_DEDUP_MAX = 5000;

/** True when this viewer already counted for this token in the current window. */
function alreadyCountedRecently(req: functions.Request, token: string): boolean {
  // Hosting/GFE sets x-forwarded-for; the left-most entry is the client. Absent
  // any address we cannot dedup, so we count (never under-count a real coach).
  const forwarded = String(req.headers['x-forwarded-for'] || '').split(',')[0].trim();
  const ip = forwarded || req.ip || '';
  if (!ip) return false;

  const now = Date.now();
  const key = createHash('sha256')
    .update(`${ip}|${token}|${Math.floor(now / VIEW_DEDUP_WINDOW_MS)}`)
    .digest('hex');

  const seenAt = recentViewers.get(key);
  if (seenAt !== undefined && now - seenAt < VIEW_DEDUP_WINDOW_MS) return true;

  if (recentViewers.size >= VIEW_DEDUP_MAX) {
    // Insertion-ordered: drop the oldest rather than growing without bound.
    const oldest = recentViewers.keys().next();
    if (!oldest.done) recentViewers.delete(oldest.value);
  }
  recentViewers.set(key, now);
  return false;
}

/**
 * Share-channel markers the client may send as `?s=`. Mirrors
 * `RecruitingShareTools.ShareChannel` — the two lists are a wire contract.
 *
 * The whitelist is load-bearing, not cosmetic: the value is interpolated into the
 * Firestore field path `channelViews.<s>`, where a dot would silently create
 * nested fields and `__name__`-style input has no business going. Anything not in
 * this set is dropped, so an unknown channel costs a lost data point rather than a
 * malformed document.
 */
const SHARE_CHANNELS = new Set(['share', 'copy', 'qr', 'mail', 'bio']);

/** The validated share channel for this request, or null if absent/unknown. */
function shareChannel(req: functions.Request): string | null {
  const raw = (req.query || {}).s;
  const value = typeof raw === 'string' ? raw : '';
  return SHARE_CHANNELS.has(value) ? value : null;
}

/**
 * Share tokens are v4 UUIDs and always have been — `claimShareToken` only ever
 * mints `UUID().uuidString`. Matching the exact shape (rather than "some
 * alphanumeric string") means a junk request costs a regex instead of a Firestore
 * query on an endpoint that is unauthenticated and has no App Check. Note Swift
 * emits UUIDs UPPERCASE, hence the case-insensitive class.
 */
const TOKEN_RE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

/**
 * Where these pages are served. Mirrors RecruitingProfileService.publicBaseURL.
 * Hardcoded rather than read off the Host header: it ends up in og:image, and a
 * header is caller-controlled.
 */
const PUBLIC_ORIGIN = 'https://profiles.playerpath.net';

/**
 * The growth loop's one outbound link, tagged so it stops arriving as untagged
 * direct traffic. `Referrer-Policy: no-referrer` is deliberate and stays (the
 * share token lives in the URL), which is exactly why the attribution has to
 * ride in the query string instead.
 *
 * `&amp;` because this goes straight into an HTML attribute.
 */
const MARKETING_HREF =
  'https://playerpath.net/?utm_source=recruiting&amp;utm_medium=profile&amp;utm_campaign=share_page';

/**
 * Set on every response, page or image.
 *
 * The page is built entirely from athlete-authored free text. `esc()` is the real
 * defense and CSP is the backstop for the day something slips past it — hence
 * `default-src 'none'`, widened only to what the page actually loads: signed
 * Storage URLs for video and posters, and same-origin for the avatar route.
 * `no-referrer` matters on its own: without it every media request leaks the page
 * URL — which contains the share token — to Google in the Referer header.
 */
const SECURITY_HEADERS: Record<string, string> = {
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'no-referrer',
  'Strict-Transport-Security': 'max-age=31536000',
  'Content-Security-Policy': [
    "default-src 'none'",
    "img-src 'self' https://storage.googleapis.com data:",
    'media-src https://storage.googleapis.com',
    "style-src 'unsafe-inline'",
    "base-uri 'none'",
    "form-action 'none'",
    "frame-ancestors 'none'",
  ].join('; '),
};

interface StatPair {
  label?: unknown;
  value?: unknown;
}

/** The default Storage bucket, derived rather than imported from @google-cloud. */
type Bucket = ReturnType<ReturnType<typeof admin.storage>['bucket']>;

/**
 * Re-derives a storage path against the profile owner, rejecting anything that
 * points outside their namespace.
 *
 * The doc's paths are written by the client and are NOT validated by
 * firestore.rules (a rule can't iterate `highlights[]`), while this function
 * signs with the Admin SDK, which ignores storage.rules. This check is therefore
 * the only thing standing between a published profile and a signed URL to any
 * object in the bucket. `ownerUID` comes from `data.userId`, which rules pin to
 * the creator and freeze on update — so it's a trustworthy anchor.
 */
function ownedPath(path: unknown, ownerUID: string): string | null {
  if (typeof path !== 'string' || !path || !ownerUID) return null;
  if (path.includes('..')) return null;
  const allowed = [`athlete_videos/${ownerUID}/`, `recruiting_headshots/${ownerUID}/`];
  return allowed.some((prefix) => path.startsWith(prefix)) ? path : null;
}

/** HTML-escape. Applied at EVERY interpolation of stored data — no exceptions. */
function esc(value: unknown): string {
  if (value === null || value === undefined) return '';
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/**
 * Warm-instance memo of signed URLs, keyed by Storage path.
 *
 * A full render signs up to 17 objects (8 videos + 8 posters + the headshot),
 * and `Cache-Control: no-store` means every reload reaches this function — so an
 * un-memoized render is 17 IAM signBlob calls per request, which a reload loop
 * turns into a direct quota/cost amplifier. Signing is deterministic per path,
 * so a warm instance can reuse the URL until it nears expiry.
 *
 * Entries expire EARLY (`- SIGN_CACHE_MARGIN_MS`) so a URL handed to a browser
 * always has usable life left. Only successes are cached: caching a miss would
 * pin a just-uploaded object as absent for the rest of the hour.
 */
const signedUrlCache = new Map<string, { url: string; expiresAt: number }>();
/** Retire a memo 5 minutes before the URL itself dies. */
const SIGN_CACHE_MARGIN_MS = 5 * 60 * 1000;
/** Hard ceiling — this is per-instance memory, not a cache tier. */
const SIGN_CACHE_MAX = 500;

function signPath(bucket: Bucket, path: unknown): Promise<string | null> {
  if (typeof path !== 'string' || !path) return Promise.resolve(null);
  const memo = signedUrlCache.get(path);
  if (memo && memo.expiresAt > Date.now()) return Promise.resolve(memo.url);
  const expires = new Date();
  expires.setHours(expires.getHours() + SIGNED_URL_HOURS);
  return bucket
    .file(path)
    .getSignedUrl({ action: 'read', expires })
    .then(([url]: [string]) => {
      // Insertion-ordered, so the first key is the oldest — evict it when full.
      if (signedUrlCache.size >= SIGN_CACHE_MAX) {
        const oldest = signedUrlCache.keys().next();
        if (!oldest.done) signedUrlCache.delete(oldest.value);
      }
      signedUrlCache.set(path, {
        url,
        expiresAt: expires.getTime() - SIGN_CACHE_MARGIN_MS,
      });
      return url;
    })
    .catch((error: unknown) => {
      // A missing object (deleted clip, never-uploaded thumbnail) must degrade to
      // one absent tile, never a 500 for the whole page.
      console.warn('serveRecruitingProfile: could not sign', path, error);
      return null;
    });
}

/**
 * Whether a Storage object is definitively gone.
 *
 * `getSignedUrl` only computes a signature — it never asks GCS whether the
 * object is there — so a clip deleted after publish keeps signing successfully
 * and the page renders a tile that answers a coach's click with a raw `NoSuchKey`
 * XML error. Publish-time `missingStoragePaths` closes the window at publish
 * only; nothing removes a highlight from a published profile when its clip is
 * later deleted (quota sweep, coach-side delete, a wipe on another device).
 *
 * A THROWN error is not evidence of absence — a transient GCS failure or a
 * permissions blip would otherwise blank the film on a perfectly healthy
 * profile, which is a far worse outcome than the tile it's meant to hide. Only a
 * definitive `false` counts.
 *
 * Cost is one metadata GET per clip per render (≤8, issued in parallel with the
 * signing), which is cheap next to the signBlob calls P2.3's memo already
 * eliminated. Deliberately NOT memoized: the whole point is to notice a deletion
 * promptly, and a warm instance caching "present" for 8 h would reopen the
 * window this closes.
 */
async function objectMissing(bucket: Bucket, path: string): Promise<boolean> {
  try {
    const [exists] = await bucket.file(path).exists();
    return !exists;
  } catch (error) {
    console.warn('serveRecruitingProfile: exists() failed, assuming present', path, error);
    return false;
  }
}

function statRow(items: unknown, className: string): string {
  if (!Array.isArray(items) || items.length === 0) return '';
  const cells = (items as StatPair[])
    .map(
      (item) =>
        `<div class="stat"><div class="stat-v">${esc(item?.value)}</div>` +
        `<div class="stat-l">${esc(item?.label)}</div></div>`
    )
    .join('');
  return `<div class="${className}">${cells}</div>`;
}

function golfSection(golf: Record<string, unknown> | undefined): string {
  if (!golf) return '';
  const lead = statRow(golf.lead, 'stats');
  const detailed = statRow(golf.detailed, 'stats');
  let rounds = '';
  if (Array.isArray(golf.recentRounds) && golf.recentRounds.length > 0) {
    const rows = (golf.recentRounds as Record<string, unknown>[])
      .map(
        (r) =>
          `<tr><td>${esc(r.course)}</td><td class="dim">${esc(r.date)}</td>` +
          `<td class="num">${esc(r.score)}</td><td class="num dim">${esc(r.toPar)}</td></tr>`
      )
      .join('');
    rounds = `<h3>Recent Rounds</h3><div class="scroll"><table>${rows}</table></div>`;
  }
  const note = golf.footnote ? `<p class="note">${esc(golf.footnote)}</p>` : '';
  if (!lead && !detailed && !rounds) return '';
  return `<section class="card"><h2>Golf</h2>${lead}${detailed}${rounds}${note}</section>`;
}

function contactSection(contact: unknown): string {
  if (!Array.isArray(contact) || contact.length === 0) return '';
  const rows = (contact as Record<string, unknown>[])
    .map((item) => {
      const kind = typeof item.kind === 'string' ? item.kind : '';
      const value = esc(item.value);
      // mailto/tel only for the fields the athlete explicitly published.
      let rendered = value;
      if (kind === 'email') rendered = `<a href="mailto:${value}">${value}</a>`;
      if (kind === 'phone') rendered = `<a href="tel:${value}">${value}</a>`;
      return `<div class="row"><span class="dim">${esc(item.label)}</span><span>${rendered}</span></div>`;
    })
    .join('');
  return `<section class="card"><h2>Contact</h2>${rows}</section>`;
}

/**
 * The MIME type a storage path should be declared as, or null to declare nothing.
 *
 * Only `.mp4` is asserted, and that is deliberate. The app now publishes an
 * H.264/mp4 rendition of each clip (RecruitingWebRenditionService), and telling
 * the browser so is the win. But a clip whose rendition could not be produced —
 * and EVERY clip on a profile published before that shipped — is still the
 * HEVC-in-QuickTime master. Declaring `video/mp4` over a QuickTime file would be
 * a lie that can make a browser reject bytes it would otherwise have sniffed and
 * played. For anything that isn't a `.mp4`, emitting no type at all reproduces
 * exactly today's behaviour.
 */
function mimeForPath(path: string | null): string | null {
  if (!path) return null;
  return path.toLowerCase().endsWith('.mp4') ? 'video/mp4' : null;
}

/**
 * A <video> with static fallback content, and a <source type> when we can honestly
 * assert one (see mimeForPath).
 *
 * The fallback text is the only error affordance this page can have: CSP is
 * `default-src 'none'`, so there is no JS to listen for the element's `error`
 * event. Without it a coach whose browser can't decode the track sees an
 * unexplained black box, and nobody on either end ever learns the share failed.
 * Note it renders only when the <video> element itself is unsupported; the
 * expired-URL and codec cases still show the browser's own empty player, so the
 * copy is worded for "something's wrong here", not for one specific cause.
 */
function videoTag(
  url: string,
  poster: string | null,
  mime: string | null,
  preload: 'metadata' | 'none'
): string {
  return (
    `<video controls playsinline preload="${preload}"${poster ? ` poster="${esc(poster)}"` : ''}>` +
    `<source src="${esc(url)}"${mime ? ` type="${esc(mime)}"` : ''}>` +
    `<p class="vfallback">This clip won’t play in your browser. Try refreshing, or open this link on a phone.</p>` +
    `</video>`
  );
}

interface RenderClip {
  url: string;
  poster: string | null;
  label: string;
  mime: string | null;
  durationSeconds: number | null;
}

/** "0:42" / "3:07" / "1:02:30". */
function clockDuration(totalSeconds: number): string {
  const whole = Math.max(0, Math.round(totalSeconds));
  const hours = Math.floor(whole / 3600);
  const minutes = Math.floor((whole % 3600) / 60);
  const seconds = whole % 60;
  const mm = hours > 0 ? String(minutes).padStart(2, '0') : String(minutes);
  return `${hours > 0 ? `${hours}:` : ''}${mm}:${String(seconds).padStart(2, '0')}`;
}

/**
 * Caption under a clip: the athlete-authored label plus its runtime.
 *
 * The runtime is worth the space because the grid clips are `preload="none"` —
 * the browser shows no scrubber and no duration until the coach clicks, so
 * without this there is nothing to tell them whether a tile is a 9-second cut or
 * a 4-minute at-bat. That is exactly the decision they're making when they scan
 * eight tiles.
 */
function clipCaption(clip: RenderClip): string {
  const parts = [clip.label, clip.durationSeconds ? clockDuration(clip.durationSeconds) : '']
    .filter(Boolean);
  return parts.length > 0 ? `<p class="cap">${esc(parts.join(' · '))}</p>` : '';
}

/**
 * The film, with the header and provenance line that used to be missing.
 *
 * The section previously opened with a bare video and no heading, and the one
 * claim no highlight-mixtape competitor can make — that these clips were tagged
 * play-by-play in an app, not assembled by a paid editor — sat 300 lines below
 * in 13px grey footer type. It belongs directly under the film it describes.
 *
 * "Tagged", not "recorded": clips can be imported from Photos (BulkVideoImport),
 * so "recorded in PlayerPath" would be false for some of them. The tagging is
 * true for every clip on the page regardless of where the video came from — and
 * a provenance line that overclaims is worth less than none, which is the same
 * reasoning behind the measurables' "self-reported" note.
 */
function videoSection(clips: RenderClip[], dateRange: string): string {
  if (clips.length === 0) return '';
  const [hero, ...rest] = clips;
  const heroHTML =
    `<div class="hero">` +
    videoTag(hero.url, hero.poster, hero.mime, 'metadata') +
    clipCaption(hero) +
    `</div>`;
  const grid =
    rest.length > 0
      ? `<div class="grid">` +
        rest
          .map(
            (c) =>
              `<div class="cell">` +
              videoTag(c.url, c.poster, c.mime, 'none') +
              clipCaption(c) +
              `</div>`
          )
          .join('') +
        `</div>`
      : '';
  const runtime = clips.reduce((total, c) => total + (c.durationSeconds || 0), 0);
  const note = [
    `${clips.length} clip${clips.length === 1 ? '' : 's'}`,
    runtime > 0 ? clockDuration(runtime) : '',
    'tagged in PlayerPath',
    dateRange,
  ]
    .filter(Boolean)
    .join(' · ');
  return (
    `<section class="film"><h2>Game Film</h2>` +
    `<p class="note filmnote">${esc(note)}</p>${heroHTML}${grid}</section>`
  );
}

/**
 * Stands in for the film when every published clip's object is gone from
 * Storage. Says so plainly rather than reusing "temporarily unavailable": the
 * objects are not coming back, and telling a coach to try again shortly sends
 * them to reload a page that will never change. The rest of the profile still
 * renders — a coach who came for the film should at least leave with the
 * athlete's measurables and contact details.
 */
/**
 * "Updated July 2026 · " for the footer, or '' when the doc predates the field.
 *
 * A recruiting page with no date on it is read as undated, and an undated page
 * is assumed stale — a coach has no way to tell a profile republished last week
 * from one abandoned two seasons ago. `updatedAt` is stamped fresh on every
 * publish (unlike `publishedAt`, which is carried forward from the FIRST
 * publish), so it is the honest freshness signal.
 *
 * Month granularity, and UTC: a day-level date would invite "why does it say
 * yesterday", and at month granularity the timezone can only matter on one day
 * out of thirty.
 */
function updatedLabel(updatedAt: unknown): string {
  if (!(updatedAt instanceof admin.firestore.Timestamp)) return '';
  const label = new Intl.DateTimeFormat('en-US', {
    month: 'long',
    year: 'numeric',
    timeZone: 'UTC',
  }).format(updatedAt.toDate());
  return `Updated ${esc(label)} · `;
}

function filmRemovedSection(): string {
  return (
    `<section class="card"><h2>Game Film</h2>` +
    `<p class="note">This profile's film is no longer available.</p></section>`
  );
}

const STYLE = `
:root{color-scheme:light dark;--bg:#faf8f5;--card:#fff;--text:#1c1c1e;--dim:#6b6b70;--line:#e6e2dc;--accent:#357a57}
@media(prefers-color-scheme:dark){:root{--bg:#111;--card:#1c1c1e;--text:#f2f2f7;--dim:#98989d;--line:#2c2c2e}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font:16px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif}
.wrap{max-width:760px;margin:0 auto;padding:24px 16px 48px}
header{text-align:center;margin-bottom:24px}
.shot{width:112px;height:112px;border-radius:50%;object-fit:cover;border:1px solid var(--line)}
h1{font-size:28px;margin:12px 0 4px}
.sub{font-size:18px;color:var(--dim);margin:0 0 6px}
.meta{font-size:14px;color:var(--dim);margin:2px 0}
.card{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:16px;margin:16px 0}
h2{font-size:18px;margin:0 0 12px}
h3{font-size:14px;color:var(--dim);margin:16px 0 8px;text-transform:uppercase;letter-spacing:.04em}
.film{margin:16px 0}
/* max-height, not just width: a highlight recorded holding the phone upright is
   1080x1920, and unconstrained that renders a ~1300px-tall hero on a laptop —
   the play button and caption land below the fold and the coach opens to a full
   screen of black. object-fit:contain letterboxes instead of cropping the
   athlete out. The athlete can't see this: the in-app preview thumbnails are a
   fixed landscape size. */
.hero video{width:100%;max-height:min(70vh,560px);object-fit:contain;border-radius:16px;background:#000;display:block}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:12px;margin-top:12px}
.cell video{width:100%;aspect-ratio:16/9;object-fit:contain;border-radius:12px;background:#000;display:block}
.cap{font-size:13px;color:var(--dim);margin:6px 2px 0}
.vfallback{font-size:13px;color:var(--dim);padding:16px;margin:0}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(88px,1fr));gap:10px;margin-bottom:8px}
.stat{background:var(--bg);border-radius:10px;padding:10px;text-align:center}
.stat-v{font-size:19px;font-weight:600}
.stat-l{font-size:11px;color:var(--dim);margin-top:2px}
.scroll{overflow-x:auto}
table{width:100%;border-collapse:collapse;font-size:14px}
td{padding:7px 4px;border-bottom:1px solid var(--line)}
.num{text-align:right;font-variant-numeric:tabular-nums}
.dim{color:var(--dim)}
.row{display:flex;justify-content:space-between;gap:12px;padding:7px 0;border-bottom:1px solid var(--line)}
.row:last-child{border-bottom:0}
a{color:var(--accent)}
.note{font-size:12px;color:var(--dim);margin:10px 0 0}
/* The film note sits ABOVE its clips, so its margin has to flip. */
.filmnote{margin:0 0 10px}
.bio{white-space:pre-wrap;margin:0}
footer{text-align:center;color:var(--dim);font-size:13px;margin-top:32px}
footer a{text-decoration:none}
.empty{max-width:420px;margin:18vh auto;text-align:center;padding:0 20px}
`;

function page(opts: {
  title: string;
  description: string;
  image: string | null;
  body: string;
}): string {
  return `<!doctype html><html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(opts.title)}</title>
<meta name="robots" content="noindex,nofollow">
<meta name="description" content="${esc(opts.description)}">
<meta property="og:type" content="profile">
<meta property="og:title" content="${esc(opts.title)}">
<meta property="og:description" content="${esc(opts.description)}">
${opts.image ? `<meta property="og:image" content="${esc(opts.image)}">` : ''}
<meta name="twitter:card" content="${opts.image ? 'summary_large_image' : 'summary'}">
<style>${STYLE}</style>
</head><body>${opts.body}</body></html>`;
}

function unavailablePage(): string {
  return page({
    title: 'Profile unavailable · PlayerPath',
    description: 'This recruiting profile is not available.',
    image: null,
    body: `<div class="empty"><h1>Profile unavailable</h1>
<p class="sub">This profile has been unpublished or the link is incorrect.</p>
<footer><a href="${MARKETING_HREF}">PlayerPath</a></footer></div>`,
  });
}

/**
 * Shown when the profile exists and is live but its film wouldn't load — almost
 * always a missing signBlob role. Distinct copy on purpose: telling an athlete
 * their link is "incorrect" when it's our signing that broke sends them chasing
 * the wrong problem, and it's the message they'll relay to a coach.
 */
function temporarilyUnavailablePage(): string {
  return page({
    title: 'Temporarily unavailable · PlayerPath',
    description: 'This recruiting profile is temporarily unavailable.',
    image: null,
    body: `<div class="empty"><h1>Temporarily unavailable</h1>
<p class="sub">This profile's video can't be loaded right now. The link is fine — please try again shortly.</p>
<footer><a href="${MARKETING_HREF}">PlayerPath</a></footer></div>`,
  });
}

/** A live, Pro-backed profile, or null. Shared by the page and the avatar route. */
interface LoadedProfile {
  doc: admin.firestore.QueryDocumentSnapshot;
  data: Record<string, unknown>;
  ownerUID: string;
}

/**
 * Looks up a published profile by share token and confirms it should be served.
 *
 * The tier check is here rather than at write time on purpose: rules gate writes
 * and cannot expire an at-rest doc, so "publish on Pro, then cancel" would leave
 * the page up forever. Every route that exposes profile content — page or image —
 * must go through this, or it becomes the hole.
 */
async function loadPublishedProfile(token: string): Promise<LoadedProfile | null> {
  const db = admin.firestore();
  // Single equality filter, then check isPublished in code: keeps this off the
  // composite-index path entirely (same shape as enforceStorageQuota).
  const snap = await db
    .collection('recruitingProfiles')
    .where('shareToken', '==', token)
    .limit(1)
    .get();

  if (snap.empty) return null;

  const doc = snap.docs[0];
  const data = doc.data() as Record<string, unknown>;
  if (data.isPublished !== true) return null;

  const ownerUID = typeof data.userId === 'string' ? data.userId : '';
  if (!ownerUID) {
    console.error('serveRecruitingProfile: profile has no userId', doc.id);
    return null;
  }

  const owner = await db.collection('users').doc(ownerUID).get();
  if (owner.get('subscriptionTier') !== 'pro') return null;

  return { doc, data, ownerUID };
}

/** Image routes hung off a profile URL. Both feed og:image. */
type ImageKind = 'avatar' | 'poster';
const IMAGE_KINDS = new Set<string>(['avatar', 'poster']);

/**
 * `/p/{token}/avatar` and `/p/{token}/poster` — profile images, proxied.
 *
 * og:image used to be the signed URL itself, which dies within the hour while
 * link-unfurl caches (iMessage, Slack, Gmail) hold onto it — so a shared profile's
 * preview image broke on exactly the surface this feature grows through, and a
 * signed Storage URL ended up sitting in third-party cache infrastructure. This
 * URL is stable forever; the signed URL never leaves the function.
 *
 * `poster` exists because a headshot is optional and most athletes skip it. With
 * no og:image the card collapses to `twitter:card=summary` — a grey text row —
 * on the single highest-leverage impression this feature has: the moment a coach
 * sees the link in their inbox or a teammate sees it in a group chat. The first
 * highlight's thumbnail is a better unfurl image than a headshot anyway: it's
 * landscape, so it fills the card instead of being cropped to a circle, and it
 * shows the athlete playing.
 *
 * Both kinds go through `ownedPath` — the doc's paths are client-authored and
 * this function signs with the Admin SDK, so skipping that check on the new
 * route would reopen the bucket-wide oracle the avatar route was careful to
 * close.
 */
async function serveProxiedImage(
  res: functions.Response,
  token: string,
  kind: ImageKind
): Promise<void> {
  const profile = await loadPublishedProfile(token);
  let raw: unknown = null;
  if (profile) {
    if (kind === 'avatar') {
      raw = profile.data.headshotPath;
    } else {
      // The hero clip's poster — the same highlight the page renders first.
      const highlights = Array.isArray(profile.data.highlights)
        ? (profile.data.highlights as Record<string, unknown>[])
        : [];
      raw = highlights[0]?.thumbnailStoragePath ?? null;
    }
  }
  const path = profile ? ownedPath(raw, profile.ownerUID) : null;
  if (!path) {
    res.status(404).type('text/plain').send('Not found');
    return;
  }

  // Short cache, not long: an unpublish has to take a minor's photo down promptly,
  // and unfurlers keep their own copy anyway.
  res.set('Cache-Control', 'public, max-age=300');
  res.set('Content-Type', 'image/jpeg');

  const stream = admin.storage().bucket().file(path).createReadStream();
  await new Promise<void>((resolve) => {
    stream.once('error', (error: unknown) => {
      console.warn('serveRecruitingProfile: avatar stream failed', path, error);
      if (!res.headersSent) {
        res.status(404).type('text/plain').send('Not found');
      } else {
        res.end();
      }
      resolve();
    });
    res.once('finish', () => resolve());
    res.once('close', () => resolve());
    stream.pipe(res);
  });
}

// `maxInstances` is the spend ceiling: the route is anonymous, uncached and
// unmetered by design, so a reload loop would otherwise scale out without bound.
// 30 s (down from the 60 s default) bounds the worst case now that the FCM send
// on the first-view-per-day path is itself time-boxed below.
export const serveRecruitingProfile = functions
  .runWith({ maxInstances: 20, timeoutSeconds: 30 })
  .https.onRequest(async (req, res) => {
  // Never cached: the CDN would freeze view counts and, worse, eventually serve
  // signed media URLs past their expiry. (The avatar route overrides both of these.)
  res.set('Cache-Control', 'no-store');
  res.set('Content-Type', 'text/html; charset=utf-8');
  for (const [header, value] of Object.entries(SECURITY_HEADERS)) {
    res.set(header, value);
  }

  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.status(405).type('text/plain').send('Method Not Allowed');
    return;
  }

  // Hosting rewrites /p/** here; the token is the last path segment, which also
  // holds when the function URL is hit directly. `/p/{token}/avatar` and
  // `/p/{token}/poster` add one trailing segment, so strip that first.
  const segments = (req.path || '').split('/').filter(Boolean);
  const lastSegment = segments[segments.length - 1] || '';
  const imageKind: ImageKind | null = IMAGE_KINDS.has(lastSegment)
    ? (lastSegment as ImageKind)
    : null;
  if (imageKind) segments.pop();
  const token = segments[segments.length - 1] || '';

  if (!TOKEN_RE.test(token)) {
    if (imageKind) {
      res.status(404).type('text/plain').send('Not found');
    } else {
      res.status(404).send(unavailablePage());
    }
    return;
  }

  try {
    if (imageKind) {
      await serveProxiedImage(res, token, imageKind);
      return;
    }

    const profile = await loadPublishedProfile(token);
    if (!profile) {
      res.status(404).send(unavailablePage());
      return;
    }
    const { doc, data, ownerUID } = profile;

    const bucket = admin.storage().bucket();

    const rawHighlights = Array.isArray(data.highlights)
      ? (data.highlights as Record<string, unknown>[]).slice(0, MAX_HIGHLIGHTS)
      : [];
    // Three outcomes per highlight, kept apart because they need opposite
    // responses: a GONE object is permanent and must be dropped quietly, while a
    // FAILED signature is usually a missing signBlob IAM role — recoverable, and
    // worth a loud page rather than a silently short one.
    type Resolved =
      | { state: 'ok'; clip: RenderClip }
      | { state: 'gone' }
      | { state: 'failed' };

    const resolved: Resolved[] = await Promise.all(
      rawHighlights.map(async (h): Promise<Resolved> => {
        const videoPath = ownedPath(h.videoStoragePath, ownerUID);
        if (!videoPath) {
          console.warn('serveRecruitingProfile: highlight path rejected for', doc.id);
          return { state: 'gone' };
        }
        // Existence and signing run together: signing a since-deleted object
        // still succeeds (it's a pure signature), so there's nothing to save by
        // waiting on the probe first, and the common case needs both anyway.
        const [missing, url, poster] = await Promise.all([
          objectMissing(bucket, videoPath),
          signPath(bucket, videoPath),
          signPath(bucket, ownedPath(h.thumbnailStoragePath, ownerUID)),
        ]);
        if (missing) {
          console.warn(
            'serveRecruitingProfile: published highlight is gone from Storage for',
            doc.id,
            videoPath
          );
          return { state: 'gone' };
        }
        if (!url) return { state: 'failed' };
        // mime comes from the PATH, not the signed URL: the URL carries query
        // params and the path is what tells us whether this is the web rendition.
        return {
          state: 'ok',
          clip: {
            url,
            poster,
            label: typeof h.label === 'string' ? h.label : '',
            mime: mimeForPath(videoPath),
            // Finite-checked, not just `> 0`: this is a client-written field on
            // a doc whose `highlights` array rules cannot type-check, and
            // Firestore stores NaN/Infinity as legitimate doubles. Unguarded,
            // Infinity formats as "Infinity:NaN:NaN" on the public page.
            durationSeconds:
              typeof h.durationSeconds === 'number' &&
              Number.isFinite(h.durationSeconds) &&
              h.durationSeconds > 0
                ? h.durationSeconds
                : null,
          },
        };
      })
    );
    const clips = resolved.flatMap((r) => (r.state === 'ok' ? [r.clip] : []));
    const signFailures = resolved.filter((r) => r.state === 'failed').length;
    const goneCount = resolved.filter((r) => r.state === 'gone').length;

    // Film is the entire point of the page. If nothing survived AND at least one
    // failure was a signature rather than a deletion, the cause is almost always
    // configuration — a 200 with a bio and no video is a silent failure dressed
    // as success, and unlike a deletion this one can come back.
    if (clips.length === 0 && signFailures > 0) {
      console.error(
        'serveRecruitingProfile: every highlight failed to sign for',
        doc.id,
        '— check the signBlob IAM role on the runtime service account'
      );
      res.status(500).send(temporarilyUnavailablePage());
      return;
    }
    if (goneCount > 0) {
      console.warn(
        `serveRecruitingProfile: ${goneCount} of ${rawHighlights.length} highlights missing for`,
        doc.id
      );
    }
    const headshot = await signPath(bucket, ownedPath(data.headshotPath, ownerUID));
    // The <img> gets the signed URL (same request, so it can't expire in time);
    // og:image gets the stable proxy, because unfurl caches outlive the signature.
    //
    // Falls back to the hero clip's poster when there's no headshot, so a profile
    // without one still unfurls as a picture rather than a grey text row. Keyed
    // on `rawHighlights[0]` — the same highlight `serveProxiedImage` re-derives —
    // rather than on the rendered `clips[0]`, so the tag and the route can't
    // disagree. If that thumbnail happens to be missing the route 404s and the
    // unfurl degrades exactly as it does today; the null branch stays because the
    // thumbnail path is derived by convention and may never have existed.
    const imageBase = `${PUBLIC_ORIGIN}/p/${encodeURIComponent(token)}`;
    const heroPosterPath = ownedPath(rawHighlights[0]?.thumbnailStoragePath, ownerUID);
    const ogImage = headshot
      ? `${imageBase}/avatar`
      : heroPosterPath
        ? `${imageBase}/poster`
        : null;

    const name = typeof data.name === 'string' ? data.name : 'Athlete';
    const subline = typeof data.subline === 'string' ? data.subline : '';
    const physical = typeof data.physicalLine === 'string' ? data.physicalLine : '';
    const school = typeof data.schoolLine === 'string' ? data.schoolLine : '';
    const bio = typeof data.bio === 'string' ? data.bio : '';

    // og:description leads with the numbers a coach filters on, so the unfurled
    // link is itself a first-pass pitch.
    const golf = data.golfStats as Record<string, unknown> | undefined;
    const headlineParts: string[] = [];
    if (Array.isArray(golf?.lead)) {
      (golf!.lead as StatPair[]).slice(0, 3).forEach((s) => {
        if (s?.value) headlineParts.push(`${s.value} ${s.label ?? ''}`.trim());
      });
    } else if (Array.isArray(data.measurables)) {
      (data.measurables as StatPair[]).slice(0, 3).forEach((s) => {
        if (s?.value) headlineParts.push(`${s.label ?? ''} ${s.value}`.trim());
      });
    }
    const description =
      [physical || school, headlineParts.join(' · ')].filter(Boolean).join(' · ') ||
      `${name} — recruiting profile`;

    const measurables = statRow(data.measurables, 'stats');
    const dateRange = typeof data.filmDateRange === 'string' ? data.filmDateRange : '';
    // When every clip's object is gone, say so rather than rendering a profile
    // that silently has no film section at all.
    let film = '';
    if (clips.length > 0) {
      film = videoSection(clips, dateRange);
    } else if (goneCount > 0) {
      film = filmRemovedSection();
    }
    const body = `<div class="wrap">
<header>
${headshot ? `<img class="shot" src="${esc(headshot)}" alt="${esc(name)}">` : ''}
<h1>${esc(name)}</h1>
${subline ? `<p class="sub">${esc(subline)}</p>` : ''}
${physical ? `<p class="meta">${esc(physical)}</p>` : ''}
${school ? `<p class="meta">${esc(school)}</p>` : ''}
</header>
${film}
${golfSection(golf)}
${measurables ? `<section class="card"><h2>Measurables</h2>${measurables}<p class="note">Self-reported by the athlete.</p></section>` : ''}
${bio ? `<section class="card"><h2>About</h2><p class="bio">${esc(bio)}</p></section>` : ''}
${contactSection(data.contact)}
<footer>${updatedLabel(data.updatedAt)}<a href="${MARKETING_HREF}">PlayerPath</a></footer>
</div>`;

    const html = page({
      title: subline ? `${name} · ${subline}` : name,
      description,
      image: ogImage,
      body,
    });

    // Count real visits only. Awaited rather than fire-and-forget: the instance
    // can be frozen the moment the response flushes, which drops the write.
    // Never let analytics' failure cost the page, though — the film is what
    // matters. NOTE: the client's publish is a full-overwrite setData, so every
    // field written here must be carried forward in
    // RecruitingProfileService.publish or a republish erases it.
    if (req.method === 'GET' && !looksLikeBot(req) && !alreadyCountedRecently(req, token)) {
      try {
        // Throttled "just viewed" push: at most one instant push per quiet
        // period; every further view accumulates silently until the daily
        // digest (recruitingViewDigest). A showcase weekend must feel alive,
        // not ring the athlete's phone fifteen times an hour.
        //
        // The quiet check runs in a TRANSACTION against a fresh read: `data`
        // was snapshotted before URL signing, hundreds of ms ago, and the
        // link-blast moment this feature exists for is exactly when two first
        // clicks land together — both would read a stale lastNotifiedAt,
        // double-push, and leave notifiedViewCount one behind viewCount (a
        // ghost digest that evening). First committer wins; the loser sees the
        // fresh stamp and stays silent.
        // The quiet window is per ACCOUNT, on users/{ownerUID}, not per profile.
        // A Pro parent with three published kids who emails all three links to
        // one program used to get three "your profile was viewed" pushes inside
        // a minute — each doc cleared its own window independently. The digest
        // was already rewritten to send one push per account for this exact
        // reason (see recruitingViewDigest); this is the instant path's half.
        // `notifiedViewCount` stays per doc: it is the digest's per-page delta
        // watermark, which has to stay per page.
        // Which share verb this view arrived through, if the link carried a
        // marker. Resolved outside the transaction — it's pure request parsing.
        const channel = shareChannel(req);
        const userRef = admin.firestore().collection('users').doc(ownerUID);
        const isQuiet = await admin.firestore().runTransaction(async (tx) => {
          // Both reads BEFORE any write — Firestore transactions require it.
          const [fresh, freshUser] = await Promise.all([tx.get(doc.ref), tx.get(userRef)]);
          const fd = (fresh.data() || {}) as Record<string, unknown>;
          const ud = (freshUser.data() || {}) as Record<string, unknown>;
          const lastNotifiedAt =
            ud.lastRecruitingNotifiedAt instanceof admin.firestore.Timestamp
              ? ud.lastRecruitingNotifiedAt.toMillis()
              : 0;
          const quiet = Date.now() - lastNotifiedAt > NOTIFY_QUIET_MS;

          const update: Record<string, unknown> = {
            viewCount: admin.firestore.FieldValue.increment(1),
            // Per-day buckets (UTC keys) behind "views this week" in the app.
            // Write-only here; recruitingViewDigest prunes keys older than 14d.
            [`dailyViews.${utcDayKey(new Date())}`]: admin.firestore.FieldValue.increment(1),
            lastViewedAt: admin.firestore.FieldValue.serverTimestamp(),
          };
          // Per-channel totals, so "which share verb actually reaches coaches"
          // stops being a guess. Whitelisted above — never a raw query value.
          if (channel) {
            update[`channelViews.${channel}`] = admin.firestore.FieldValue.increment(1);
          }
          if (quiet) {
            // Counter snapshot INCLUDING this view — the digest pushes only
            // when viewCount has moved past this watermark.
            update.notifiedViewCount =
              (typeof fd.viewCount === 'number' ? fd.viewCount : 0) + 1;
            // set+merge, not update: the account doc is guaranteed in practice,
            // but a missing one must not cost the athlete their view count.
            tx.set(
              userRef,
              { lastRecruitingNotifiedAt: admin.firestore.FieldValue.serverTimestamp() },
              { merge: true }
            );
          }
          tx.update(doc.ref, update);
          return quiet;
        });

        // After the stamp lands, so a failed write can't spam: no stamp, no
        // push. sendPushNotification is itself best-effort and never throws.
        if (isQuiet) {
          // Time-boxed: admin.messaging() retries ECONNRESET/ETIMEDOUT up to 4
          // times at 15 s each, so an APNs stall could hold a fully-rendered
          // page for ~82 s and hand the coach a platform 504 on a healthy
          // profile. The send keeps running after we stop waiting — losing the
          // race costs at most a late push, never the film.
          await Promise.race([
            sendPushNotification(
              ownerUID,
              'Your recruiting profile was viewed',
              `Someone just opened ${typeof data.name === 'string' ? data.name : 'your athlete'}'s page.`,
              // athleteId (== doc.id, the athlete UUID) lets the tap select the
              // right profile on multi-athlete accounts before deep-linking.
              { type: 'recruiting_view', athleteId: doc.id }
            ),
            new Promise<void>((resolve) => setTimeout(resolve, PUSH_SEND_BUDGET_MS)),
          ]);
        }
      } catch (error) {
        console.warn('serveRecruitingProfile: view analytics', error);
      }
    }

    res.status(200).send(html);
  } catch (error) {
    console.error('serveRecruitingProfile error:', error);
    if (res.headersSent) {
      res.end();
    } else if (imageKind) {
      // Don't hand an unfurler an HTML page under an image content type.
      res.status(500).type('text/plain').send('Temporarily unavailable');
    } else {
      res.status(500).send(temporarilyUnavailablePage());
    }
  }
});

/**
 * Daily digest for the views the instant-push throttle held back.
 *
 * 01:00 UTC ≈ 7–8pm Central — evening, when a "coaches looked at your page
 * today" push actually gets read. The window is 25h rather than "since UTC
 * midnight" so views landing between one run and the next day-roll can't fall
 * through the gap.
 *
 * The same sweep prunes dailyViews keys past retention — the render path stays
 * write-only, and a doc nobody views keeps at most stale-but-harmless keys the
 * client never sums (it only reads the trailing 7 days).
 *
 * ONE push per ACCOUNT, not per profile: a Pro parent can have several published
 * athletes, and a per-doc send rang their phone once per kid with the same title
 * at the same minute. So the sweep collects qualifying docs by owner and sends a
 * single notification — hence the two passes below.
 */
// The sweep is serial (an update per doc, then a send per owner) inside what was
// the 60 s default, with retries off — so at scale the instance would be killed
// mid-pass and that night's deltas would be lost PERMANENTLY: the next run's
// 25 h window no longer covers them. 540 s + 512 MB buys roughly an order of
// magnitude of headroom. Still unpaged (P2.8): the query has no limit/cursor, so
// past a few thousand in-window profiles this needs batching too.
export const recruitingViewDigest = functions
  .runWith({ timeoutSeconds: 540, memory: '512MB' })
  .pubsub.schedule('0 1 * * *')
  .timeZone('UTC')
  .onRun(async () => {
    const db = admin.firestore();
    const windowStart = admin.firestore.Timestamp.fromMillis(
      Date.now() - 25 * 60 * 60 * 1000
    );
    // Single-field range — no composite index needed.
    const snap = await db
      .collection('recruitingProfiles')
      .where('lastViewedAt', '>', windowStart)
      .get();

    const cutoffKey = utcDayKey(
      new Date(Date.now() - DAILY_VIEWS_RETENTION_DAYS * 24 * 60 * 60 * 1000)
    );

    /** A profile that has earned a digest, waiting to be grouped by owner. */
    interface PendingDigest {
      ref: admin.firestore.DocumentReference;
      athleteId: string;
      name: string;
      unnotified: number;
      viewCount: number;
      /** The retention pruning for this doc, applied in the same write. */
      prune: Record<string, unknown>;
    }

    // Pass 1 — per doc: prune, and work out whether it owes its owner a digest.
    // Docs that don't (nothing new, unpublished, malformed) are written here and
    // done with; the rest are held so one owner gets one push.
    const pendingByUser = new Map<string, PendingDigest[]>();
    // Growth-loop telemetry. Nothing else reports on the share funnel, so the
    // nightly log line is the only place the numbers surface at all.
    let windowNewViews = 0;
    const channelTotals: Record<string, number> = {};
    for (const doc of snap.docs) {
      try {
        const data = doc.data() as Record<string, unknown>;
        const prune: Record<string, unknown> = {};

        const dailyViews = (data.dailyViews || {}) as Record<string, unknown>;
        for (const key of Object.keys(dailyViews)) {
          if (key < cutoffKey) {
            prune[`dailyViews.${key}`] = admin.firestore.FieldValue.delete();
          }
        }

        const viewCount = typeof data.viewCount === 'number' ? data.viewCount : 0;
        const notified =
          typeof data.notifiedViewCount === 'number' ? data.notifiedViewCount : 0;
        const unnotified = viewCount - notified;
        windowNewViews += Math.max(0, unnotified);
        // channelViews is LIFETIME-cumulative (the render path only increments),
        // so this total is not window-scoped — the log says so.
        const channelViews = (data.channelViews || {}) as Record<string, unknown>;
        for (const [key, value] of Object.entries(channelViews)) {
          if (typeof value === 'number') {
            channelTotals[key] = (channelTotals[key] || 0) + value;
          }
        }
        // isPublished can't be false here in practice (an unpublished page never
        // renders, so lastViewedAt stops moving), but an unpublish AFTER today's
        // views would still land in the window — and a "coaches viewed it" push
        // about a page the athlete just took down reads as a malfunction.
        if (unnotified > 0 && data.isPublished === true && typeof data.userId === 'string') {
          const owner = data.userId;
          const entry: PendingDigest = {
            ref: doc.ref,
            athleteId: doc.id,
            name: typeof data.name === 'string' ? data.name : 'Your athlete',
            unnotified,
            viewCount,
            prune,
          };
          const existing = pendingByUser.get(owner);
          if (existing) existing.push(entry);
          else pendingByUser.set(owner, [entry]);
        } else if (Object.keys(prune).length > 0) {
          await doc.ref.update(prune);
        }
      } catch (error) {
        console.warn(`recruitingViewDigest: ${doc.id}`, error);
      }
    }

    // Pass 2 — per owner: stamp every one of their profiles, THEN send a single
    // push. Stamp-before-send is the same invariant the render path keeps: no
    // stamp, no push, so a failed write can never turn into a nightly repeat.
    let digests = 0;
    for (const [userId, entries] of pendingByUser) {
      // Stamp each profile SEPARATELY. Grouping the sends must not group the
      // failures: one doc's update throwing used to cost only that doc, and
      // bailing on the whole account here would skip its siblings' stamps and
      // swallow the views of any sibling already stamped — stamped but never
      // notified, and tomorrow's delta starts from the new watermark, so those
      // views are simply gone. The push then describes only what was stamped.
      const stamped: PendingDigest[] = [];
      for (const entry of entries) {
        try {
          // `lastDigestAt`, NOT `lastNotifiedAt`. Stamping the instant path's
          // field here re-armed its 24 h window nightly, so any profile viewed
          // at least once a day could never satisfy the quiet test again — the
          // real-time "someone just opened your page" push became unreachable
          // on exactly the profiles that were working. Idempotency for the
          // digest comes from `notifiedViewCount`, not from a timestamp, so
          // nothing is lost. (Instant now gates on the account-level
          // users/{uid}.lastRecruitingNotifiedAt, which this sweep never
          // touches; `lastNotifiedAt` values left on old docs are inert.)
          await entry.ref.update({
            ...entry.prune,
            notifiedViewCount: entry.viewCount,
            lastDigestAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          stamped.push(entry);
        } catch (error) {
          console.warn(`recruitingViewDigest: ${entry.athleteId}`, error);
        }
      }
      if (stamped.length === 0) continue;

      try {
        const total = stamped.reduce((sum, entry) => sum + entry.unnotified, 0);
        const single = stamped.length === 1;
        // Only a single-athlete digest can deep-link: with several there is no
        // one profile to open, and MainTabView's observer already lands a push
        // carrying no athleteId on the More tab root rather than guessing.
        const data: Record<string, string> = single
          ? { type: 'recruiting_view', athleteId: stamped[0].athleteId }
          : { type: 'recruiting_view' };

        await sendPushNotification(
          userId,
          single ? 'Your recruiting profile was viewed' : 'Your recruiting profiles were viewed',
          // "today" would overstate: the delta can include quiet-window views
          // from before the UTC day rolled.
          single
            ? stamped[0].unnotified === 1
              ? `${stamped[0].name}'s page was opened 1 more time.`
              : `${stamped[0].name}'s page was opened ${stamped[0].unnotified} more times.`
            : `${total} more views across ${stamped.length} of your athletes' pages.`,
          data
        );
        digests++;
      } catch (error) {
        console.warn(`recruitingViewDigest: user ${userId}`, error);
      }
    }
    const channelSummary =
      Object.entries(channelTotals)
        .sort((a, b) => b[1] - a[1])
        .map(([name, count]) => `${name}=${count}`)
        .join(' ') || 'none';
    console.log(
      `✅ recruitingViewDigest: ${snap.size} active profile(s), ${digests} digest(s) sent, ` +
        `${windowNewViews} new view(s) in window; lifetime views by channel: ${channelSummary}`
    );
  });
