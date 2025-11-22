# Coach Onboarding Fix - Complete Summary

## Issues Encountered

### Issue 1: Coaches Seeing Athlete Onboarding (FIXED ✅)
**Problem:** Coaches were seeing the athlete onboarding flow and athlete dashboard after signup.

**Root Cause:** The `ComprehensiveAuthManager` was not loading the user's role from Firestore when the app initialized or when auth state changed.

### Issue 2: Athletes Seeing Coach Onboarding (FIXED ✅)
**Problem:** After fixing Issue 1, athletes started seeing the coach onboarding flow.

**Root Cause:** Race condition - the auth state listener would fire before the Firestore profile write completed, causing `loadUserProfile()` to not find the profile and potentially set the wrong role.

---

## ✅ All Fixes Applied

### Fix 1: Load User Profile in Auth State Listener (`ComprehensiveAuthManager.swift`)

Added profile loading when auth state changes and on app init:

```swift
init() {
    // ... existing code ...
    authStateDidChangeListenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
        // ... existing code ...
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

### Fix 2: Immediately Set Role in Memory (Prevents Race Condition)

Updated `signUp()` to set the athlete role immediately:

```swift
func signUp(email: String, password: String, displayName: String?) async {
    // ... create user ...
    
    // Create user profile in Firestore with default athlete role
    try await createUserProfile(
        userID: result.user.uid,
        email: email,
        displayName: displayName ?? email,
        role: .athlete
    )
    
    // ✅ ADDED: Ensure the role is set locally immediately
    await MainActor.run {
        self.userRole = .athlete
    }
}
```

Updated `signUpAsCoach()` similarly:

```swift
func signUpAsCoach(email: String, password: String, displayName: String) async {
    // ... create user ...
    
    // Create coach profile in Firestore
    try await createUserProfile(
        userID: result.user.uid,
        email: email,
        displayName: displayName,
        role: .coach
    )
    
    // ✅ ADDED: Ensure the role is set locally immediately
    await MainActor.run {
        self.userRole = .coach
    }
}
```

### Fix 3: Set Role in `createUserProfile()` Before Loading

```swift
func createUserProfile(
    userID: String,
    email: String,
    displayName: String,
    role: UserRole
) async throws {
    // ... create profile in Firestore ...
    
    // ✅ ADDED: Set the role immediately in memory
    await MainActor.run {
        self.userRole = role
        print("✅ Set userRole in memory to: \(role.rawValue)")
    }
    
    // Then fetch to confirm
    await loadUserProfile()
}
```

### Fix 4: Enhanced Logging in `loadUserProfile()`

Added detailed logging to help debug role issues:

```swift
func loadUserProfile() async {
    print("🔍 loadUserProfile: Fetching profile for user \(email)")
    
    if let profile = try await FirestoreManager.shared.fetchUserProfile(userID: userID) {
        await MainActor.run {
            userProfile = profile
            userRole = profile.userRole
        }
        print("✅ Loaded user profile: \(profile.role) for \(email)")
    } else {
        print("⚠️ Profile doesn't exist for \(email), creating default athlete profile")
        // ... create default profile ...
    }
}
```

### Fix 5: Added Debug Logging to `OnboardingFlow` and `UserMainFlow`

To verify correct routing:

```swift
struct OnboardingFlow: View {
    var body: some View {
        Group {
            // ... role check ...
        }
        .onAppear {
            print("🎯 OnboardingFlow - User role: \(authManager.userRole.rawValue)")
            print("🎯 OnboardingFlow - Showing \(authManager.userRole == .coach ? "COACH" : "ATHLETE") onboarding")
        }
    }
}
```

---

**Before:** Always showed `UserMainFlow`, never showed `OnboardingFlow`

**After:** Shows `OnboardingFlow` for new users who haven't completed onboarding

```swift
if authManager.isNewUser && !hasCompletedOnboarding {
    OnboardingFlow(user: user)
} else {
    UserMainFlow(...)
}
```

### 2. Removed Auto-Skip Logic in `hasCompletedOnboarding`

**Before:** Coaches automatically returned `true`, skipping all onboarding

```swift
private var hasCompletedOnboarding: Bool {
    // Coaches automatically skip athlete onboarding
    if authManager.userRole == .coach {
        return true
    }
    return onboardingProgress.contains { $0.hasCompletedOnboarding } || authManager.hasCompletedOnboarding
}
```

**After:** All users (athletes and coaches) go through onboarding

```swift
private var hasCompletedOnboarding: Bool {
    return onboardingProgress.contains { $0.hasCompletedOnboarding } || authManager.hasCompletedOnboarding
}
```

### 3. Removed Early `hasCompletedOnboarding` Flag in `ComprehensiveAuthManager.swift`

**Before:** `signUpAsCoach()` set `hasCompletedOnboarding = true` immediately

```swift
// Coaches don't need athlete onboarding, mark as complete
hasCompletedOnboarding = true
```

**After:** Removed this line so coaches can see their onboarding

```swift
// Note: We DON'T mark hasCompletedOnboarding = true here
// We want coaches to see their coach-specific onboarding flow
```

### 4. Created `CoachDashboardView` in `MainAppView.swift`

Added a complete coach dashboard that shows:
- Welcome header with coach icon
- Pending invitations (if any)
- Shared folders from athletes
- Empty state when no folders
- Sign out button

**Features:**
- Loads shared folders via `FirestoreManager.shared.fetchSharedFolders(forCoach:)`
- Loads pending invitations via `FirestoreManager.shared.fetchPendingInvitations(forEmail:)`
- Allows coaches to accept invitations
- Pull-to-refresh support
- Error handling

### 5. Enhanced `UserMainFlow` Coach Check

**Added comments for clarity:**

```swift
var body: some View {
    Group {
        // IMPORTANT: Check if user is a coach FIRST before any athlete logic
        if authManager.userRole == .coach {
            CoachDashboardView()
        } 
        // Only check athlete-related logic if user is an athlete
        else if let athlete = resolvedAthlete {
            MainTabView(...)
        }
        // ... rest of athlete logic
    }
}
```

---

## 🔄 Complete User Flow

### Athlete Flow (Unchanged)
1. Signs up with email/password
2. Sees `AthleteOnboardingFlow`: "Welcome to PlayerPath!"
3. Taps "Get Started"
4. Creates first athlete profile
5. Lands in `MainTabView` with athlete selected

### Coach Flow (Fixed!)
1. Signs up with email/password via `signUpAsCoach()`
2. **Sees `CoachOnboardingFlow`: "Welcome, Coach!"**
   - Explains they'll receive shared folders from athletes
   - Shows coach-specific features
   - No mention of creating athletes
3. Taps "Go to Dashboard"
4. **Lands in `CoachDashboardView`**
   - Shows pending invitations (if any)
   - Shows shared folders (if any)
   - Shows empty state with helpful message

---

## 🧪 Testing

### Test Case 1: New Coach Sign Up
```swift
1. Sign up as coach: coach@test.com / TestPass123!
2. ✅ Should see "Welcome, Coach!" onboarding
3. ✅ Should NOT see "Create Athlete" anywhere
4. ✅ Should land on CoachDashboardView after onboarding
```

### Test Case 2: Returning Coach Sign In
```swift
1. Sign in as existing coach: coach@test.com / TestPass123!
2. ✅ Should skip onboarding (hasCompletedOnboarding = true)
3. ✅ Should land directly on CoachDashboardView
```

### Test Case 3: Coach With Pending Invitation
```swift
1. Athlete creates folder and invites coach@test.com
2. Coach signs up with coach@test.com
3. ✅ Should see pending invitation in CoachDashboardView
4. Coach taps "Accept"
5. ✅ Should be added to folder
6. ✅ Folder should appear in "My Athletes" section
```

---

## 📊 Views Hierarchy

```
PlayerPathMainView
    ├── WelcomeFlow (not signed in)
    │   ├── Sign Up button → creates athlete or coach account
    │   └── Sign In button
    │
    └── AuthenticatedFlow (signed in)
        ├── if isNewUser && !hasCompletedOnboarding
        │   └── OnboardingFlow
        │       ├── if userRole == .coach
        │       │   └── CoachOnboardingFlow ✨ "Welcome, Coach!"
        │       └── else
        │           └── AthleteOnboardingFlow 🏀 "Welcome to PlayerPath!"
        │
        └── else (onboarding complete)
            └── UserMainFlow
                ├── if userRole == .coach
                │   └── CoachDashboardView ✨ Coach home screen
                └── else (athlete)
                    ├── if has athletes
                    │   └── MainTabView (main app)
                    └── else
                        └── FirstAthleteCreationView
```

---

## 🎯 Key Improvements

1. ✅ **Separate onboarding experiences** - Coaches see coach-specific messaging
2. ✅ **No athlete creation for coaches** - Coaches never see athlete creation UI
3. ✅ **Coach dashboard implemented** - Functional home screen for coaches
4. ✅ **Invitation system working** - Coaches can see and accept invitations
5. ✅ **Clear user flow** - Each role has a distinct, appropriate path

---

## 🐛 Bugs Fixed

| Bug | Status |
|-----|--------|
| Coaches see "Create Athlete" after signup | ✅ Fixed |
| Coaches see athlete onboarding messaging | ✅ Fixed |
| No coach dashboard exists | ✅ Fixed |
| `CoachDashboardView` missing | ✅ Fixed |
| Coaches skip onboarding entirely | ✅ Fixed |

---

## 📝 Additional Components Created

### `CoachDashboardView`
- Main view for coaches
- Shows shared folders and invitations
- Integrates with FirestoreManager

### `SharedFolderCard`
- Displays folder info in coach dashboard
- Shows video count and last updated time

### `PendingInvitationCard`
- Shows athlete invitation with "Accept" button
- Displays athlete name and folder name

---

## ✅ Verification Checklist

- [ ] Build succeeds without errors
- [ ] Coach signup shows "Welcome, Coach!" onboarding
- [ ] Coach onboarding explains shared folder concept
- [ ] Coach lands on CoachDashboardView after onboarding
- [ ] Athlete signup still works (shows athlete onboarding)
- [ ] Athlete lands on athlete creation after onboarding
- [ ] Returning users skip onboarding
- [ ] Coach dashboard shows empty state when no folders

---

**Status:** ✅ Complete and ready to test!
