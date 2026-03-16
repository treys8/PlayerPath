//
//  DesignTokens.swift
//  PlayerPath
//
//  Created by Assistant on 11/22/25.
//  Centralized design system tokens for consistent UI
//

import SwiftUI

// MARK: - Layout

extension CGFloat {
    /// Icon sizes
    static let iconSmall: CGFloat = 24
    static let iconMedium: CGFloat = 30
    static let iconLarge: CGFloat = 44
    
    /// Profile image sizes
    static let profileSmall: CGFloat = 40
    static let profileMedium: CGFloat = 60
    static let profileLarge: CGFloat = 80
    static let profileXLarge: CGFloat = 120
    
    /// Spacing
    static let spacingXSmall: CGFloat = 4
    static let spacingSmall: CGFloat = 8
    static let spacingMedium: CGFloat = 12
    static let spacingLarge: CGFloat = 16
    static let spacingXLarge: CGFloat = 24
    
    /// Corner radius
    static let cornerSmall: CGFloat = 4
    static let cornerMedium: CGFloat = 8
    static let cornerLarge: CGFloat = 12
    static let cornerXLarge: CGFloat = 16
}

// MARK: - Typography

extension Font {
    /// Display fonts (use text styles for Dynamic Type support)
    static let displayLarge = Font.system(.largeTitle, weight: .bold)
    static let displayMedium = Font.system(.title, weight: .bold)

    /// Heading fonts
    static let headingLarge = Font.system(.title2, weight: .semibold)
    static let headingMedium = Font.system(.headline, weight: .semibold)
    static let headingSmall = Font.system(.subheadline, weight: .semibold)

    /// Body fonts
    static let bodyLarge = Font.system(.body, weight: .regular)
    static let bodyMedium = Font.system(.callout, weight: .regular)
    static let bodySmall = Font.system(.footnote, weight: .regular)

    /// Label fonts
    static let labelLarge = Font.system(.callout, weight: .medium)
    static let labelMedium = Font.system(.footnote, weight: .medium)
    static let labelSmall = Font.system(.caption2, weight: .medium)
}

// MARK: - Colors (Semantic)

extension Color {
    /// Primary brand color
    static let brandPrimary = Color.blue
    static let brandSecondary = Color.purple
    
    /// Premium colors
    static let premium = Color.yellow
    static let premiumBackground = Color.yellow.opacity(0.1)
    
    /// Play result colors
    static let gold = Color(red: 1.0, green: 0.75, blue: 0.0)

    /// Status colors
    static let success = Color.green
    static let warning = Color.orange
    static let error = Color.red
    static let info = Color.blue
    
    /// Background colors (adapts to dark mode)
    static let backgroundPrimary = Color(.systemBackground)
    static let backgroundSecondary = Color(.secondarySystemBackground)
    static let backgroundTertiary = Color(.tertiarySystemBackground)
    
    /// Text colors
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
}

// MARK: - Gradients

extension LinearGradient {
    /// Primary button gradient (blue CTA buttons)
    static let primaryButton = LinearGradient(
        colors: [.blue, .blue.opacity(0.85)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Coach/green button gradient
    static let coachButton = LinearGradient(
        colors: [.green, .green.opacity(0.8)],
        startPoint: .leading, endPoint: .trailing
    )

    /// Premium/purple button gradient
    static let premiumButton = LinearGradient(
        colors: [.purple, .purple.opacity(0.8)],
        startPoint: .leading, endPoint: .trailing
    )

    /// Premium accent gradient (yellow-orange)
    static let premiumAccent = LinearGradient(
        colors: [.yellow, .orange],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Glass panel border highlight
    static let glassBorder = LinearGradient(
        colors: [.white.opacity(0.3), .white.opacity(0.1)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Glass panel top shine effect
    static let glassShine = LinearGradient(
        colors: [.white.opacity(0.15), .clear],
        startPoint: .top, endPoint: .center
    )

    /// Dark glass panel background overlay
    static let glassDark = LinearGradient(
        colors: [Color.black.opacity(0.2), Color.black.opacity(0.4)],
        startPoint: .top, endPoint: .bottom
    )
}

// MARK: - Shadow

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
    
    static let small = ShadowStyle(
        color: .black.opacity(0.06),
        radius: 2,
        x: 0,
        y: 1
    )
    
    static let medium = ShadowStyle(
        color: .black.opacity(0.08),
        radius: 4,
        x: 0,
        y: 2
    )
    
    static let large = ShadowStyle(
        color: .black.opacity(0.12),
        radius: 8,
        x: 0,
        y: 4
    )
}

extension View {
    func cardShadow(_ style: ShadowStyle = .medium) -> some View {
        self.shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}

// MARK: - Animation

extension Animation {
    static let quick = Animation.easeInOut(duration: 0.2)
    static let standard = Animation.easeInOut(duration: 0.3)
    static let slow = Animation.easeInOut(duration: 0.5)
}
