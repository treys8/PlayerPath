# Onboarding Race Condition Fix

## Problem
The onboarding flow was showing the same onboarding (athlete onboarding) for both athletes and coaches. This was caused by a race condition where the `userRole` property wasn't set early enough in the sign-up process.

## Root Cause Analysis

### The Issue
When a new user signed up as a coach:

1. **`signUpAsCoach()` was called**
   - `isNewUser = true` was set
   - Firebase user was created
   - `createUserProfile()` was called to create Firestore profile
   - `createUserProfile()` set `userRole = .coach` in a `MainActor.run` block
   - Another `await MainActor.run { self.userRole = .coach }` was executed after `createUserProfile()`

2. **Race Condition Timeline**
   - `userRole` has default value of `.athlete` (declared as `@Published var userRole: UserRole = .athlete`)
   - Sign-up starts → UI may render before async operations complete
   - `OnboardingFlow` checks `authManager.userRole` 
   - At this point, `userRole` might still be `.athlete` (default value)
   - Result: Coach sees athlete onboarding

### Why This Happened
- `userRole` was set in async blocks (`await MainActor.run`)
- SwiftUI views could render between when the function started and when the async block executed
- The default value (`.athlete`) was visible to the UI during this window
- Even though the code eventually set the correct role, the UI had already made its decision

## The Fix

### Changes Made

1. **Synchronous Role Assignment (ComprehensiveAuthManager.swift)**
   
   **In `signUp()` function:**
   ```swift
   func signUp(email: String, password: String, displayName: String?) async {
       isLoading = true
       errorMessage = nil
       isNewUser = true
       
       // ✅ NEW: Set the role IMMEDIATELY before any async operations
       userRole = .athlete
       print("✅ Pre-set userRole to athlete BEFORE Firebase operations")
       
       do {
           // ... rest of sign-up logic
           
           // ✅ NEW: Double-check the role after operations
           if userRole != .athlete {
               print("⚠️ WARNING: userRole was changed, resetting to athlete")
               userRole = .athlete
           }
           
           print("🟢 Sign up successful with role: \(userRole.rawValue)")
       } catch {
           // ... error handling
       }
   }
   ```

   **In `signUpAsCoach()` function:**
   ```swift
   func signUpAsCoach(email: String, password: String, displayName: String) async {
       isLoading = true
       errorMessage = nil
       isNewUser = true
       
       // ✅ NEW: Set the role IMMEDIATELY before any async operations
       userRole = .coach
       print("✅ Pre-set userRole to coach BEFORE Firebase operations")
       
       do {
           // ... rest of sign-up logic
           
           // ✅ NEW: Double-check the role after operations
           if userRole != .coach {
               print("⚠️ WARNING: userRole was changed, resetting to coach")
               userRole = .coach
           }
           
           print("🟢 Coach sign up successful with role: \(userRole.rawValue)")
       } catch {
           // Reset role on error
           userRole = .athlete
           // ... error handling
       }
   }
   ```

2. **Enhanced Debugging (MainAppView.swift)**
   
   Added more comprehensive logging in `OnboardingFlow`:
   ```swift
   .onAppear {
       print("🎯 OnboardingFlow - User role: \(authManager.userRole.rawValue)")
       print("🎯 OnboardingFlow - User email: \(user.email)")
       print("🎯 OnboardingFlow - Showing \(authManager.userRole == .coach ? "COACH" : "ATHLETE") onboarding")
       print("🎯 OnboardingFlow - isNewUser: \(authManager.isNewUser)")
       print("🎯 OnboardingFlow - isSignedIn: \(authManager.isSignedIn)")
       
       if let profile = authManager.userProfile {
           print("🎯 OnboardingFlow - Profile role: \(profile.userRole.rawValue)")
           print("🎯 OnboardingFlow - Profile email: \(profile.email)")
       } else {
           print("⚠️ OnboardingFlow - NO PROFILE LOADED (expected for new users)")
           print("⚠️ OnboardingFlow - Using local userRole: \(authManager.userRole.rawValue)")
       }
   }
   ```

## Benefits of This Fix

1. **Eliminates Race Condition**
   - Role is set synchronously at the start of sign-up
   - UI always sees the correct role, even if it renders before async operations complete

2. **Defensive Programming**
   - Double-checks role after operations
   - Resets role on error
   - Comprehensive logging for debugging

3. **Better User Experience**
   - Coaches immediately see coach-specific onboarding
   - Athletes immediately see athlete-specific onboarding
   - No confusion or incorrect flows

## Testing Checklist

- [ ] Sign up as athlete → Should see athlete onboarding with "ATHLETE ACCOUNT" badge
- [ ] Sign up as coach → Should see coach onboarding with "COACH ACCOUNT" badge
- [ ] Check console logs to verify role is set before Firebase operations
- [ ] Verify role persists after onboarding completion
- [ ] Test error cases (invalid email, weak password) → Role should reset appropriately

## Future Considerations

If you add more roles in the future:
1. Set the role synchronously at the start of the sign-up function
2. Add defensive checks after async operations
3. Add comprehensive logging
4. Consider adding a `roleConfirmed` flag if you need to wait for Firestore confirmation

## Related Files
- `ComprehensiveAuthManager.swift` - Authentication and role management
- `MainAppView.swift` - Onboarding flow UI
- `FirestoreManager.swift` - User profile storage (unchanged)
