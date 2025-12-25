# Coach Onboarding Fix

## Issue
Coaches were seeing the athlete onboarding flow and athlete dashboard after signup instead of the coach-specific onboarding and dashboard.

## Root Cause
The `ComprehensiveAuthManager` was not loading the user profile (including role) from Firestore when:
1. The app initialized with an already signed-in user
2. The auth state changed after signup

This meant that even though the coach role was correctly saved to Firestore during signup, the `userRole` property in `ComprehensiveAuthManager` was never updated from the default `.athlete` value.

## Fix Applied
Modified `ComprehensiveAuthManager.init()` to:
1. Load user profile from Firestore in the auth state listener (when user signs in)
2. Load user profile immediately if a user is already signed in when the app starts

### Changes Made in `ComprehensiveAuthManager.swift`

```swift
init() {
    currentFirebaseUser = Auth.auth().currentUser
    isSignedIn = currentFirebaseUser != nil
    authStateDidChangeListenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
        Task { @MainActor in
            self?.currentFirebaseUser = user
            self?.isSignedIn = user != nil
            // Reset new user flag when auth state changes (unless it's a signup)
            if user == nil {
                self?.isNewUser = false
            }
        }
        if user != nil {
            Task {
                await self?.ensureLocalUser()
                // ✅ ADDED: Load user profile from Firestore to get the role
                await self?.loadUserProfile()
            }
        }
    }
    
    // ✅ ADDED: Load profile for already signed-in users
    if currentFirebaseUser != nil {
        Task {
            await self.loadUserProfile()
        }
    }
}
```

## Flow After Fix

### Coach Signup Flow
1. User selects "Coach" role in signup form
2. `signUpAsCoach()` is called
3. Firebase auth account is created
4. User profile is created in Firestore with `role: "coach"`
5. `loadUserProfile()` is called, setting `authManager.userRole = .coach`
6. Auth state listener triggers, loading the profile again (redundant but safe)
7. `OnboardingFlow` checks `authManager.userRole` and shows `CoachOnboardingFlow`
8. After onboarding, `UserMainFlow` checks role and shows `CoachDashboardView`

### Coach Sign In Flow
1. User signs in with existing coach account
2. Auth state listener triggers
3. `loadUserProfile()` is called
4. User role is fetched from Firestore and set to `.coach`
5. `UserMainFlow` checks role and shows `CoachDashboardView` (skipping onboarding if already completed)

## Testing Checklist
- [ ] New coach signup shows coach onboarding
- [ ] After coach onboarding, coach sees CoachDashboardView with "My Athletes" tab
- [ ] Coach sign out and sign in returns to CoachDashboardView
- [ ] Athlete signup still shows athlete onboarding
- [ ] Athlete flow is unaffected

## Related Files
- `ComprehensiveAuthManager.swift` - Auth manager with role management
- `MainAppView.swift` - Contains `OnboardingFlow`, `CoachOnboardingFlow`, `UserMainFlow`
- `CoachDashboardView.swift` - Coach-specific dashboard
