# Navigation Quick Reference Card

## When to Use What

### 📱 Tab Root View (First view in a tab)
```swift
.tabRootNavigationBar(title: "My Tab")
```
**Use when**: View is the first/root view inside a tab's NavigationStack
**Back button**: Hidden (no back navigation possible at tab root)
**Example**: GamesView, StatisticsView, VideoClipsView

---

### 📄 Child/Detail View (Nested view)
```swift
.childNavigationBar(title: "Details")
```
**Use when**: View is navigated to from another view (via NavigationLink)
**Back button**: Visible (standard iOS back button)
**Example**: GameDetailView, TournamentDetailView, SecuritySettingsView

---

### ✏️ Custom Back Button (With interception)
```swift
.customBackButton(title: "Cancel") {
    // Your custom logic here
    if hasUnsavedChanges {
        showAlert = true
    } else {
        dismiss()
    }
}
```
**Use when**: Need to intercept back navigation (e.g., unsaved changes warning)
**Back button**: Custom (you control the action)
**Example**: Edit forms, unsaved content warnings

---

### 🎭 Modal Sheet (Presented modally)
```swift
NavigationStack {
    MyView()
        .navigationTitle("Modal View")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
}
```
**Use when**: View is presented as a sheet/modal
**Back button**: None (use Cancel/Done in toolbar)
**Example**: AddGameView, AddAthleteView

---

## Common Patterns

### Pattern 1: Simple Tab Root
```swift
struct GamesView: View {
    var body: some View {
        List {
            // Content
        }
        .tabRootNavigationBar(title: "Games")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Add") { }
            }
        }
    }
}
```

### Pattern 2: Child Detail View
```swift
struct GameDetailView: View {
    let game: Game
    
    var body: some View {
        ScrollView {
            // Content
        }
        .childNavigationBar(title: game.opponent)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") { }
            }
        }
    }
}
```

### Pattern 3: Navigation Link
```swift
NavigationLink("Game 1") {
    GameDetailView(game: game)  // Child view - back button automatic
}
```

### Pattern 4: Modal Sheet
```swift
.sheet(isPresented: $showingModal) {
    NavigationStack {  // Modals get their own NavigationStack
        AddGameView()
    }
}
```

---

## Decision Tree

```
Is this view presented as a sheet/modal?
├─ YES → Use NavigationStack + .navigationTitle() + Cancel/Done in toolbar
└─ NO → Is this the first view in a tab?
    ├─ YES → Use .tabRootNavigationBar()
    └─ NO → Use .childNavigationBar()
    
Do you need to intercept back navigation?
└─ YES → Use .customBackButton() instead
```

---

## Tab Structure Template

```swift
TabView(selection: $selectedTab) {
    // Tab 1
    NavigationStack {
        TabRootView()  // ← Use .tabRootNavigationBar()
    }
    .tabItem { Label("Tab 1", systemImage: "star") }
    .tag(0)
    
    // Tab 2
    NavigationStack {
        AnotherTabRootView()  // ← Use .tabRootNavigationBar()
    }
    .tabItem { Label("Tab 2", systemImage: "gear") }
    .tag(1)
}
```

---

## ⚠️ Common Mistakes

### ❌ DON'T: Hide back button on child views
```swift
.navigationBarBackButtonHidden(true)  // WRONG for child views!
```

### ❌ DON'T: Double wrap in NavigationStack
```swift
NavigationStack {  // Already in a NavigationStack from tab
    NavigationStack {  // WRONG - Don't nest!
        MyView()
    }
}
```

### ❌ DON'T: Manually configure navigation
```swift
.navigationTitle("Title")
.navigationBarTitleDisplayMode(.inline)
.navigationBarBackButtonHidden(false)  // WRONG - Use helpers!
```

### ✅ DO: Use the helpers
```swift
.tabRootNavigationBar(title: "Title")  // ✓ Tab root
.childNavigationBar(title: "Title")     // ✓ Child view
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Phantom back button on tab root | Use `.tabRootNavigationBar()` |
| Missing back button on detail | Use `.childNavigationBar()` |
| Need to ask before going back | Use `.customBackButton()` |
| Double back buttons | Remove inner NavigationStack |
| Modal has back button | Modal needs own NavigationStack + Cancel/Done |

---

## Import Required

```swift
// Make sure NavigationHelpers.swift is in your project
// No imports needed - it's in the same module
```

---

## API Reference

| Method | Parameters | Use Case |
|--------|-----------|----------|
| `.tabRootNavigationBar(title:displayMode:)` | title: String, displayMode: .large/.inline | Tab root views |
| `.childNavigationBar(title:displayMode:)` | title: String, displayMode: .large/.inline | Child/detail views |
| `.customBackButton(title:action:)` | title: String?, action: () -> Void | Custom back handling |
| `.navigationBar(title:displayMode:level:)` | title: String, displayMode, level: .tabRoot/.child/.modal | Flexible/conditional |

---

## Display Modes

- `.large` - Large title at top (scrolls to small on scroll)
- `.inline` - Small title always
- `.automatic` - System decides based on context

**Tip**: Use `.large` for tab roots, `.inline` for detail views

---

## Example Hierarchy

```
TabView
├─ Games Tab (NavigationStack)
│   └─ GamesView [TAB ROOT] 🚫 no back button
│       └─ GameDetailView [CHILD] ✅ back button
│           └─ GameStatsView [CHILD] ✅ back button
│
└─ Settings Tab (NavigationStack)
    └─ SettingsView [TAB ROOT] 🚫 no back button
        ├─ AccountView [CHILD] ✅ back button
        └─ SecurityView [CHILD] ✅ back button

Sheets (Modals)
└─ AddGameView [MODAL] 🚫 no back, use Cancel/Done
```

---

## Debug Helper

```swift
#if DEBUG
.debugNavigationLevel(.tabRoot)  // Shows "TAB ROOT" badge
.debugNavigationLevel(.child)     // Shows "CHILD" badge
#endif
```

---

## See Also

- **NavigationHelpers.swift** - Full implementation and documentation
- **NavigationExamples.swift** - Complete working examples
- **NAVIGATION_FIXES_SUMMARY.md** - Detailed explanation of changes

---

**Print this and keep it by your desk! 📝**
