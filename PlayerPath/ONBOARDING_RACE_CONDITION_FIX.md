# Onboarding Race Condition - Final Fix

## Problem
Both athletes and coaches were experiencing incorrect onboarding flows. Users would see the wrong onboarding screen, or skip onboarding entirely.

## Root Cause Analysis

### The Race Condition
When a user signs up, multiple async operations happen simultaneously:

```
1. signUp() or signUpAsCoach() starts
   ├─ Sets isNewUser = true
   ├─ Creates Firebase auth account
   ├─ Sets isSignedIn = true
   │  └─ ⚡ TRIGGERS AUTH STATE LISTENER
   ├─ Creates Firestore profile with role
   ├─ Sets userRole in memory
   └─ Calls loadUserProfile() to verify

2. Auth State Listener fires (in parallel!)
   ├─ Sees user is signed in
   ├─ Calls ensureLocalUser()
   └─ Calls loadUserProfile() ❌
      └─ Profile might not exist yet in Firestore
         └─ Creates ANOTHER profile with default .athlete role
            └─ Overwrites the correct role!
```

### Why This Caused Issues

1. **Auth listener interference**: The auth state listener would call `loadUserProfile()` before the signup method finished creating the profile
2. **Firestore latency**: Even after writing to Firestore, reads might not immediately see the new data
3. **Double profile creation**: `loadUserProfile()` would think no profile exists and create a default athlete profile
4. **Role overwriting**: The correct role set during signup would be overwritten by the default athlete role

## Solutions Applied

### 1. Skip Auth Listener Profile Load for New Users

**File**: `ComprehensiveAuthManager.swift` - `init()`

```swift
authStateDidChangeListenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
    // ... existing code ...
    if user != nil {
        Task {
            await self?.ensureLocalUser()
            // ✅ Only load profile if this isn't a brand new signup
            if await self?.isNewUser == false {
                print("🔍 Auth state changed - Loading profile for existing user")
                await self?.loadUserProfile()
            } else {
                print("⏭️ Auth state changed - Skipping profile load for new user")
            }
        }
    }
}
```

**Why**: Prevents the auth state listener from interfering with signup's profile creation.

### 2. Set Role Immediately in Memory (Multiple Layers)

**File**: `ComprehensiveAuthManager.swift`

#### In `signUp()`:
```swift
// Create athlete profile
try await createUserProfile(..., role: .athlete)

// ✅ Set role immediately in memory
await MainActor.run {
    self.userRole = .athlete
}
```

#### In `signUpAsCoach()`:
```swift
// Create coach profile
try await createUserProfile(..., role: .coach)

// ✅ Set role immediately in memory
await MainActor.run {
    self.userRole = .coach
}
```

#### In `createUserProfile()`:
```swift
// Write to Firestore
try await FirestoreManager.shared.updateUserProfile(...)

// ✅ Set in memory before even verifying
await MainActor.run {
    self.userRole = role
}
```

**Why**: Ensures the role is correct immediately, not dependent on Firestore reads.

### 3. Add Delay Before Verification

**File**: `ComprehensiveAuthManager.swift` - `createUserProfile()`

```swift
// Set role in memory immediately
await MainActor.run {
    self.userRole = role
}

// ✅ Wait for Firestore to propagate
try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

// Then verify
await loadUserProfile()
```

**Why**: Gives Firestore time to propagate the write before we try to read it back.

### 4. Don't Create Duplicate Profiles for New Users

**File**: `ComprehensiveAuthManager.swift` - `loadUserProfile()`

```swift
if let profile = try await FirestoreManager.shared.fetchUserProfile(userID: userID) {
    // Profile found - use it
    userRole = profile.userRole
} else {
    // ✅ Only create default profile for EXISTING users (not new signups)
    if !isNewUser {
        print("⚠️ Profile doesn't exist for existing user, creating default")
        try await createUserProfile(..., role: .athlete)
    } else {
        print("⚠️ Profile not found for new user, keeping existing role: \(userRole.rawValue)")
    }
}
```

**Why**: If the profile isn't found for a new user, it's because of Firestore latency - we already created it. Don't create another one!

### 5. Enhanced Debug Logging

Added detailed logging at every step:
- Profile creation
- Role setting
- Profile loading
- Onboarding flow selection
- User main flow routing

**Why**: Makes it easy to diagnose any remaining issues.

## Flow After Fix

### Athlete Signup
```
1. User clicks "Sign Up" → selects "Athlete"
2. signUp() called
   ├─ Sets isNewUser = true
   ├─ Creates Firebase auth ✅
   ├─ Sets isSignedIn = true
   │  └─ Auth listener fires
   │     └─ Sees isNewUser = true
   │        └─ Skips loadUserProfile() ✅
   ├─ Creates profile in Firestore with role: .athlete
   ├─ Sets userRole = .athlete in memory ✅
   └─ Verifies profile after 0.5s delay ✅

3. AuthenticatedFlow checks:
   ├─ isNewUser = true ✅
   ├─ hasCompletedOnboarding = false ✅
   └─ Shows OnboardingFlow

4. OnboardingFlow checks:
   ├─ userRole = .athlete ✅
   └─ Shows AthleteOnboardingFlow ✅

5. User completes onboarding
   ├─ Sets hasCompletedOnboarding = true
   └─ Shows FirstAthleteCreationView ✅
```

### Coach Signup
```
1. User clicks "Sign Up" → selects "Coach"
2. signUpAsCoach() called
   ├─ Sets isNewUser = true
   ├─ Creates Firebase auth ✅
   ├─ Sets isSignedIn = true
   │  └─ Auth listener fires
   │     └─ Sees isNewUser = true
   │        └─ Skips loadUserProfile() ✅
   ├─ Creates profile in Firestore with role: .coach
   ├─ Sets userRole = .coach in memory ✅
   └─ Verifies profile after 0.5s delay ✅

3. AuthenticatedFlow checks:
   ├─ isNewUser = true ✅
   ├─ hasCompletedOnboarding = false ✅
   └─ Shows OnboardingFlow

4. OnboardingFlow checks:
   ├─ userRole = .coach ✅
   └─ Shows CoachOnboardingFlow ✅

5. User completes onboarding
   ├─ Sets hasCompletedOnboarding = true
   └─ Shows CoachDashboardView ✅
```

## Testing Checklist

- [ ] New athlete signup shows AthleteOnboardingFlow
- [ ] New coach signup shows CoachOnboardingFlow
- [ ] Athletes land on athlete creation after onboarding
- [ ] Coaches land on CoachDashboardView after onboarding
- [ ] Sign out and sign in works for both roles
- [ ] Console logs show correct role at each step
- [ ] No duplicate profiles created in Firestore

## Debug Console Output (Expected)

### Athlete Signup
```
🔵 Creating athlete profile for: athlete@test.com
🔵 Creating user profile in Firestore - Role: athlete, Email: athlete@test.com
✅ Set userRole in memory to: athlete
⏭️ Auth state changed - Skipping profile load for new user (already handled in signup)
🔍 loadUserProfile: Fetching profile for user athlete@test.com
✅ Loaded user profile: athlete for athlete@test.com
🎯 AuthenticatedFlow - isNewUser: true, hasCompletedOnboarding: false, userRole: athlete
🎯 OnboardingFlow - User role: athlete
🎯 OnboardingFlow - Showing ATHLETE onboarding
```

### Coach Signup
```
🔵 Creating coach profile for: coach@test.com
🔵 Creating user profile in Firestore - Role: coach, Email: coach@test.com
✅ Set userRole in memory to: coach
⏭️ Auth state changed - Skipping profile load for new user (already handled in signup)
🔍 loadUserProfile: Fetching profile for user coach@test.com
✅ Loaded user profile: coach for coach@test.com
🎯 AuthenticatedFlow - isNewUser: true, hasCompletedOnboarding: false, userRole: coach
🎯 OnboardingFlow - User role: coach
🎯 OnboardingFlow - Showing COACH onboarding
```

## Key Takeaways

1. **Never rely on Firestore reads during signup** - Set values in memory immediately
2. **Prevent race conditions with guards** - Check if it's a new user before loading profile
3. **Account for propagation delays** - Add small delays before verification reads
4. **Don't create duplicate profiles** - Check if it's a signup before creating defaults
5. **Log everything** - Detailed logging makes debugging async issues much easier

---

**Status**: ✅ Ready to test! Both athlete and coach onboarding should now work correctly.
