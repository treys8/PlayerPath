//
//  MainAppView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//
//  CRITICAL FIXES APPLIED:
//  1. ✅ NotificationCenter Memory Leak Prevention - Using @StateObject NotificationObserverManager for lifecycle safety
//  2. ✅ SwiftData Relationship Race Condition - Set relationships before insert, let inverse handle array
//  3. ✅ Safe Predicate Implementation - Removed force unwrap, using Swift filter instead
//  4. ✅ Task Cancellation - All async tasks check for cancellation and store references for cleanup
//  5. ✅ Observer Duplication Prevention - Dedicated ObservableObject manages observers with automatic cleanup
//

import SwiftUI
import SwiftData
import FirebaseAuth
import Combine

/// App-wide notifications used for cross-feature coordination.
/// - switchTab: Pass an Int tab index as object to switch the main TabView.
/// - presentVideoRecorder: Ask Videos module to present its recorder UI.
/// - showAthleteSelection: Request athlete selection UI to be shown.
/// - recordedHitResult: Post with object ["hitType": String] to update highlights and stats.

// MARK: - Main Tab Enum
enum MainTab: Int {
    case home = 0
    case games = 1
    case videos = 2
    case stats = 3
    case practice = 4
    case highlights = 5
    case more = 6

    // Legacy compatibility alias
    static var profile: MainTab { .more }
}

// Convenience helper to switch tabs via NotificationCenter
@inline(__always)
func postSwitchTab(_ tab: MainTab) {
    NotificationCenter.default.post(name: .switchTab, object: tab.rawValue)
}

// MARK: - App Root
struct PlayerPathMainView: View {
    @StateObject private var authManager = ComprehensiveAuthManager()
    
    var body: some View {
        Group {
            if authManager.isSignedIn {
                AuthenticatedFlow()
            } else {
                WelcomeFlow()
            }
        }
        .environmentObject(authManager)
        .tint(.blue)
        .dynamicTypeSize(...DynamicTypeSize.accessibility5)
        .withErrorHandling() // Global error handling
    }
}
