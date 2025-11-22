//
//  Haptics.swift
//  PlayerPath
//
//  Created by Assistant on 11/22/25.
//  Consistent haptic feedback throughout the app
//

import UIKit
import SwiftUI

/// Centralized haptic feedback manager
/// Usage: Haptics.success(), Haptics.warning(), etc.
enum Haptics {
    
    // MARK: - Notification Feedback
    
    /// Positive confirmation (e.g., save successful, upload complete)
    static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    /// Warning or important action (e.g., about to delete, premium required)
    static func warning() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }
    
    /// Error occurred (e.g., save failed, network error)
    static func error() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }
    
    // MARK: - Impact Feedback
    
    /// Light tap (e.g., button press, selection change)
    static func light() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    /// Medium impact (e.g., toggle switch, sheet dismiss)
    static func medium() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    
    /// Heavy impact (e.g., delete action, important confirmation)
    static func heavy() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
    }
    
    /// Soft impact (iOS 17+, gentle feedback)
    @available(iOS 17.0, *)
    static func soft() {
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.impactOccurred()
    }
    
    /// Rigid impact (iOS 17+, precise feedback)
    @available(iOS 17.0, *)
    static func rigid() {
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.impactOccurred()
    }
    
    // MARK: - Selection Feedback
    
    /// Selection changed (e.g., picker scroll, segmented control)
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
}

// MARK: - SwiftUI View Extension

extension View {
    /// Add haptic feedback to any tap gesture
    func haptic(_ style: HapticStyle) -> some View {
        self.onTapGesture {
            switch style {
            case .light: Haptics.light()
            case .medium: Haptics.medium()
            case .heavy: Haptics.heavy()
            case .success: Haptics.success()
            case .warning: Haptics.warning()
            case .error: Haptics.error()
            case .selection: Haptics.selection()
            }
        }
    }
}

enum HapticStyle {
    case light, medium, heavy
    case success, warning, error
    case selection
}
