# Subscription Quick Reference

**Last Updated:** June 24, 2026

---

## Tier Structure

### Athlete Tiers

| Tier | Athletes | Storage | Coach Sharing | Stats Export |
|------|----------|---------|---------------|-------------|
| Free | 1 | 2 GB | Yes | No |
| Plus | 3 | 25 GB | Yes | CSV/PDF |
| Pro | 5 | 100 GB | Yes | CSV/PDF |

**Pricing Model V2 (shipped June 2026):** coach connections are paid by the **coach's seat**, not the athlete's tier. Any athlete tier (Free/Plus/Pro) can create shared folders and keep coaches connected. There is no athlete-tier gate on coach sharing.

### Coach Tiers

| Tier | Athletes | Sessions |
|------|----------|----------|
| Free | 2 | Yes |
| Instructor | 10 | Yes |
| Pro Instructor | 30 | Yes |
| Academy | Unlimited | Yes (manual Firestore grant) |

---

## Key APIs

### Check Tier

```swift
// Athlete tier
let tier = StoreKitManager.shared.currentTier  // .free, .plus, .pro
let expiry = StoreKitManager.shared.tierExpirationDate

// Coach tier
let coachTier = StoreKitManager.shared.currentCoachTier  // .free, .instructor, .proInstructor, .academy
let coachExpiry = StoreKitManager.shared.coachTierExpirationDate

// Entitlements resolved (prevents stale sync)
let ready = StoreKitManager.shared.hasResolvedEntitlements
```

### Gate a Feature

```swift
// Coach: check athlete limit
if SubscriptionGate.isCoachOverLimit(coachID: id, folders: folders, invitations: invitations) {
    showCoachPaywall = true
}

// Coach: remaining slots
let remaining = SubscriptionGate.coachAthleteSlotsRemaining(
    coachID: id, folders: folders, invitations: invitations
)
```

### Show Paywall

```swift
// Athlete paywall
.sheet(isPresented: $showPaywall) {
    ImprovedPaywallView(user: user)
}

// Coach paywall
.sheet(isPresented: $showCoachPaywall) {
    CoachPaywallView()
}

// Global paywall (from anywhere via NotificationCenter)
NotificationCenter.default.post(name: .showSubscriptionPaywall, object: nil)
```

### Restore Purchases

```swift
Task {
    await StoreKitManager.shared.restorePurchases()
}
```

---

## Downgrade Handling

Under **Pricing Model V2** the coach pays for each connected athlete seat, so downgrade
enforcement lives entirely on the **coach** side. Athlete tier changes no longer touch coach
access.

### Coach Downgrade (client shed flow)

`CoachDowngradeManager.shared` manages the flow when a coach drops below their connected
athlete count:

| State | Behavior |
|-------|----------|
| `.none` | Under limit, no action |
| `.gracePeriod` | 7-day warning banner; coach can still operate normally |
| `.selectionRequired` | Grace period expired; `CoachDowngradeSelectionView` forces athlete deselection |

When the coach selects which athletes to shed, `FirestoreManager.batchRevokeCoachAccess`
removes them from the over-limit folders.

### Server backstop

A coach who never runs the client shed flow is still enforced server-side:

- `auditCoachDowngrades` — daily Cloud Function cron that detects over-limit coaches
- CF-managed `downgradeUnresolved` / `coachDowngradeGraceStartedAt` fields on `users/{id}`
- Security rules **block coach feedback writes** (comments/annotations) once a coach is over
  limit — "block feedback, allow viewing" (the coach can still view, just not deliver feedback)

---

## Product IDs & Configuration

Defined in `SubscriptionModels.swift`. StoreKit config file: `PlayerPath/PlayerPathStoreKit.storekit`.

### Testing

```
Debug:      Uses PlayerPathStoreKit.storekit (local testing)
Sandbox:    Real App Store sandbox (requires tester account)
Production: Real App Store
```

Set StoreKit config in: Edit Scheme > Run > Options > StoreKit Configuration.

---

## Tier Sync to Firebase

1. `StoreKitManager` resolves entitlements from App Store receipts
2. Calls `FirestoreManager.shared.syncSubscriptionTiers()` to update Firestore `users/{id}`
3. `syncSubscriptionTier` Cloud Function validates server-side
4. The `appStoreServerNotifications` Cloud Function (App Store Server Notifications V2 webhook)
   receives Apple-pushed subscription lifecycle events (renew/expire/refund) and keeps the
   server tier in sync even when the app is not open
5. Security rules use Firestore tier fields for access control

Important: `hasResolvedEntitlements` must be `true` before syncing to prevent stale writes.

---

## Subscription State Machine

```
Not Subscribed
  | (purchase / with optional trial)
Active (trial or paid)
  | (payment fails)
Billing Retry (isInBillingRetryPeriod)
  | (retry fails)
Grace Period
  | (grace period ends)
Expired
  | (user re-subscribes)
Active
```

---

## Key Services

| Service | Purpose |
|---------|---------|
| `StoreKitManager` | StoreKit 2 entitlements, purchase flow, tier resolution |
| `SubscriptionGateService` | Coach athlete limit enforcement |
| `CoachDowngradeManager` | 7-day grace period, forced selection (client shed flow) |
| `FirestoreManager+UserProfile` | Tier sync to Firestore |

---

## Support Responses

**"How do I cancel?"**
> Settings > [Your Name] > Subscriptions > PlayerPath > Cancel Subscription

**"How do I restore?"**
> In the app: Profile > Subscription > Restore Purchase

**"Can I get a refund?"**
> Visit reportaproblem.apple.com, sign in, find your purchase, and submit a request.
