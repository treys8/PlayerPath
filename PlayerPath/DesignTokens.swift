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
    /// Display fonts
    static let displayLarge = Font.system(size: 34, weight: .bold)
    static let displayMedium = Font.system(size: 28, weight: .bold)
    
    /// Heading fonts
    static let headingLarge = Font.system(size: 22, weight: .semibold)
    static let headingMedium = Font.system(size: 18, weight: .semibold)
    static let headingSmall = Font.system(size: 16, weight: .semibold)
    
    /// Body fonts
    static let bodyLarge = Font.system(size: 17, weight: .regular)
    static let bodyMedium = Font.system(size: 15, weight: .regular)
    static let bodySmall = Font.system(size: 13, weight: .regular)
    
    /// Label fonts
    static let labelLarge = Font.system(size: 15, weight: .medium)
    static let labelMedium = Font.system(size: 13, weight: .medium)
    static let labelSmall = Font.system(size: 11, weight: .medium)
}

// MARK: - Colors (Semantic)

extension Color {
    /// Primary brand color
    static let brandPrimary = Color.blue
    static let brandSecondary = Color.purple
    
    /// Premium colors
    static let premium = Color.yellow
    static let premiumBackground = Color.yellow.opacity(0.1)
    
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
