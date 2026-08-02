# Cloud Monitoring alerts

## The problem with the "Cloud Function Errors" policy

The current policy alerts on the metric
`cloudfunctions.googleapis.com/function/execution_count` filtered to `status = error`,
firing when the count exceeds **5**.

**That `status` label cannot tell a dead link from a crash.** For an HTTP-triggered
function it is coarse — any non-2xx response counts as `error`, so a `404` scores
identically to a `500`.

That is fine for most functions. It is actively wrong for **`serveRecruitingProfile`**,
where a 404 is not a fault but the *designed* response to a long list of ordinary
situations:

- the athlete unpublished their profile (the kill switch)
- **Reset Link** was used — the entire point of that feature is that the old URL 404s
- the owner's Pro subscription lapsed, and the per-render tier re-check took the page down
- the athlete was deleted
- a bot or scanner walked `/p/` paths
- anyone typo'd a share link

So once the recruiting feature has real traffic, this policy fires because a college
coach opened a stale link. The cost is not the email — it is that the one signal worth
waking up for, the function actually failing, ends up buried in noise you have learned
to swipe away.

> Historical note: the policy first fired on 2026-07-26 at 14:05 UTC during
> post-deploy verification, when 18 deliberately-bogus tokens were probed to confirm the
> N2 share-slug parser. All 18 returned 404; none was a failure.

## The fix: alert on logs, not on status codes

**No code change is required.** `serveRecruitingProfile` already logs at exactly the
right severities, and this must stay true — see the invariant below.

| Situation | Logs | Severity |
|---|---|---|
| Bad/unknown token → 404 | *nothing* | — |
| Unpublished / lapsed / deleted → 404 | *nothing* | — |
| Highlight path rejected by `ownedPath` | `console.warn` | WARNING |
| Avatar/poster stream failed | `console.warn` | WARNING |
| View-analytics write failed | `console.warn` | WARNING |
| Signing failed → 500 | `console.error` | ERROR |
| Unhandled throw → 500 | `console.error` | ERROR |
| `recruitingViewDigest` scan/digest deadline hit | `console.error` | ERROR |

Because every 404 path is silent, a **log-based metric on `severity>=ERROR` is already
clean** — it sees only the two 500 paths and the digest's data-loss warnings.

### Console recipe

1. **Logging → Log-based Metrics → Create metric**
   - Type: **Counter**
   - Name: `function_errors`
   - Filter:
     ```
     resource.type="cloud_function"
     severity>=ERROR
     ```
     Add `resource.labels.function_name="serveRecruitingProfile"` to scope it to one
     function; leave it off for a project-wide error signal (recommended — the digest's
     deadline `console.error`s are worth catching too, and they are on a different
     function).

2. **Monitoring → Alerting → Edit "Cloud Function Errors"**
   - Repoint the condition at `logging.googleapis.com/user/function_errors`.
   - Threshold: **above 0**, rolling window **5 min**. Unlike the old metric, one hit
     here is genuinely worth reading — these are real failures, not stale bookmarks.

3. Keep the old execution-count condition only if you want a **volume/cost** signal, and
   if so rename it so nobody reads it as an error alert.

## ⚠️ Invariant this depends on

**A 404 path in `serveRecruitingProfile` must never log at ERROR, and a genuine failure
must never be downgraded to `warn`.** The alerting above has no other way to tell them
apart — the HTTP status is not visible to a log-based metric. If you add a new bail-out
branch, match the table: silent for "this link isn't valid", `console.error` for "we
could not serve a page we should have been able to serve".

Related: [`RECRUITING_PROFILE_REVIEW_2026-07-25.md`](../RECRUITING_PROFILE_REVIEW_2026-07-25.md) §0.
