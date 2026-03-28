# Dashboard Architecture Overhaul - MVVM Pattern

## Overview
Complete restructure of dashboard to use proper MVVM architecture with reactive updates. This solves the issue where live games weren't appearing on the dashboard.

---

## The Problem (Old Architecture)

**Before:**
- DashboardView used `@Query` to observe SwiftData changes
- SwiftData wasn't triggering view updates when games became live
- Long delays (or no updates) when creating live games
- Computed properties recalculated on every render
- No control over refresh timing

**Why it failed:**
- SwiftData's automatic observation wasn't working reliably
- The athlete relationship update wasn't triggering `@Query` refresh
- Property changes on existing objects (like `isLive`) weren't detected

---

## The Solution (New Architecture)

### **MVVM Pattern with Observable ViewModel**

```
┌─────────────────────────────────────────────────────────┐
│                    DashboardView                        │
│              (Pure Presentation Layer)                   │
│                                                          │
│  ┌────────────────────────────────────────────────┐    │
│  │  @StateObject viewModel                         │    │
│  │  - Observes published properties                │    │
│  │  - No business logic                            │    │
│  │  - Just displays data                           │    │
│  └────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
                          │
                          │ Observes @Published
                          ▼
┌─────────────────────────────────────────────────────────┐
│            GamesDashboardViewModel                       │
│         (@MainActor ObservableObject)                    │
│                                                          │
│  Published Properties:                                   │
│  ├─ @Published liveGames: [Game]                        │
│  ├─ @Published recentGames: [Game]                      │
│  ├─ @Published upcomingGames: [Game]                    │
│  ├─ @Published recentVideos: [VideoClip]               │
│  ├─ @Published totalGames: Int                          │
│  ├─ @Published totalVideos: Int                         │
│  └─ @Published totalHighlights: Int                     │
│                                                          │
│  Methods:                                                │
│  ├─ refresh() async         - Manual refresh            │
│  ├─ forceRefresh() async    - Pull-to-refresh          │
│  ├─ startAutoRefresh()      - Start 3-second timer     │
│  └─ stopAutoRefresh()       - Stop timer                │
│                                                          │
│  Private:                                                │
│  ├─ setupNotificationObservers() - Listen for changes  │
│  ├─ updateGames([Game])          - Process game data   │
│  └─ updateVideos([VideoClip])    - Process video data  │
└─────────────────────────────────────────────────────────┘
                          │
                          │ Fetches from
                          ▼
┌─────────────────────────────────────────────────────────┐
│                    SwiftData                             │
│  - FetchDescriptor queries                              │
│  - No @Query needed                                     │
│  - Direct modelContext.fetch()                          │
└─────────────────────────────────────────────────────────┘
                          ▲
                          │ Notifies via
                          │ NotificationCenter
┌─────────────────────────────────────────────────────────┐
│                Service Layer                             │
│  ├─ GameService                                         │
│  │  └─ Posts "GameCreated", "GameBecameLive"           │
│  └─ ClipPersistenceService                              │
│     └─ Posts "VideoRecorded"                            │
└─────────────────────────────────────────────────────────┘
```

---

## Key Components

### **1. GamesDashboardViewModel.swift** (NEW)

**Location:** `/Users/Trey/Desktop/PlayerPath/PlayerPath/GamesDashboardViewModel.swift`

**Responsibilities:**
- Fetch data from SwiftData using `FetchDescriptor`
- Filter and sort games/videos for display
- Publish changes to the view
- Listen for notifications from services
- Manage auto-refresh timer

**Key Features:**
- ✅ `@Published` properties automatically trigger view updates
- ✅ Manual refresh via `refresh()` method
- ✅ Auto-refresh timer (every 3 seconds when visible)
- ✅ Notification observers for real-time updates
- ✅ Proper cleanup in `deinit`

**Notification Listeners:**
```swift
- "GameCreated"      → Refresh when any game is created
- "GameBecameLive"   → Refresh when game goes live
- "VideoRecorded"    → Refresh when video is saved
```

---

### **2. DashboardView (REFACTORED)**

**Location:** `/Users/Trey/Desktop/PlayerPath/PlayerPath/MainAppView.swift:2843`

**Changes:**
- ✅ Removed all computed properties (`liveGames`, `recentGames`, etc.)
- ✅ Removed `@Query` declarations
- ✅ Added `@StateObject var viewModel: GamesDashboardViewModel`
- ✅ All data now comes from `viewModel.liveGames`, `viewModel.totalGames`, etc.
- ✅ Custom initializer to create ViewModel with modelContext

**Lifecycle:**
```swift
.onAppear {
    viewModel.startAutoRefresh()  // Start 3-second timer
}
.onDisappear {
    viewModel.stopAutoRefresh()   // Stop timer
}
.refreshable {
    await viewModel.forceRefresh()  // Pull-to-refresh
}
```

---

### **3. Service Layer Updates**

#### **GameService.swift**
**Changes:**
- ✅ Posts `"GameCreated"` notification after save (line 196)
- ✅ Posts `"GameBecameLive"` notification when game goes live (line 200)

#### **ClipPersistenceService.swift**
**Changes:**
- ✅ Posts `"VideoRecorded"` notification after video save (line 175)

---

## Data Flow

### **Creating a Live Game:**

```
1. User creates game with "Start as Live" toggle ON
   │
   ├─ GamesView → GameCreationView
   │
2. GameService.createGame() called
   │
   ├─ Validates season exists
   ├─ Creates Game object
   ├─ Sets game.isLive = true
   ├─ Saves to SwiftData
   │
3. Posts notifications:
   │
   ├─ NotificationCenter.post("GameCreated")
   └─ NotificationCenter.post("GameBecameLive")
   │
4. GamesDashboardViewModel receives notifications
   │
   ├─ Calls refresh() async
   ├─ Fetches all games from SwiftData
   ├─ Filters for athlete's live games
   │
5. Updates @Published var liveGames
   │
6. DashboardView automatically re-renders
   │
   └─ Shows live game in "Live" section ✅
```

### **Auto-Refresh (Every 3 Seconds):**

```
DashboardView appears
   │
   ├─ Calls viewModel.startAutoRefresh()
   │
   ├─ Timer fires every 3 seconds
   │
   ├─ Calls viewModel.refresh()
   │
   ├─ Fetches fresh data from SwiftData
   │
   ├─ Updates @Published properties
   │
   └─ View automatically updates ✅
```

---

## Benefits of New Architecture

### **1. Guaranteed Updates**
- ✅ `@Published` properties **always** trigger view updates
- ✅ No reliance on SwiftData's flaky observation
- ✅ Explicit refresh control

### **2. Real-Time Responsiveness**
- ✅ Auto-refresh timer (3 seconds)
- ✅ Notification-based immediate updates
- ✅ Pull-to-refresh support

### **3. Separation of Concerns**
- ✅ View only displays data
- ✅ ViewModel handles business logic
- ✅ Services manage persistence
- ✅ Testable architecture

### **4. Performance**
- ✅ Data fetched once, cached in ViewModel
- ✅ Only refreshes when needed
- ✅ Timer stops when view disappears

### **5. Maintainability**
- ✅ Single source of truth (ViewModel)
- ✅ Clear data flow
- ✅ Easy to debug
- ✅ Standard iOS pattern

---

## Migration Guide

### **Files Created:**
1. `GamesDashboardViewModel.swift` - NEW

### **Files Modified:**
1. `MainAppView.swift`
   - DashboardView struct completely refactored
   - homeTab now passes modelContext to DashboardView

2. `GameService.swift`
   - Added notification posts (lines 196, 200)

3. `ClipPersistenceService.swift`
   - Added notification post (line 175)

### **Breaking Changes:**
- **DashboardView initialization** now requires `modelContext` parameter
- If you have other code calling DashboardView, update to:
  ```swift
  DashboardView(
      user: user,
      athlete: athlete,
      authManager: authManager,
      modelContext: modelContext  // NEW
  )
  ```

---

## Testing Checklist

### **Live Game Creation:**
1. ✅ Create a season (if none exists)
2. ✅ Create a game with "Start as Live Game" toggle ON
3. ✅ Game should appear on dashboard within 3 seconds
4. ✅ "Quick Record" button should change to "Record Live"

### **Console Output (Debug Mode):**
```
🏗️ GameService: Creating game
   - Is Live: true
🎮 GameService: Game isLive set to: true
✅ GameService: Created new game successfully
📣 Posted GameCreated notification
📣 Posted GameBecameLive notification
🔄 GamesDashboardViewModel: Refreshing data
📊 GamesDashboardViewModel: Fetched X games
🎮 GamesDashboardViewModel: Found 1 live games
   - Opponent Name (isLive: true)
```

### **Pull-to-Refresh:**
1. ✅ Pull down on dashboard
2. ✅ Data refreshes
3. ✅ Latest games/videos appear

### **Auto-Refresh:**
1. ✅ Create a live game in another part of app
2. ✅ Wait 3 seconds
3. ✅ Dashboard updates automatically

### **Cleanup:**
1. ✅ Navigate away from dashboard
2. ✅ Console shows: "⏸️ GamesDashboardViewModel: Stopping auto-refresh"
3. ✅ Timer stops (no more refresh logs)

---

## Performance Notes

### **Auto-Refresh Timer:**
- **Interval:** 3 seconds
- **Impact:** Minimal - only fetches when view is visible
- **Battery:** Stops when view disappears
- **Network:** No network calls, local SwiftData only

### **Memory:**
- ViewModel is created once per view lifecycle
- Properly cleaned up in `deinit`
- Notification observers removed automatically

---

## Future Enhancements

### **Potential Optimizations:**
1. **Incremental Updates**
   - Instead of fetching all games, only fetch changed items
   - Use SwiftData change notifications

2. **Configurable Refresh Rate**
   - Let users set refresh interval (1s, 3s, 5s, manual)
   - Add settings in ProfileView

3. **Smart Refresh**
   - Only refresh if app is in foreground
   - Use `scenePhase` to pause/resume

4. **Reactive SwiftData (Future)**
   - When SwiftData's observation is fixed, can remove timer
   - Keep notification-based updates for critical changes

---

## Troubleshooting

### **Live games still not appearing?**

**Check 1:** Is the game actually marked as live?
```swift
// In GameService debug output:
🎮 GameService: Game isLive set to: true
```

**Check 2:** Is the ViewModel refreshing?
```swift
// Should see in console:
🔄 GamesDashboardViewModel: Refreshing data
```

**Check 3:** Is the athlete ID matching?
```swift
// In ViewModel debug output:
📊 GamesDashboardViewModel: Fetched 5 total games, 5 for athlete
```

**Check 4:** Is the timer running?
```swift
// Should see every 3 seconds:
🔄 GamesDashboardViewModel: Refreshing data
```

**Manual Fix:**
- Pull down on dashboard to force refresh
- Check that auto-refresh started: `▶️ GamesDashboardViewModel: Starting auto-refresh`

---

## Conclusion

This new architecture provides:
- ✅ **Reliable** updates through `@Published` properties
- ✅ **Immediate** feedback via notifications
- ✅ **Automatic** refresh every 3 seconds
- ✅ **Maintainable** code following MVVM pattern
- ✅ **Performant** with proper lifecycle management

The days of wondering why live games don't appear are **over**. 🎉
