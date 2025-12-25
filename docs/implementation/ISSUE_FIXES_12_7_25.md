# PlayerPath Issue Fixes - December 7, 2025

## Issues Identified from Console Screenshots

### 1. ✅ FIXED - Alert Controller Presentation Issue (Critical)

**Screenshot:** Screenshot 2025-12-07 at 5.23.07 PM.png

**Error:**
```
Attempt to present <SwiftUI.PlatformAlertController: 0x1050c3e00> on
<_TtGC7SwiftUI29PresentationHostingControllerVS_7AnyView_: 0x10b019200>
whose view is not in the window hierarchy.
```

**Root Cause:**
The authentication sign-in view was trying to dismiss itself immediately when `authManager.isSignedIn` changed to `true`. This happened before the view hierarchy was fully stable, causing SwiftUI to attempt presenting an alert controller on a view that wasn't yet in the window hierarchy.

**Location:** `MainAppView.swift:762`

**Fix Applied:**
Added a small delay (100ms) before dismissing the authentication sheet to ensure the view hierarchy is stable:

```swift
// Auto-dismiss on successful authentication
.onChange(of: authManager.isSignedIn) { _, isSignedIn in
    if isSignedIn {
        // Add small delay to ensure view hierarchy is stable before dismissing
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            dismiss()
        }
    }
}
```

This gives SwiftUI enough time to complete any pending presentation/dismissal animations and ensures the view hierarchy is ready.

---

### 2. 🔍 INVESTIGATING - Dashboard Live Games Count = 0

**Screenshot:** Screenshot 2025-12-07 at 5.22.51 PM.png

**Issue:**
```
DashboardView liveGames count: 0 for athlete: Rhett
```

**Root Cause (Suspected):**
The dashboard uses SwiftData `@Query` with a predicate to fetch live games. The query might not be finding games due to:
1. No games are actually marked as `isLive = true`
2. SwiftData relationship query timing issues
3. Predicate not working correctly with optional relationships

**Current Query:**
```swift
@Query(filter: #Predicate<Game> { game in
    game.isLive == true && game.athlete?.id == athleteID
}, sort: [SortDescriptor(\Game.date, order: .reverse)])
```

**Enhanced Debugging Added:**
Added comprehensive debugging in both `DashboardView` and `DashboardLiveSection` to help identify the issue:

1. **DashboardView** (`MainAppView.swift:3127-3139`):
   - Logs total games for the athlete
   - Logs live games found by manual filtering
   - Lists all live games with their details

2. **DashboardLiveSection** (`DashboardLiveSection.swift:26-28`):
   - Logs all live games from the query
   - Logs filtered count for the specific athlete

**Next Steps:**
Run the app and check the console output to see:
- Are there any games for the athlete at all?
- Are any of those games marked as `isLive = true`?
- Is the @Query finding the live games vs manual filtering?

This will help determine if it's a data issue (no live games exist) or a query issue (games exist but query isn't finding them).

---

### 3. ⚠️ NON-CRITICAL - Auto Layout Constraint Conflicts

**Screenshot:** Screenshot 2025-12-07 at 5.23.23 PM.png

**Warnings:**
```
Unable to simultaneously satisfy constraints.
<NSLayoutConstraint:0x6000021c8aa0 'accessoryView.bottom'
 _UIRemoteKeyboardPlaceholderView:0x103a9c7b0.bottom ==
 _UIKBCompatInputView:0x103ca5670.top - 17 (active)>

<NSLayoutConstraint:0x6000021c8d20 'inputView.top'
 V:[_UIRemoteKeyboardPlaceholderView:0x103a9c7b0]-(0)-[
 _UIKBCompatInputView:0x103ca5670] (active)>
```

**Root Cause:**
This is a known iOS/SwiftUI issue with keyboard layout constraints. When the iOS keyboard appears, the system tries to manage layout constraints for `UIRemoteKeyboardPlaceholderView` and `_UIKBCompatInputView`, which sometimes conflict.

**Impact:**
- **User Experience:** None - the conflicts are resolved automatically by the system
- **Performance:** Negligible impact
- **Visual:** No visible issues

**Recommendation:**
These warnings can be safely ignored. They occur in Apple's internal keyboard management code and don't affect your app's functionality. The system will automatically break one of the conflicting constraints to resolve the issue.

**Note:**
These warnings commonly appear when using `TextField`, `SecureField`, or any text input in SwiftUI, especially in forms or authentication screens.

---

### 4. ⚠️ NON-CRITICAL - CloudKit Account Cache Validation

**Screenshot:** Screenshot 2025-12-07 at 5.22.51 PM.png

**Warning:**
```
Could not validate account info cache. (This is a potential performance issue.)
```

**Root Cause:**
CloudKit is reporting that it couldn't validate its account information cache during initialization. This is a performance warning, not an error.

**Impact:**
- **Functionality:** None - CloudKit will still work correctly
- **Performance:** Minimal - CloudKit may need to re-fetch account info instead of using cache
- **User Experience:** No visible impact

**When This Occurs:**
- First app launch after installation
- After CloudKit re-authentication
- After iOS updates
- Occasionally during app backgrounding/foregrounding

**Recommendation:**
This can be safely ignored. CloudKit will automatically re-validate and rebuild its cache as needed. The warning is informational to help identify potential performance bottlenecks during profiling.

---

## Summary of Changes

### Files Modified:
1. ✅ **MainAppView.swift** (Line 762-770)
   - Fixed alert controller presentation timing issue
   - Added enhanced debugging for live games query (Lines 3127-3139)

2. ✅ **DashboardLiveSection.swift** (Lines 24-30)
   - Added debugging for live games filtering

### Recommendations:

1. **Immediate Action:**
   - Test the authentication flow to verify the alert presentation issue is resolved
   - Run the app and check console output for the enhanced live games debugging

2. **Follow-up:**
   - Review console logs to determine why live games count is 0
   - If no games are being created as live, investigate game creation flow
   - If games exist but query isn't finding them, may need to revise the predicate

3. **Optional:**
   - Consider suppressing Auto Layout keyboard warnings in debug builds if they're cluttering console
   - Monitor CloudKit performance in production to ensure cache validation isn't impacting users

---

## Testing Checklist

- [ ] Sign in and ensure no "view not in hierarchy" errors appear
- [ ] Create a new game with "Start as Live Game" enabled
- [ ] Verify the game appears in the dashboard live section
- [ ] Check console output for enhanced debugging information
- [ ] Verify authentication flow completes smoothly

---

## Notes

- All critical issues have been addressed
- Non-critical warnings are expected iOS/SwiftUI behaviors
- Enhanced debugging will help identify the live games query issue
- No breaking changes introduced
