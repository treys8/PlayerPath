# StoreKit 2 Integration Setup Guide

## Overview
PlayerPath now includes a complete StoreKit 2 integration for in-app purchases and subscriptions. This guide will help you configure everything needed to test and deploy the subscription system.

## Files Created

### 1. **StoreKitManager.swift**
- Manages all StoreKit 2 operations
- Handles product loading, purchases, and subscription status
- Listens for transaction updates
- Verifies transactions for security

### 2. **ImprovedPaywallView.swift**
- Modern paywall UI with real StoreKit integration
- Shows subscription options (Monthly & Annual)
- Handles purchase flow and errors
- Updates user premium status automatically

### 3. **PlayerPath.storekit**
- StoreKit Configuration File for local testing
- Defines two subscription products:
  - Monthly Premium: $9.99/month (7-day free trial)
  - Annual Premium: $59.99/year (7-day free trial)

### 4. **Updated Files**
- **ProfileView.swift**: Now uses `ImprovedPaywallView`
- **CoachProfileView.swift**: Updated with StoreKit-powered `CoachPaywallView`

## Setup Instructions

### Step 1: Configure Xcode Project

1. **Add StoreKit Configuration File**
   - In Xcode, go to your project target
   - Select "Signing & Capabilities"
   - Click "+ Capability" and add "In-App Purchase"
   - The `PlayerPath.storekit` file should now be available for testing

2. **Set Active StoreKit Configuration**
   - In Xcode, go to Product > Scheme > Edit Scheme
   - Select "Run" on the left
   - Go to "Options" tab
   - Under "StoreKit Configuration", select `PlayerPath.storekit`
   - This enables local testing without App Store Connect

### Step 2: Configure App Store Connect

1. **Create Subscription Group**
   - Log in to App Store Connect
   - Go to your app > Features > In-App Purchases
   - Create a new Subscription Group with ID: `21513084`
   - Name it "PlayerPath Premium"

2. **Create Subscription Products**
   
   **Monthly Premium:**
   - Product ID: `com.playerpath.premium.monthly`
   - Reference Name: PlayerPath Premium Monthly
   - Duration: 1 month
   - Price: $9.99
   - Introductory Offer: 7 days free trial
   
   **Annual Premium:**
   - Product ID: `com.playerpath.premium.annual`
   - Reference Name: PlayerPath Premium Annual
   - Duration: 1 year
   - Price: $59.99
   - Introductory Offer: 7 days free trial

3. **Configure Localizations**
   - Add English (US) localization
   - Display Name: "PlayerPath Premium Monthly" / "Annual"
   - Description: "Premium features with unlimited athletes, advanced analytics, and cloud backup"

### Step 3: Testing in Xcode

With the StoreKit Configuration file, you can test purchases locally:

1. **Run the app in simulator or device**
2. **Navigate to Profile > Subscription**
3. **Select a subscription plan**
4. **Tap "Start 7-Day Free Trial"**
5. **StoreKit will show a fake purchase sheet**
6. **Approve the purchase**
7. **The app should now show Premium features**

**Testing Features:**
- ✅ Product loading
- ✅ Purchase flow
- ✅ Free trial
- ✅ Subscription status
- ✅ Restore purchases
- ✅ Auto-renewal (simulated)

### Step 4: Sandbox Testing

Before production, test with real App Store sandbox:

1. **Create Sandbox Tester**
   - App Store Connect > Users and Access > Sandbox Testers
   - Create a new tester account

2. **Sign Out of Real Apple ID**
   - On test device: Settings > App Store > Sign Out
   - DO NOT sign in with sandbox account here

3. **Test Purchase Flow**
   - Run the app from Xcode on device
   - Attempt a purchase
   - When prompted, sign in with sandbox tester
   - Complete purchase flow

### Step 5: Syncing Premium Status

The current implementation updates the local `User` model. You'll want to sync this with your backend:

**In `ImprovedPaywallView.swift`, update the `onChange` handler:**

```swift
.onChange(of: storeManager.isPremium) { _, isPremium in
    if isPremium {
        // Update user model
        user.isPremium = true
        try? modelContext.save()
        
        // TODO: Sync with Firebase
        Task {
            await FirebaseManager.shared.updateUserPremiumStatus(
                userID: authManager.userID,
                isPremium: true
            )
        }
        
        // Dismiss after short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            dismiss()
        }
    }
}
```

### Step 6: Server-Side Receipt Validation (Recommended)

For production, validate receipts server-side:

1. **Set up a server endpoint** to verify App Store receipts
2. **Send transaction info** from the app to your server
3. **Validate with Apple's verifyReceipt API**
4. **Update Firebase user premium status** from server

**Security Best Practice:**
Never trust client-side subscription status alone. Always verify transactions server-side before granting premium features.

## Architecture Overview

### StoreKitManager Flow

```
App Launch
    ↓
StoreKitManager.shared initializes
    ↓
Loads products from App Store
    ↓
Listens for transaction updates
    ↓
Updates subscription status
```

### Purchase Flow

```
User taps "Start Free Trial"
    ↓
StoreKitManager.purchase(product)
    ↓
StoreKit presents purchase sheet
    ↓
User approves
    ↓
Transaction verified
    ↓
Subscription status updated
    ↓
User.isPremium = true
    ↓
Premium features unlocked
```

### Transaction Listening

```
Background transaction occurs
    ↓
Transaction.updates receives event
    ↓
Verify transaction
    ↓
Update subscription status
    ↓
Finish transaction
    ↓
UI automatically updates via @Published
```

## Product IDs Reference

Update these if you use different product IDs:

**In `StoreKitManager.swift`:**
```swift
enum SubscriptionProduct: String, CaseIterable {
    case monthlyPremium = "com.playerpath.premium.monthly"  // Change this
    case annualPremium = "com.playerpath.premium.annual"    // Change this
}
```

## Premium Feature Gating

To gate features behind premium:

```swift
// Check if user has premium
if storeManager.isPremium {
    // Show premium feature
} else {
    // Show upgrade prompt
}

// Or use User model
if user.isPremium {
    // Show premium feature
}
```

## Error Handling

The system handles these error cases:
- ✅ Network failures when loading products
- ✅ User cancellation
- ✅ Purchase failures
- ✅ Transaction verification failures
- ✅ Restore purchase errors

Errors are displayed via alerts in the paywall view.

## Testing Checklist

- [ ] Products load correctly
- [ ] Monthly subscription displays correct price
- [ ] Annual subscription displays correct price
- [ ] Free trial shows in subscription details
- [ ] Purchase completes successfully
- [ ] Premium features unlock after purchase
- [ ] Restore purchases works
- [ ] Subscription status persists across app launches
- [ ] Subscription auto-renews (sandbox)
- [ ] Subscription cancellation works
- [ ] Grace period handling
- [ ] Billing retry handling

## Production Deployment

Before submitting to App Store:

1. ✅ Create products in App Store Connect
2. ✅ Submit products for review
3. ✅ Products must be "Ready to Submit"
4. ✅ Test with sandbox accounts
5. ✅ Implement server-side receipt validation
6. ✅ Add Terms of Service & Privacy Policy links
7. ✅ Configure subscription management URL
8. ✅ Test on multiple devices and iOS versions

## Support & Troubleshooting

### Products Not Loading
- Check product IDs match exactly
- Ensure App Store Connect products are approved
- Verify in-app purchase capability is enabled
- Check network connectivity

### Purchase Fails
- Check sandbox tester is valid
- Verify device/simulator can make purchases
- Check for parental controls
- Ensure product is available in user's region

### Subscription Status Not Updating
- Check Transaction.updates listener is active
- Verify transaction verification succeeds
- Check for @MainActor warnings
- Ensure app has network access

## Future Enhancements

Consider adding:
- [ ] Promotional offers
- [ ] Subscription offer codes
- [ ] Family Sharing support
- [ ] Subscription status badges in UI
- [ ] Upgrade/downgrade between plans
- [ ] Cancellation flow improvements
- [ ] Refund request handling
- [ ] Analytics for conversion tracking

## Resources

- [StoreKit 2 Documentation](https://developer.apple.com/documentation/storekit)
- [App Store Server API](https://developer.apple.com/documentation/appstoreserverapi)
- [Receipt Validation Guide](https://developer.apple.com/documentation/storekit/original_api_for_in-app_purchase/validating_receipts_with_the_app_store)
- [In-App Purchase Best Practices](https://developer.apple.com/app-store/in-app-purchase/)

---

**Created:** November 22, 2025  
**Last Updated:** November 22, 2025  
**Version:** 1.0
