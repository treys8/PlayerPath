# Onboarding Flows - Complete Guide

## Overview

PlayerPath has **two completely different onboarding experiences** based on user role:
- **Athletes** see athlete-focused onboarding
- **Coaches** see coach-focused onboarding

## Flow Architecture

```
Sign Up Screen (SignInView.swift)
    ↓
User Selects Role: [Athlete] or [Coach]
    ↓
    ├─→ Athlete Selected
    │   ├─→ authManager.signUp() called
    │   ├─→ Firestore profile created with role: "athlete"
    │   ├─→ AthleteOnboardingFlow shown
    │   │   • Orange/Yellow wave icon
    │   │   • "Welcome to PlayerPath!"
    │   │   • Shows: Create Profiles, Record Videos, Track Stats
    │   │   • Button: "Get Started"
    │   ├─→ First Athlete Creation View
    │   └─→ MainTabView (Home, Videos, Stats, Profile)
    │
    └─→ Coach Selected
        ├─→ authManager.signUpAsCoach() called
        ├─→ Firestore profile created with role: "coach"
        ├─→ CoachOnboardingFlow shown
        │   • Blue/Purple coach icon
        │   • "Welcome, Coach!"
        │   • Shows: Shared Folders, Upload Videos, Annotate, Manage Athletes
        │   • Info box about folder sharing
        │   • Button: "Go to Dashboard"
        └─→ CoachDashboardView (My Athletes, Profile)
```

## Visual Differences

### Athlete Onboarding (AthleteOnboardingFlow)

**Visual Indicators:**
- 🔵 Blue badge at top: "ATHLETE ACCOUNT"
- 👋 Orange/Yellow gradient hand wave icon
- "Welcome to PlayerPath!" heading
- Athlete-centric feature list

**Features Highlighted:**
1. 👤 Create Athlete Profiles
2. 📹 Record & Analyze
3. 📊 Track Statistics
4. 🔄 Sync Everywhere

**Call to Action:** "Get Started" → Creates first athlete profile

---

### Coach Onboarding (CoachOnboardingFlow)

**Visual Indicators:**
- 🟢 Green badge at top: "COACH ACCOUNT"
- 👥 Blue/Purple gradient coach icon
- "Welcome, Coach!" heading
- Coach-centric feature list

**Features Highlighted:**
1. 📁 Access Shared Folders
2. 🎥 Upload & Review Videos
3. 💬 Annotate & Comment
4. 👥 Manage Multiple Athletes

**Info Box:** Explains how athletes share folders via email

**Call to Action:** "Go to Dashboard" → Opens coach dashboard

## Implementation Details

### 1. Role Selection (SignInView.swift)

```swift
if isSignUp {
    RoleSelectionSection(selectedRole: $selectedRole)
}
```

User taps either:
- **Athlete**: Blue card with baseball player icon
- **Coach**: Green card with checkmark person icon

### 2. Sign-Up Routing (SignInView.swift)

```swift
if selectedRole == .coach {
    await authManager.signUpAsCoach(
        email: normalizedEmail,
        password: password,
        displayName: trimmedDisplayName
    )
} else {
    await authManager.signUp(
        email: normalizedEmail,
        password: password,
        displayName: trimmedDisplayName
    )
}
```

### 3. Onboarding Display (MainAppView.swift)

```swift
struct OnboardingFlow: View {
    var body: some View {
        Group {
            if authManager.userRole == .coach {
                CoachOnboardingFlow(...)
            } else {
                AthleteOnboardingFlow(...)
            }
        }
    }
}
```

### 4. Post-Onboarding Routing (MainAppView.swift)

```swift
struct UserMainFlow: View {
    var body: some View {
        Group {
            if authManager.userRole == .coach {
                CoachDashboardView()  // Coach home screen
            } else if let athlete = resolvedAthlete {
                MainTabView(...)  // Athlete home screen
            } else {
                FirstAthleteCreationView(...)
            }
        }
    }
}
```

## Debugging

### Console Logs to Watch For

**During Sign-Up:**
```
🔐 Starting authentication - isSignUp: true, role: coach
🔵 Signing up as coach with email: coach@test.com
✅ Authentication successful - userRole: coach
📋 User profile loaded: true
📋 Profile role from Firestore: coach
```

**During Onboarding:**
```
🎯 OnboardingFlow - User role: coach
🎯 OnboardingFlow - User email: coach@test.com
🎯 OnboardingFlow - Showing COACH onboarding
🎯 OnboardingFlow - Profile role: coach
```

**After Onboarding:**
```
🎯 UserMainFlow - User role: coach
🎯 UserMainFlow - Showing CoachDashboardView for user: coach@test.com
```

### Common Issues

#### Issue: "I'm seeing athlete onboarding when I signed up as a coach"

**Possible Causes:**
1. **Testing with existing account**: If you previously created this email as an athlete, the role is already set in Firestore
2. **Role not saving**: Check Firestore console to verify the user document has `"role": "coach"`
3. **Cache issue**: Try signing out completely and signing back in

**Solution:**
- Delete the user from Firebase Authentication
- Delete the user document from Firestore `users` collection
- Sign up again and select "Coach"

#### Issue: "Both onboarding screens look the same"

**New Visual Indicators (After Latest Update):**
- Athlete onboarding shows **blue "ATHLETE ACCOUNT" badge** at top
- Coach onboarding shows **green "COACH ACCOUNT" badge** at top
- Different icons, colors, and feature lists

## Testing Checklist

### Test Case 1: New Athlete Sign-Up
- [ ] Select "Athlete" role in sign-up
- [ ] Complete sign-up
- [ ] See **blue "ATHLETE ACCOUNT" badge**
- [ ] See orange/yellow wave icon
- [ ] See "Welcome to PlayerPath!"
- [ ] See athlete features (Create Profiles, Record Videos, etc.)
- [ ] Tap "Get Started"
- [ ] Land on First Athlete Creation screen
- [ ] After creating athlete, see MainTabView

### Test Case 2: New Coach Sign-Up
- [ ] Select "Coach" role in sign-up
- [ ] Complete sign-up
- [ ] See **green "COACH ACCOUNT" badge**
- [ ] See blue/purple coach icon
- [ ] See "Welcome, Coach!"
- [ ] See coach features (Shared Folders, Upload Videos, etc.)
- [ ] See info box about folder sharing
- [ ] Tap "Go to Dashboard"
- [ ] Land on CoachDashboardView with "My Athletes" tab

### Test Case 3: Returning Users
- [ ] Athlete signs in → Skip onboarding → MainTabView
- [ ] Coach signs in → Skip onboarding → CoachDashboardView

## Files Involved

| File | Purpose |
|------|---------|
| `SignInView.swift` | Role selection UI, sign-up/sign-in routing |
| `MainAppView.swift` | Onboarding flows, post-auth routing |
| `CoachDashboardView.swift` | Coach home screen |
| `ComprehensiveAuthManager.swift` | Authentication and role management |

## Summary

✅ **Two distinct onboarding flows exist and work correctly**
✅ **Visual differences are now more obvious with account type badges**
✅ **Proper routing to appropriate dashboards after onboarding**
✅ **Enhanced logging for easier debugging**

If you're still seeing issues, check the console logs during sign-up to verify:
1. The correct role is being selected
2. The correct sign-up method is being called
3. The role is being saved to Firestore
4. The role is being loaded correctly on app launch
