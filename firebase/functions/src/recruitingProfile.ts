/**
 * Public recruiting-profile web page.
 *
 * Serves the athlete-facing product's one outward surface: a college coach opens
 * https://profiles.playerpath.net/p/{shareToken} in a browser — no account, no
 * app, no login — and watches the athlete's game film.
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

/** Share tokens are UUIDs. Reject anything else before it reaches Firestore. */
const TOKEN_RE = /^[A-Za-z0-9-]{8,64}$/;

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

export const serveRecruitingProfile = functions.https.onRequest(async (req, res) => {
  // Never cached: the CDN would freeze view counts and, worse, eventually serve
  // signed media URLs past their expiry.
  res.set('Cache-Control', 'no-store');
  res.set('Content-Type', 'text/html; charset=utf-8');

  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.status(405).send('Method Not Allowed');
    return;
  }

  // Hosting rewrites /p/** here; the token is the last path segment. Works the
  // same when the function URL is hit directly.
  const token = (req.path || '').split('/').filter(Boolean).pop() || '';
  if (!TOKEN_RE.test(token)) {
    res.status(404).send(unavailablePage());
    return;
  }

  try {
    const db = admin.firestore();
    // Single equality filter, then check isPublished in code: keeps this off the
    // composite-index path entirely (same shape as enforceStorageQuota).
    const snap = await db
      .collection('recruitingProfiles')
      .where('shareToken', '==', token)
      .limit(1)
      .get();

    if (snap.empty) {
      res.status(404).send(unavailablePage());
      return;
    }

    const doc = snap.docs[0];
    const data = doc.data() as Record<string, unknown>;
    if (data.isPublished !== true) {
      res.status(404).send(unavailablePage());
      return;
    }

    const ownerUID = typeof data.userId === 'string' ? data.userId : '';
    if (!ownerUID) {
      console.error('serveRecruitingProfile: profile has no userId', doc.id);
      res.status(404).send(unavailablePage());
      return;
    }

    // Publishing requires Pro, but rules only gate writes — cancelling a
    // subscription leaves isPublished:true untouched forever. Re-check at render
    // so the page actually tracks the entitlement it's sold as.
    const owner = await db.collection('users').doc(ownerUID).get();
    if (owner.get('subscriptionTier') !== 'pro') {
      res.status(404).send(unavailablePage());
      return;
    }

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
      res.status(500).send(unavailablePage());
      return;
    }
    const headshot = await signPath(bucket, ownedPath(data.headshotPath, ownerUID));

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
      image: headshot,
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
    res.status(500).send(unavailablePage());
  }
});
