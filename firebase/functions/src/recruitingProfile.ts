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
 *   signed here with a 1-hour expiry, so a scraped page's links go dead.
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

/** Signed media URLs live an hour — long enough to watch, short enough to rot. */
const SIGNED_URL_HOURS = 1;

/** Mirrors RecruitingProfileService.maxHighlights and the firestore.rules cap. */
const MAX_HIGHLIGHTS = 8;

/**
 * Link unfurlers (iMessage, Slack, WhatsApp…) fetch the page to build a preview.
 * Every shared link triggers at least one, so counting them would make viewCount
 * a measure of sharing rather than of coaches actually looking.
 */
const BOT_UA = /bot|crawler|spider|preview|facebookexternalhit|slackbot|whatsapp|telegram|discord|twitterbot|linkedinbot|embedly|quora|pinterest|vkshare|redditbot|applebot|skypeuripreview/i;

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

function signPath(bucket: Bucket, path: unknown): Promise<string | null> {
  if (typeof path !== 'string' || !path) return Promise.resolve(null);
  const expires = new Date();
  expires.setHours(expires.getHours() + SIGNED_URL_HOURS);
  return bucket
    .file(path)
    .getSignedUrl({ action: 'read', expires })
    .then(([url]: [string]) => url)
    .catch((error: unknown) => {
      // A missing object (deleted clip, never-uploaded thumbnail) must degrade to
      // one absent tile, never a 500 for the whole page.
      console.warn('serveRecruitingProfile: could not sign', path, error);
      return null;
    });
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

function videoSection(clips: { url: string; poster: string | null; label: string }[]): string {
  if (clips.length === 0) return '';
  const [hero, ...rest] = clips;
  const heroHTML =
    `<div class="hero">` +
    `<video controls playsinline preload="metadata"${hero.poster ? ` poster="${esc(hero.poster)}"` : ''} src="${esc(hero.url)}"></video>` +
    (hero.label ? `<p class="cap">${esc(hero.label)}</p>` : '') +
    `</div>`;
  const grid =
    rest.length > 0
      ? `<div class="grid">` +
        rest
          .map(
            (c) =>
              `<div class="cell">` +
              `<video controls playsinline preload="none"${c.poster ? ` poster="${esc(c.poster)}"` : ''} src="${esc(c.url)}"></video>` +
              (c.label ? `<p class="cap">${esc(c.label)}</p>` : '') +
              `</div>`
          )
          .join('') +
        `</div>`
      : '';
  return `<section class="film">${heroHTML}${grid}</section>`;
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
.hero video{width:100%;border-radius:16px;background:#000;display:block}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:12px;margin-top:12px}
.cell video{width:100%;border-radius:12px;background:#000;display:block}
.cap{font-size:13px;color:var(--dim);margin:6px 2px 0}
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
<footer><a href="https://playerpath.net">PlayerPath</a></footer></div>`,
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
<footer><a href="https://playerpath.net">PlayerPath</a></footer></div>`,
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

/**
 * `/p/{token}/avatar` — the headshot, proxied.
 *
 * og:image used to be the signed URL itself, which dies within the hour while
 * link-unfurl caches (iMessage, Slack, Gmail) hold onto it — so a shared profile's
 * preview image broke on exactly the surface this feature grows through, and a
 * signed Storage URL ended up sitting in third-party cache infrastructure. This
 * URL is stable forever; the signed URL never leaves the function.
 */
async function serveAvatar(
  res: functions.Response,
  token: string
): Promise<void> {
  const profile = await loadPublishedProfile(token);
  const path = profile ? ownedPath(profile.data.headshotPath, profile.ownerUID) : null;
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

export const serveRecruitingProfile = functions.https.onRequest(async (req, res) => {
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
  // holds when the function URL is hit directly. `/p/{token}/avatar` adds one
  // trailing segment, so strip that before taking the last one.
  const segments = (req.path || '').split('/').filter(Boolean);
  const wantsAvatar = segments[segments.length - 1] === 'avatar';
  if (wantsAvatar) segments.pop();
  const token = segments[segments.length - 1] || '';

  if (!TOKEN_RE.test(token)) {
    if (wantsAvatar) {
      res.status(404).type('text/plain').send('Not found');
    } else {
      res.status(404).send(unavailablePage());
    }
    return;
  }

  try {
    if (wantsAvatar) {
      await serveAvatar(res, token);
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
    const signed = await Promise.all(
      rawHighlights.map(async (h) => {
        const [url, poster] = await Promise.all([
          signPath(bucket, ownedPath(h.videoStoragePath, ownerUID)),
          signPath(bucket, ownedPath(h.thumbnailStoragePath, ownerUID)),
        ]);
        return url ? { url, poster, label: typeof h.label === 'string' ? h.label : '' } : null;
      })
    );
    const clips = signed.filter(
      (c): c is { url: string; poster: string | null; label: string } => c !== null
    );
    // Film is the entire point of the page. If every clip failed to sign — the
    // usual cause being a missing signBlob IAM role rather than missing objects —
    // a 200 with a bio and no video is a silent failure dressed as success.
    if (rawHighlights.length > 0 && clips.length === 0) {
      console.error(
        'serveRecruitingProfile: every highlight failed to sign for',
        doc.id,
        '— check the signBlob IAM role on the runtime service account'
      );
      res.status(500).send(temporarilyUnavailablePage());
      return;
    }
    const headshot = await signPath(bucket, ownedPath(data.headshotPath, ownerUID));
    // The <img> gets the signed URL (same request, so it can't expire in time);
    // og:image gets the stable proxy, because unfurl caches outlive the signature.
    const ogImage = headshot ? `${PUBLIC_ORIGIN}/p/${encodeURIComponent(token)}/avatar` : null;

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
    const body = `<div class="wrap">
<header>
${headshot ? `<img class="shot" src="${esc(headshot)}" alt="${esc(name)}">` : ''}
<h1>${esc(name)}</h1>
${subline ? `<p class="sub">${esc(subline)}</p>` : ''}
${physical ? `<p class="meta">${esc(physical)}</p>` : ''}
${school ? `<p class="meta">${esc(school)}</p>` : ''}
</header>
${videoSection(clips)}
${golfSection(golf)}
${measurables ? `<section class="card"><h2>Measurables</h2>${measurables}<p class="note">Self-reported by the athlete.</p></section>` : ''}
${bio ? `<section class="card"><h2>About</h2><p class="bio">${esc(bio)}</p></section>` : ''}
${contactSection(data.contact)}
<footer>Game film recorded &amp; tagged in <a href="https://playerpath.net">PlayerPath</a></footer>
</div>`;

    const html = page({
      title: subline ? `${name} · ${subline}` : name,
      description,
      image: ogImage,
      body,
    });

    // Count real visits only. Awaited rather than fire-and-forget: the instance
    // can be frozen the moment the response flushes, which drops the write.
    // Never let the counter's failure cost the page, though — it's a vanity
    // metric and the film is what matters.
    const ua = String(req.headers['user-agent'] || '');
    if (req.method === 'GET' && !BOT_UA.test(ua)) {
      try {
        await doc.ref.update({
          viewCount: admin.firestore.FieldValue.increment(1),
          lastViewedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (error) {
        console.warn('serveRecruitingProfile: viewCount', error);
      }
    }

    res.status(200).send(html);
  } catch (error) {
    console.error('serveRecruitingProfile error:', error);
    if (res.headersSent) {
      res.end();
    } else if (wantsAvatar) {
      // Don't hand an unfurler an HTML page under an image content type.
      res.status(500).type('text/plain').send('Temporarily unavailable');
    } else {
      res.status(500).send(temporarilyUnavailablePage());
    }
  }
});
