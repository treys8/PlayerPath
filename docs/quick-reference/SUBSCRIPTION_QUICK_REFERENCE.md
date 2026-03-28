# Subscription Quick Reference

**Last Updated:** March 27, 2026

---

## Tier Structure

### Athlete Tiers

| Tier | Athletes | Storage | Coach Sharing | Stats Export |
|------|----------|---------|---------------|-------------|
| Free | 1 | 2 GB | No | No |
| Plus | 3 | 25 GB | No | CSV/PDF |
| Pro | 5 | 100 GB | Yes | CSV/PDF |

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
// Athlete: require Pro for coach sharing
if StoreKitManager.shared.currentTier >= .pro {
    // Allow shared folder creation
} else {
    showPaywall = true
}

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

### Coach Downgrade

`CoachDowngradeManager.shared` manages the flow:

| State | Behavior |
|-------|----------|
| `.none` | Under limit, no action |
| `.gracePeriod` | 7-day warning banner; coach can still operate normally |
| `.selectionRequired` | Grace period expired; full-screen selection view forces athlete deselection |

### Athlete Downgrade

`AthleteDowngradeManager.shared` detects Pro tier loss:
- Does NOT auto-revoke shared folder access
- Notifies coaches via `ActivityNotificationService`
- Access restores automatically on re-subscription

---

## Product IDs & Configuration

Defined in `SubscriptionModels.swift`. StoreKit config file: `PlayerPathStoreKit.storekit`.

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
4. Security rules use Firestore tier fields for access control

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
| `CoachDowngradeManager` | 7-day grace period, forced selection |
| `AthleteDowngradeManager` | Pro tier loss detection, coach notification |
| `FirestoreManager+UserProfile` | Tier sync to Firestore |

---

## Support Responses

**"How do I cancel?"**
> Settings > [Your Name] > Subscriptions > PlayerPath > Cancel Subscription

**"How do I restore?"**
> In the app: Profile > Subscription > Restore Purchase

**"Can I get a refund?"**
> Visit reportaproblem.apple.com, sign in, find your purchase, and submit a request.
