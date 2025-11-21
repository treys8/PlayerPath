//
//  NavigationExamples.swift
//  PlayerPath
//
//  Examples demonstrating proper navigation patterns
//

import SwiftUI

// MARK: - Example 1: Simple Tab Root View

/// ✅ CORRECT: Tab root view with no back button
struct ExampleTabRootView: View {
    var body: some View {
        List {
            Text("Item 1")
            Text("Item 2")
            Text("Item 3")
        }
        .tabRootNavigationBar(title: "My Tab")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Add") { /* action */ }
            }
        }
    }
}

// MARK: - Example 2: Detail View with Standard Back Button

/// ✅ CORRECT: Child/detail view with automatic back button
struct ExampleDetailView: View {
    let item: String
    
    var body: some View {
        ScrollView {
            Text("Details for \(item)")
                .padding()
        }
        .childNavigationBar(title: "Details")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") { /* action */ }
            }
        }
    }
}

// MARK: - Example 3: Custom Back Button with Confirmation

/// ✅ CORRECT: Custom back button that asks for confirmation
struct ExampleEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hasChanges = false
    @State private var showingDiscardAlert = false
    @State private var text = ""
    
    var body: some View {
        Form {
            TextField("Name", text: $text)
                .onChange(of: text) { _, _ in
                    hasChanges = true
                }
        }
        .childNavigationBar(title: "Edit")
        .customBackButton {
            if hasChanges {
                showingDiscardAlert = true
            } else {
                dismiss()
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    // Save changes
                    hasChanges = false
                    dismiss()
                }
            }
        }
        .alert("Discard Changes?", isPresented: $showingDiscardAlert) {
            Button("Discard", role: .destructive) {
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You have unsaved changes. Are you sure you want to go back?")
        }
    }
}

// MARK: - Example 4: Conditional Navigation Level

/// ✅ CORRECT: View that adapts based on presentation context
struct ExampleAdaptiveView: View {
    let isRootView: Bool
    
    var body: some View {
        List {
            Text("Content")
        }
        .navigationBar(
            title: "Adaptive",
            displayMode: isRootView ? .large : .inline,
            level: isRootView ? .tabRoot : .child
        )
    }
}

// MARK: - Example 5: Modal Sheet (No Back Button Needed)

/// ✅ CORRECT: Modal sheet with cancel/done in toolbar
struct ExampleModalView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
            }
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        // Save
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}

// MARK: - Common Mistakes to Avoid

/// ❌ WRONG: Manually hiding back button on child view
struct WrongChildViewExample: View {
    var body: some View {
        ScrollView {
            Text("Details")
        }
        .navigationTitle("Details")
        .navigationBarBackButtonHidden(true)  // ❌ DON'T DO THIS
    }
}

/// ❌ WRONG: Double NavigationStack wrapping
struct WrongDoubleNavigationExample: View {
    var body: some View {
        // This view is already inside a NavigationStack from the tab
        NavigationStack {  // ❌ DON'T ADD ANOTHER ONE
            List {
                Text("Item")
            }
            .navigationTitle("My View")
        }
    }
}

/// ❌ WRONG: Redundant back button configuration
struct WrongRedundantExample: View {
    var body: some View {
        List {
            Text("Item")
        }
        .navigationTitle("My View")
        .navigationBarBackButtonHidden(false)  // ❌ This is the default!
    }
}

// MARK: - Complete Tab Structure Example

/// ✅ CORRECT: Complete example showing tab with navigation hierarchy
struct CompleteNavigationExample: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: Games
            NavigationStack {
                GamesListView()
            }
            .tabItem {
                Label("Games", systemImage: "sportscourt.fill")
            }
            .tag(0)
            
            // Tab 2: Settings
            NavigationStack {
                SettingsListView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .tag(1)
        }
    }
}

struct GamesListView: View {
    var body: some View {
        List {
            NavigationLink("Game 1") {
                GameDetailView(gameName: "Game 1")
            }
            NavigationLink("Game 2") {
                GameDetailView(gameName: "Game 2")
            }
        }
        .tabRootNavigationBar(title: "Games")  // ✅ Tab root - no back button
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Add") { /* action */ }
            }
        }
    }
}

struct GameDetailView: View {
    let gameName: String
    
    var body: some View {
        VStack {
            Text("Details for \(gameName)")
            
            NavigationLink("View Statistics") {
                GameStatisticsView(gameName: gameName)
            }
        }
        .childNavigationBar(title: gameName)  // ✅ Child view - shows back button
    }
}

struct GameStatisticsView: View {
    let gameName: String
    
    var body: some View {
        List {
            Text("Stats for \(gameName)")
        }
        .childNavigationBar(title: "Statistics")  // ✅ Child view - shows back button
    }
}

struct SettingsListView: View {
    var body: some View {
        List {
            NavigationLink("Account") {
                AccountSettingsView()
            }
            NavigationLink("Notifications") {
                NotificationSettingsView()
            }
        }
        .tabRootNavigationBar(title: "Settings")  // ✅ Tab root - no back button
    }
}

struct AccountSettingsView: View {
    var body: some View {
        Form {
            Section("Profile") {
                Text("User Name")
            }
        }
        .childNavigationBar(title: "Account")  // ✅ Child view - shows back button
    }
}

struct NotificationSettingsView: View {
    @State private var enabled = true
    
    var body: some View {
        Form {
            Toggle("Enable Notifications", isOn: $enabled)
        }
        .childNavigationBar(title: "Notifications")  // ✅ Child view - shows back button
    }
}

// MARK: - Navigation Hierarchy Visualization

/*
 NAVIGATION HIERARCHY VISUAL:
 
 TabView
 ├─ Tab 1: Games (NavigationStack)
 │   ├─ GamesListView [TAB ROOT - NO BACK BUTTON]
 │   │   └─ GameDetailView [CHILD - SHOWS BACK BUTTON]
 │   │       └─ GameStatisticsView [CHILD - SHOWS BACK BUTTON]
 │   └─ ... more views
 │
 ├─ Tab 2: Settings (NavigationStack)
 │   ├─ SettingsListView [TAB ROOT - NO BACK BUTTON]
 │   │   ├─ AccountSettingsView [CHILD - SHOWS BACK BUTTON]
 │   │   └─ NotificationSettingsView [CHILD - SHOWS BACK BUTTON]
 │   └─ ... more views
 │
 └─ ... more tabs
 
 MODAL PRESENTATIONS (Separate NavigationStack):
 .sheet {
     NavigationStack {
         ModalView [MODAL - NO BACK BUTTON, USES CANCEL/DONE]
     }
 }
 
 KEY RULES:
 1. Each tab has its own NavigationStack (defined in TabView)
 2. First view in each tab = TAB ROOT (no back button)
 3. Subsequent views = CHILD (automatic back button)
 4. Modals = separate NavigationStack (use cancel/done, not back)
 5. NEVER nest NavigationStack within a tab's views
 6. NEVER hide back buttons on child views (breaks UX)
 */

// MARK: - Real-World Pattern: Settings with Edit Flow

struct RealWorldSettingsExample: View {
    @State private var showingEditProfile = false
    
    var body: some View {
        List {
            Section("Profile") {
                HStack {
                    Text("Name")
                    Spacer()
                    Text("John Doe")
                        .foregroundColor(.secondary)
                }
                
                Button("Edit Profile") {
                    showingEditProfile = true
                }
            }
            
            Section("Account") {
                NavigationLink("Security Settings") {
                    SecuritySettingsView()
                }
                NavigationLink("Privacy") {
                    PrivacySettingsView()
                }
            }
        }
        .tabRootNavigationBar(title: "Settings")
        .sheet(isPresented: $showingEditProfile) {
            // Modal presentation with its own NavigationStack
            NavigationStack {
                EditProfileForm()
            }
        }
    }
}

struct EditProfileForm: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = "John Doe"
    @State private var hasChanges = false
    
    var body: some View {
        Form {
            TextField("Name", text: $name)
                .onChange(of: name) { _, _ in
                    hasChanges = true
                }
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    // Save changes
                    dismiss()
                }
                .disabled(!hasChanges)
            }
        }
    }
}

struct SecuritySettingsView: View {
    var body: some View {
        Form {
            Section("Authentication") {
                Toggle("Face ID", isOn: .constant(true))
            }
        }
        .childNavigationBar(title: "Security")
    }
}

struct PrivacySettingsView: View {
    var body: some View {
        Form {
            Section("Data") {
                Toggle("Share Analytics", isOn: .constant(false))
            }
        }
        .childNavigationBar(title: "Privacy")
    }
}

// MARK: - Preview Examples

#Preview("Tab Root") {
    NavigationStack {
        ExampleTabRootView()
    }
}

#Preview("Detail View") {
    NavigationStack {
        ExampleDetailView(item: "Test Item")
    }
}

#Preview("Custom Back Button") {
    NavigationStack {
        ExampleEditView()
    }
}

#Preview("Modal Sheet") {
    Text("Tap to show modal")
        .sheet(isPresented: .constant(true)) {
            ExampleModalView()
        }
}

#Preview("Complete Navigation") {
    CompleteNavigationExample()
}

#Preview("Settings Example") {
    NavigationStack {
        RealWorldSettingsExample()
    }
}
