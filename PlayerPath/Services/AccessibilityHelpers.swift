//
//  AccessibilityHelpers.swift
//  PlayerPath
//
//  Comprehensive accessibility utilities and helpers
//

import SwiftUI
import UIKit

// MARK: - Accessibility Announcements

struct AccessibilityAnnouncer {
    /// Post an accessibility announcement to VoiceOver
    static func announce(_ message: String, priority: UIAccessibility.Notification = .announcement) {
        DispatchQueue.main.async {
            UIAccessibility.post(notification: priority, argument: message)
        }
    }

    /// Announce with a delay (useful after transitions)
    static func announceAfterDelay(_ message: String, delay: TimeInterval = 0.5) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }

    /// Announce screen change (when navigating to a new screen)
    static func announceScreenChange(_ screenName: String) {
        UIAccessibility.post(notification: .screenChanged, argument: screenName)
    }

    /// Announce layout change (when content updates)
    static func announceLayoutChange(_ message: String? = nil) {
        UIAccessibility.post(notification: .layoutChanged, argument: message)
    }
}

// MARK: - Accessibility Identifiers

enum AccessibilityID {
    // Navigation
    static let tabBarHome = "tab_bar_home"
    static let tabBarGames = "tab_bar_games"
    static let tabBarVideos = "tab_bar_videos"
    static let tabBarStats = "tab_bar_stats"
    static let tabBarPractice = "tab_bar_practice"
    static let tabBarHighlights = "tab_bar_highlights"
    static let tabBarMore = "tab_bar_more"

    // Video Recording
    static let recordButton = "record_button"
    static let uploadButton = "upload_button"
    static let playResultOverlay = "play_result_overlay"
    static let saveVideoButton = "save_video_button"

    // Games
    static let addGameButton = "add_game_button"
    static let gameCard = "game_card"
    static let editGameButton = "edit_game_button"

    // Statistics
    static let battingAverageLabel = "batting_average"
    static let onBasePercentageLabel = "on_base_percentage"
    static let sluggingPercentageLabel = "slugging_percentage"
    static let opsLabel = "ops"

    // Authentication
    static let emailField = "email_field"
    static let passwordField = "password_field"
    static let signInButton = "sign_in_button"
    static let signUpButton = "sign_up_button"
}

// MARK: - Accessibility Traits Extension

extension AccessibilityTraits {
    /// Combine multiple traits
    static func combine(_ traits: AccessibilityTraits...) -> AccessibilityTraits {
        var combined: AccessibilityTraits = []
        for trait in traits {
            combined.formUnion(trait)
        }
        return combined
    }
}

// MARK: - Accessibility View Modifiers

extension View {
    /// Add comprehensive accessibility for a button
    func accessibleButton(
        label: String,
        hint: String? = nil,
        identifier: String? = nil
    ) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .if(let: hint) { view, hint in
                view.accessibilityHint(hint)
            }
            .if(let: identifier) { view, id in
                view.accessibilityIdentifier(id)
            }
    }

    /// Add comprehensive accessibility for a text field
    func accessibleTextField(
        label: String,
        hint: String? = nil,
        value: String? = nil,
        identifier: String? = nil
    ) -> some View {
        self
            .accessibilityLabel(label)
            .if(let: value) { view, val in
                view.accessibilityValue(val)
            }
            .if(let: hint) { view, hint in
                view.accessibilityHint(hint)
            }
            .if(let: identifier) { view, id in
                view.accessibilityIdentifier(id)
            }
    }

    /// Add comprehensive accessibility for a statistic display
    func accessibleStatistic(
        label: String,
        value: String,
        description: String? = nil
    ) -> some View {
        self
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(value)
            .if(let: description) { view, desc in
                view.accessibilityHint(desc)
            }
    }

    /// Mark as header for navigation
    func accessibleHeader() -> some View {
        self.accessibilityAddTraits(.isHeader)
    }

    /// Add accessibility for images
    func accessibleImage(
        label: String,
        isDecorative: Bool = false
    ) -> some View {
        if isDecorative {
            return self.accessibilityHidden(true)
        } else {
            return self
                .accessibilityLabel(label)
                .accessibilityAddTraits(.isImage)
        }
    }

    /// Group multiple elements into a single accessibility element
    func accessibleGroup(label: String, hint: String? = nil) -> some View {
        self
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .if(let: hint) { view, hint in
                view.accessibilityHint(hint)
            }
    }

    /// Conditional modifier helper
    @ViewBuilder
    func `if`<T, Transform: View>(
        `let` optional: T?,
        transform: (Self, T) -> Transform
    ) -> some View {
        if let value = optional {
            transform(self, value)
        } else {
            self
        }
    }
}

// MARK: - Dynamic Type Support

extension View {
    /// Add support for dynamic type sizing with limits
    func dynamicTypeWithLimits(
        min: DynamicTypeSize = .small,
        max: DynamicTypeSize = .accessibility3
    ) -> some View {
        self.dynamicTypeSize(min...max)
    }

    /// Scale with dynamic type but maintain minimum readable size
    func scaledFont(
        _ style: Font.TextStyle,
        design: Font.Design = .default,
        weight: Font.Weight? = nil
    ) -> some View {
        self.font(.system(style, design: design, weight: weight))
    }
}

// MARK: - Accessibility Environment Keys

struct AccessibilityEnabledKey: EnvironmentKey {
    static let defaultValue: Bool = UIAccessibility.isVoiceOverRunning
}

struct ReduceMotionKey: EnvironmentKey {
    static let defaultValue: Bool = UIAccessibility.isReduceMotionEnabled
}

struct IncreasedContrastKey: EnvironmentKey {
    static let defaultValue: Bool = UIAccessibility.isDarkerSystemColorsEnabled
}

extension EnvironmentValues {
    var isVoiceOverRunning: Bool {
        get { self[AccessibilityEnabledKey.self] }
        set { self[AccessibilityEnabledKey.self] = newValue }
    }

    var isReduceMotionEnabled: Bool {
        get { self[ReduceMotionKey.self] }
        set { self[ReduceMotionKey.self] = newValue }
    }

    var isIncreasedContrastEnabled: Bool {
        get { self[IncreasedContrastKey.self] }
        set { self[IncreasedContrastKey.self] = newValue }
    }
}

// MARK: - Accessibility Utilities

struct AccessibilityUtils {
    /// Check if any accessibility feature is enabled
    static var isAccessibilityEnabled: Bool {
        UIAccessibility.isVoiceOverRunning ||
        UIAccessibility.isSwitchControlRunning ||
        UIAccessibility.isAssistiveTouchRunning
    }

    /// Check if reduce motion is enabled
    static var isReduceMotionEnabled: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    /// Check if increased contrast is enabled
    static var isIncreasedContrastEnabled: Bool {
        UIAccessibility.isDarkerSystemColorsEnabled
    }

    /// Check if reduce transparency is enabled
    static var isReduceTransparencyEnabled: Bool {
        UIAccessibility.isReduceTransparencyEnabled
    }

    /// Get preferred content size category
    static var preferredContentSizeCategory: UIContentSizeCategory {
        UIApplication.shared.preferredContentSizeCategory
    }

    /// Check if user prefers larger text
    static var prefersLargerText: Bool {
        preferredContentSizeCategory.isAccessibilityCategory
    }
}

// MARK: - Accessible Button Style

struct AccessibleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.sizeCategory) private var sizeCategory

    let minimumTapTarget: CGFloat = 44 // Apple's recommended minimum

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: minimumTapTarget, minHeight: minimumTapTarget)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .opacity(isEnabled ? 1.0 : 0.5)
    }
}

// MARK: - Accessible Card Modifier

struct AccessibleCardModifier: ViewModifier {
    let title: String
    let description: String?
    let action: String?

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .combine)
            .accessibilityLabel(title)
            .if(let: description) { view, desc in
                view.accessibilityValue(desc)
            }
            .if(let: action) { view, act in
                view.accessibilityHint(act)
            }
            .accessibilityAddTraits(.isButton)
    }
}

extension View {
    func accessibleCard(
        title: String,
        description: String? = nil,
        action: String? = nil
    ) -> some View {
        modifier(AccessibleCardModifier(title: title, description: description, action: action))
    }
}

// MARK: - Readable Content Guide

extension View {
    /// Constrain content to readable width for better accessibility
    func readableContentGuide() -> some View {
        self.frame(maxWidth: 700) // Standard readable content width
            .padding(.horizontal)
    }
}

// MARK: - High Contrast Colors

struct HighContrastColor {
    static func foreground(for background: Color) -> Color {
        if AccessibilityUtils.isIncreasedContrastEnabled {
            // Ensure sufficient contrast ratio (WCAG AA: 4.5:1)
            return background == .black ? .white : .black
        }
        return .primary
    }

    static var buttonBackground: Color {
        AccessibilityUtils.isIncreasedContrastEnabled ? .blue : .accentColor
    }

    static var destructiveBackground: Color {
        AccessibilityUtils.isIncreasedContrastEnabled ? .red : Color.red.opacity(0.8)
    }
}

// MARK: - Accessibility Testing Helpers

#if DEBUG
struct AccessibilityPreviewModifier: ViewModifier {
    let contentSizeCategory: ContentSizeCategory
    let colorScheme: ColorScheme

    func body(content: Content) -> some View {
        content
            .environment(\.sizeCategory, contentSizeCategory)
            .environment(\.colorScheme, colorScheme)
    }
}

extension View {
    /// Preview with different accessibility settings
    func accessibilityPreview(
        sizeCategory: ContentSizeCategory = .large,
        colorScheme: ColorScheme = .light
    ) -> some View {
        modifier(AccessibilityPreviewModifier(
            contentSizeCategory: sizeCategory,
            colorScheme: colorScheme
        ))
    }
}
#endif
