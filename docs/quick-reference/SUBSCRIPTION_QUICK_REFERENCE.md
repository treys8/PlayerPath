# Subscription Management Quick Reference

## 🎯 For Users

### Accessing Subscriptions

**Athletes:**
1. Tap **"Profile"** tab (or "More")
2. Scroll to **"Account"** section
3. Tap **"Subscription"** or **"Upgrade to Premium"**

**Coaches:**
1. Tap **"Profile"** tab
2. Scroll to **"Account"** section  
3. Tap **"Subscription"**

### Subscription Plans

| Plan | Price | Features | Free Trial |
|------|-------|----------|------------|
| **Monthly** | $9.99/mo | All Premium Features | 7 days |
| **Annual** | $59.99/yr | All Premium Features | 7 days |

**Annual Savings:** 50% compared to monthly ($5/month equivalent)

### Premium Features

✅ **Unlimited Athletes** - Track as many players as you need  
✅ **Advanced Statistics** - Detailed analytics and performance trends  
✅ **Coach Sharing** - Share videos with coaches securely  
✅ **Cloud Backup** - Never lose your data  
✅ **Unlimited Videos** - Record and store unlimited clips  
✅ **Priority Support** - Get help faster  

### Free vs Premium Limits

| Feature | Free | Premium |
|---------|------|---------|
| Athletes | 3 | ∞ Unlimited |
| Videos | Basic | Unlimited |
| Statistics | Basic | Advanced |
| Coach Sharing | ❌ | ✅ |
| Cloud Backup | ❌ | ✅ |

---

## 🔧 For Developers

### Quick Code Snippets

#### Check if User is Premium
```swift
// Using StoreKitManager
@StateObject private var storeManager = StoreKitManager.shared

if storeManager.isPremium {
    // Show premium content
}

// Using User model
if user.isPremium {
    // Show premium content
}
```

#### Show Paywall
```swift
// For Athletes
@State private var showingPaywall = false

Button("Upgrade") {
    showingPaywall = true
}
.sheet(isPresented: $showingPaywall) {
    ImprovedPaywallView(user: user)
}

// For Coaches
.sheet(isPresented: $showingPaywall) {
    CoachPaywallView()
}
```

#### Gate a Feature
```swift
Button("Create Shared Folder") {
    if user.isPremium {
        // Show folder creation
    } else {
        // Show upgrade alert
        showPremiumAlert = true
    }
}
.alert("Premium Required", isPresented: $showPremiumAlert) {
    Button("Upgrade") { showingPaywall = true }
    Button("Cancel", role: .cancel) {}
}
```

#### Check Subscription Status
```swift
@StateObject private var storeManager = StoreKitManager.shared

// Current status
print(storeManager.subscriptionStatus)
// .active, .notSubscribed, .inGracePeriod, .expired

// Expiration date
if let expDate = storeManager.expirationDate {
    print("Expires: \(expDate)")
}
```

#### Manual Status Update
```swift
Task {
    await storeManager.updateSubscriptionStatus()
}
```

#### Restore Purchases
```swift
Button("Restore Purchases") {
    Task {
        await storeManager.restorePurchases()
    }
}
```

### StoreKit Configuration

**Product IDs:**
- Monthly: `com.playerpath.premium.monthly`
- Annual: `com.playerpath.premium.annual`

**Subscription Group:** `21513084`

**Testing File:** `PlayerPath.storekit`

### Environment Setup

**Debug Mode:**
```swift
// Uses PlayerPath.storekit for local testing
// Set in: Edit Scheme > Run > Options > StoreKit Configuration
```

**Sandbox Mode:**
```swift
// Uses real App Store sandbox
// Requires sandbox tester account from App Store Connect
```

**Production:**
```swift
// Uses real App Store
// Requires approved products in App Store Connect
```

### Common Integration Points

#### 1. Profile View
```swift
Section("Account") {
    NavigationLink(destination: SubscriptionView(user: user)) {
        if user.isPremium {
            Label("Subscription", systemImage: "crown.fill")
        } else {
            Label("Upgrade to Premium", systemImage: "crown")
        }
    }
}
```

#### 2. Feature Gate
```swift
// Shared Folders
if user.isPremium {
    NavigationLink("Shared Folders") { /* ... */ }
} else {
    Button {
        showPremiumAlert = true
    } label: {
        HStack {
            Label("Shared Folders", systemImage: "folder.badge.person.crop")
            Spacer()
            Text("Premium")
                .font(.caption)
                .foregroundColor(.yellow)
        }
    }
}
```

#### 3. Add Athlete Limit
```swift
private let freeAthleteLimit = 3

Button("Add Athlete") {
    if !user.isPremium && user.athletes.count >= freeAthleteLimit {
        showingPaywall = true
    } else {
        showingAddAthlete = true
    }
}
```

### Subscription State Machine

```
Not Subscribed
    ↓ (purchase with trial)
Active (7-day trial)
    ↓ (trial ends, payment succeeds)
Active (paid)
    ↓ (payment fails)
In Billing Retry
    ↓ (retry fails)
In Grace Period
    ↓ (grace period ends)
Expired
    ↓ (user re-subscribes)
Active
```

### Testing Commands

```bash
# View sandbox transactions (macOS only)
xcrun simctl --set simulator privacy grant photos com.yourcompany.PlayerPath

# Clear StoreKit test data
xcrun simctl --set simulator erase all

# Speed up subscriptions for testing
# In StoreKit config: subscription duration = 3 minutes for 1 month
```

### Firebase Sync

```swift
// After successful purchase
.onChange(of: storeManager.isPremium) { _, isPremium in
    if isPremium {
        // 1. Update local model
        user.isPremium = true
        try? modelContext.save()
        
        // 2. Sync to Firebase
        Task {
            await FirestoreManager.shared.updateUser(
                userID: authManager.userID ?? "",
                data: ["isPremium": true]
            )
        }
    }
}
```

### Error Handling

```swift
if let error = storeManager.error {
    switch error {
    case .productLoadFailed(let err):
        // Handle product loading error
    case .purchaseFailed(let err):
        // Handle purchase error
    case .restoreFailed(let err):
        // Handle restore error
    case .transactionVerificationFailed:
        // Handle verification error
    }
}
```

---

## 📊 Analytics Events to Track

Consider tracking these events:

- `paywall_viewed` - User saw the paywall
- `subscription_selected` - User selected a plan
- `purchase_initiated` - User tapped purchase button
- `purchase_completed` - Purchase succeeded
- `purchase_cancelled` - User cancelled
- `purchase_failed` - Purchase failed
- `trial_started` - Free trial began
- `trial_converted` - Trial converted to paid
- `subscription_renewed` - Auto-renewal succeeded
- `subscription_cancelled` - User cancelled
- `restore_initiated` - Restore purchases tapped

---

## 🔒 Security Checklist

- [ ] Never trust client-side subscription status alone
- [ ] Validate receipts server-side for sensitive features
- [ ] Use HTTPS for all API calls
- [ ] Store subscription data in secure backend
- [ ] Implement receipt refresh on app launch
- [ ] Handle expired subscriptions gracefully
- [ ] Protect premium content URLs
- [ ] Log suspicious activity

---

## 📞 Support Responses

**"How do I cancel my subscription?"**
> Your subscription is managed by Apple. To cancel:
> 1. Open Settings on your iPhone
> 2. Tap your name at the top
> 3. Tap "Subscriptions"
> 4. Tap "PlayerPath Premium"
> 5. Tap "Cancel Subscription"

**"How do I restore my purchase?"**
> In the app:
> 1. Go to Profile > Subscription
> 2. Tap "Restore Purchase"
> Your purchase will be restored if you previously subscribed with this Apple ID.

**"Can I get a refund?"**
> Refunds are handled by Apple. To request a refund:
> 1. Visit reportaproblem.apple.com
> 2. Sign in with your Apple ID
> 3. Find your PlayerPath purchase
> 4. Click "Report a Problem"
> 5. Follow the prompts

---

**Last Updated:** November 22, 2025
