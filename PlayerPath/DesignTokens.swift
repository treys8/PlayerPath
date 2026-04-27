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

// MARK: - Thumbnail Sizes

extension CGSize {
    /// Small video thumbnail (search results, compact lists)
    static let thumbnailSmall = CGSize(width: 80, height: 60)
    /// Standard 16:9 video thumbnail (game clip rows, file manager)
    static let thumbnailMedium = CGSize(width: 160, height: 90)
    /// Card-sized video thumbnail (highlights, video clips grid)
    static let thumbnailLarge = CGSize(width: 200, height: 112)
    /// Photo/profile image thumbnail
    static let thumbnailPhoto = CGSize(width: 300, height: 300)
}

// MARK: - Typography

extension Font {
    /// Display — Fraunces (serif)
    static let displayLarge = Font.custom("Fraunces72pt-Bold", size: 34, relativeTo: .largeTitle)
    static let displayMedium = Font.custom("Fraunces72pt-Bold", size: 28, relativeTo: .title)

    /// Headings — Fraunces (large/medium) + Inter (small)
    static let headingLarge = Font.custom("Fraunces72pt-SemiBold", size: 22, relativeTo: .title2)
    static let headingMedium = Font.custom("Inter18pt-SemiBold", size: 17, relativeTo: .headline)
    static let headingSmall = Font.custom("Inter18pt-SemiBold", size: 15, relativeTo: .subheadline)

    /// Body — Inter
    static let bodyLarge = Font.custom("Inter18pt-Regular", size: 17, relativeTo: .body)
    static let bodyMedium = Font.custom("Inter18pt-Regular", size: 16, relativeTo: .callout)
    static let bodySmall = Font.custom("Inter18pt-Regular", size: 13, relativeTo: .footnote)

    /// Labels — Inter Medium
    static let labelLarge = Font.custom("Inter18pt-Medium", size: 16, relativeTo: .callout)
    static let labelMedium = Font.custom("Inter18pt-Medium", size: 13, relativeTo: .footnote)
    static let labelSmall = Font.custom("Inter18pt-Medium", size: 11, relativeTo: .caption2)
}

// MARK: - Colors (Semantic)

extension Color {
    /// Primary brand colors — derived from the app icon (navy + gold)
    static let brandNavy = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.25, green: 0.66, blue: 0.97, alpha: 1) // #40A8F7
            : UIColor(red: 0.0, green: 0.20, blue: 0.45, alpha: 1)  // #003373 original navy
    })
    static let brandGold = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.90, green: 0.72, blue: 0.28, alpha: 1) // brighter for dark mode
            : UIColor(red: 0.83, green: 0.63, blue: 0.16, alpha: 1) // #D4A029
    })

    /// Legacy aliases
    static let brandPrimary = Color.brandNavy
    static let brandSecondary = Color.purple

    /// Premium colors
    static let premium = Color.brandGold
    static let premiumBackground = Color.brandGold.opacity(0.1)

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

    // MARK: - Hex Conversion (used by telestration shape serialization)

    /// Creates a Color from a "#RRGGBB" or "RRGGBB" hex string. Returns red on parse failure.
    init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: trimmed).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8)  & 0xFF) / 255.0
        let b = Double(value         & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }

    /// "#RRGGBB" representation of the color's resolved sRGB components.
    /// Returns nil if the underlying UIColor can't resolve without trait context.
    func toHex() -> String? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        let ri = Int((r * 255).rounded())
        let gi = Int((g * 255).rounded())
        let bi = Int((b * 255).rounded())
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }
}

// MARK: - Gradients

extension LinearGradient {
    /// Brand navy gradient
    static let brandNavy = LinearGradient(
        colors: [.brandNavy, .brandNavy.opacity(0.85)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Brand gold gradient
    static let brandGold = LinearGradient(
        colors: [.brandGold, .brandGold.opacity(0.8)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

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

// MARK: - Badges

extension View {
    /// Small metadata badge (season, duration, count). 6h / 2v padding.
    /// Pair with Capsule background.
    func badgeSmall() -> some View {
        padding(.horizontal, 6).padding(.vertical, 2)
    }

    /// Medium status badge (LIVE, pitch speed, uploading). 8h / 4v padding.
    /// Pair with Capsule background.
    func badgeMedium() -> some View {
        padding(.horizontal, 8).padding(.vertical, 4)
    }
}
