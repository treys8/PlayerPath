//
//  NavigationHelpers.swift
//  PlayerPath
//
//  Created by Xcode Assistant
//  Navigation utilities and modifiers for consistent back button behavior
//

import SwiftUI

// MARK: - Navigation Level

/// Defines the navigation hierarchy level to determine back button behavior
enum NavigationLevel {
    /// Root level in a tab (no back button)
    case tabRoot
    /// Child view in navigation hierarchy (show back button)
    case child
    /// Modal presentation (no back button, use cancel/done)
    case modal
}

// MARK: - Navigation Bar Modifier

extension View {
    /// Configures navigation bar with proper back button behavior based on navigation level
    /// - Parameters:
    ///   - title: The navigation title
    ///   - displayMode: How the title should be displayed
    ///   - level: The navigation hierarchy level (determines back button visibility)
    /// - Returns: Modified view with consistent navigation bar configuration
    func navigationBar(
        title: String,
        displayMode: NavigationBarItem.TitleDisplayMode = .automatic,
        level: NavigationLevel = .child
    ) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(displayMode)
            .navigationBarBackButtonHidden(level == .tabRoot)
    }
    
    /// Configures navigation bar for a root tab view
    /// Hides the back button to prevent phantom back buttons in tab-based navigation
    /// - Parameters:
    ///   - title: The navigation title
    ///   - displayMode: How the title should be displayed (defaults to .large for tab roots)
    /// - Returns: Modified view configured as a tab root
    func tabRootNavigationBar(
        title: String,
        displayMode: NavigationBarItem.TitleDisplayMode = .large
    ) -> some View {
        navigationBar(title: title, displayMode: displayMode, level: .tabRoot)
    }
    
    /// Configures navigation bar for a child view in the navigation hierarchy
    /// Shows the standard back button behavior
    /// - Parameters:
    ///   - title: The navigation title
    ///   - displayMode: How the title should be displayed
    /// - Returns: Modified view configured as a child view
    func childNavigationBar(
        title: String,
        displayMode: NavigationBarItem.TitleDisplayMode = .inline
    ) -> some View {
        navigationBar(title: title, displayMode: displayMode, level: .child)
    }
}

// MARK: - Back Button Customization

extension View {
    /// Adds a custom back button with a specific action
    /// Use this when you need to intercept back navigation (e.g., unsaved changes warning)
    /// - Parameters:
    ///   - title: Optional custom title for the back button (defaults to "Back")
    ///   - action: The action to perform when back button is tapped
    /// - Returns: Modified view with custom back button
    func customBackButton(
        title: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        self
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: action) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                            if let title = title {
                                Text(title)
                            }
                        }
                        .foregroundColor(.blue)
                    }
                }
            }
    }
}

// MARK: - Navigation State Helper

/// Helper to detect if a view is at the root of its navigation stack
/// This can be used to conditionally show/hide UI elements based on navigation depth
struct NavigationStateReader<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let isRoot: Bool
    let content: (Bool) -> Content
    
    init(isRoot: Bool = false, @ViewBuilder content: @escaping (Bool) -> Content) {
        self.isRoot = isRoot
        self.content = content
    }
    
    var body: some View {
        content(isRoot)
    }
}

// MARK: - Debug Navigation Helper

#if DEBUG
extension View {
    /// Adds a visual indicator showing the navigation level (debug builds only)
    /// Useful for debugging navigation hierarchy issues
    func debugNavigationLevel(_ level: NavigationLevel) -> some View {
        self.overlay(alignment: .topTrailing) {
            Text(debugLabel(for: level))
                .font(.caption2)
                .padding(4)
                .background(.red.opacity(0.7))
                .foregroundColor(.white)
                .cornerRadius(4)
                .padding(8)
        }
    }
    
    private func debugLabel(for level: NavigationLevel) -> String {
        switch level {
        case .tabRoot: return "TAB ROOT"
        case .child: return "CHILD"
        case .modal: return "MODAL"
        }
    }
}
#endif

// MARK: - Usage Examples & Documentation

/*
 USAGE EXAMPLES:
 
 1. Tab Root View (no back button):
 ```swift
 struct GamesView: View {
     var body: some View {
         List { ... }
             .tabRootNavigationBar(title: "Games")
             .toolbar { ... }
     }
 }
 ```
 
 2. Child View (standard back button):
 ```swift
 struct GameDetailView: View {
     var body: some View {
         ScrollView { ... }
             .childNavigationBar(title: "Game Details")
     }
 }
 ```
 
 3. Custom Back Button (with warning for unsaved changes):
 ```swift
 struct EditProfileView: View {
     @State private var hasChanges = false
     @Environment(\.dismiss) private var dismiss
     
     var body: some View {
         Form { ... }
             .navigationTitle("Edit Profile")
             .customBackButton {
                 if hasChanges {
                     // Show warning alert
                 } else {
                     dismiss()
                 }
             }
     }
 }
 ```
 
 4. Flexible Navigation Bar (conditional behavior):
 ```swift
 struct AthleteView: View {
     let isRootView: Bool
     
     var body: some View {
         List { ... }
             .navigationBar(
                 title: "Athlete",
                 displayMode: isRootView ? .large : .inline,
                 level: isRootView ? .tabRoot : .child
             )
     }
 }
 ```
 
 NAVIGATION BEST PRACTICES:
 
 ✅ DO:
 - Use .tabRootNavigationBar() for the first view in each tab
 - Use .childNavigationBar() for detail views
 - Use .customBackButton() when you need to intercept back navigation
 - Keep navigation hierarchies shallow (3-4 levels max)
 
 ❌ DON'T:
 - Manually set .navigationBarBackButtonHidden() without using these helpers
 - Hide back buttons on child views (breaks user expectations)
 - Create circular navigation paths
 - Mix modal and push navigation for the same flow
 
 TROUBLESHOOTING:
 
 Problem: "Phantom back button" appears on tab root
 Solution: Use .tabRootNavigationBar() instead of .navigationTitle()
 
 Problem: Back button missing on detail view
 Solution: Don't hide back button on child views; remove .navigationBarBackButtonHidden()
 
 Problem: Need to confirm before going back
 Solution: Use .customBackButton() with your confirmation logic
 */
