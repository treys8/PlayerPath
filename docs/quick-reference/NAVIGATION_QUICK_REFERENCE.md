# Navigation Quick Reference

**Last Updated:** March 27, 2026

---

## Tab Structure

### Athlete Tabs (MainTabView)

| Tab | Index | View | Badge |
|-----|-------|------|-------|
| Home | 0 | `DashboardView` | Pending invitations |
| Games | 1 | `GamesView` | -- |
| Videos | 2 | `VideoClipsView` | Unread activity |
| Stats | 3 | `StatisticsView` | -- |
| More | 4 | List nav (NavigationPath) | -- |

More tab destinations: Practices, Highlights, Seasons, Photos, Coaches, Shared Folders.

### Coach Tabs (CoachTabView)

| Tab | Index | View | Badge |
|-----|-------|------|-------|
| Dashboard | 0 | `CoachDashboardView` | Unread notifications |
| Athletes | 1 | `CoachAthletesTab` | Unread folders + pending invitations |
| Profile | 2 | `CoachProfileView` | -- |

---

## Navigation Helpers

### Tab Root (first view in a tab)
```swift
.tabRootNavigationBar(title: "My Tab")
```
Back button hidden. Examples: GamesView, StatisticsView, VideoClipsView.

### Child/Detail View (navigated to from another view)
```swift
.childNavigationBar(title: "Details")
```
Standard iOS back button. Examples: GameDetailView, PracticeDetailView.

### Custom Back Button (intercept back navigation)
```swift
.customBackButton(title: "Cancel") {
    if hasUnsavedChanges { showAlert = true }
    else { dismiss() }
}
```

### Modal Sheet
```swift
.sheet(isPresented: $showingModal) {
    NavigationStack {
        MyView()
            .navigationTitle("Modal View")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
    }
}
```

---

## Decision Tree

```
Is this view a sheet/modal?
|- YES -> Own NavigationStack + .navigationTitle() + Cancel/Done toolbar
|- NO -> Is this the first view in a tab?
    |- YES -> .tabRootNavigationBar()
    |- NO -> .childNavigationBar()

Need to intercept back?
|- YES -> .customBackButton() instead
```

---

## Programmatic Navigation

All cross-feature navigation uses `NotificationCenter`:

```swift
// Switch tabs
NotificationCenter.default.post(name: .switchTab, object: MainTab.games)

// Switch athlete
NotificationCenter.default.post(name: .switchAthlete, object: nil)

// Present sheets
NotificationCenter.default.post(name: .presentVideoRecorder, object: nil)
NotificationCenter.default.post(name: .presentSeasons, object: nil)
NotificationCenter.default.post(name: .presentCoaches, object: nil)

// Deep navigation
NotificationCenter.default.post(name: .navigateToStatistics, object: nil)
NotificationCenter.default.post(name: .navigateToMorePractice, object: nil)
NotificationCenter.default.post(name: .navigateToMoreHighlights, object: nil)

// Coach navigation
NotificationCenter.default.post(name: .navigateToCoachFolder, object: folderID)
NotificationCenter.default.post(name: .openCoachInvitations, object: nil)
NotificationCenter.default.post(name: .switchCoachTab, object: CoachTab.athletes)

// Global paywall
NotificationCenter.default.post(name: .showSubscriptionPaywall, object: nil)
```

---

## Navigation Coordinators

### NavigationCoordinator (Global)
Defined in `PlayerPathApp.swift`. `@Observable` class injected via environment.
- Sheet/modal presentation state
- Deep link intents (`DeepLinkIntent` enum)

### CoachNavigationCoordinator
Defined in `Views/Coach/CoachNavigationCoordinator.swift`. `@Observable` class.
- Separate `NavigationPath` per tab (dashboard, athletes)
- Pending folder navigation with lazy resolution
- Tab selection persistence (UserDefaults)

---

## Common Patterns

### Per-Tab Athlete Refresh
MainTabView tracks per-tab athlete IDs. Only the active tab refreshes immediately on athlete switch; inactive tabs defer update via `refreshStaleTab()`.

### NavigationPath for More Tab
```swift
@State private var morePath = NavigationPath()

NavigationStack(path: $morePath) {
    List { /* destinations */ }
    .navigationDestination(for: MoreDestination.self) { dest in
        switch dest {
        case .practice: PracticesView()
        case .highlights: HighlightsView()
        // ...
        }
    }
}
```

### iOS 18+ Sidebar
Both MainTabView and CoachTabView support sidebar layout for regular horizontal size class (iPad).

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Phantom back button on tab root | Use `.tabRootNavigationBar()` |
| Missing back button on detail | Use `.childNavigationBar()` |
| Double back buttons | Remove nested NavigationStack |
| Modal has back button | Modal needs own NavigationStack + Cancel/Done |
| Navigation not working | Check NotificationCenter observer is registered |

---

## Key Files

| File | Purpose |
|------|---------|
| `PlayerPathApp.swift` | Global NavigationCoordinator, deep links, NotificationCenter observers |
| `MainAppView.swift` | Root view routing (auth state -> flow) |
| `Views/Athletes/UserMainFlow.swift` | Role-based routing (athlete vs coach) |
| `Views/Navigation/MainTabView.swift` | Athlete 5-tab navigation (652 lines) |
| `Views/Coach/CoachTabView.swift` | Coach 3-tab navigation |
| `Views/Coach/CoachNavigationCoordinator.swift` | Coach nav state management |
| `NavigationHelpers.swift` | `.tabRootNavigationBar()`, `.childNavigationBar()`, `.customBackButton()` |
