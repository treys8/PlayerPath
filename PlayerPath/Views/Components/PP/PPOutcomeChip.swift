//
//  PPOutcomeChip.swift
//  PlayerPath
//
//  Visual overhaul — the outcome chip.
//  A small tag for the tagged play: HR / 2B / 1B / BB / K (baseball) or
//  GOLF / PRACTICE (context). Accent fill for home runs and highlighted clips;
//  dark-translucent otherwise; green for golf/result context.
//
//  Maps PlayResultType → short abbreviation. Color meaning here is intentionally
//  NOT PlayResultType.color (which uses many hues) — the overhaul rule is one
//  accent only, so significance (HR/highlight) gets accent and everything else
//  stays neutral.
//

import SwiftUI

struct PPOutcomeChip: View {

    enum Style {
        case accent          // significance — HR / highlighted clip
        case darkTranslucent // neutral outcome over media
        case green           // golf / result context
        case neutralOnCard   // outcome shown on a light card (not over media)
    }

    let label: String
    let style: Style

    init(label: String, style: Style) {
        self.label = label
        self.style = style
    }

    var body: some View {
        Text(label)
            .font(.ppCaptionBold)            // Inter semibold 12
            .tracking(0.4)
            .foregroundStyle(foreground)
            .padding(.horizontal, .spacingSmall)
            .padding(.vertical, 3)
            .background(Capsule().fill(background))
    }

    private var foreground: Color {
        switch style {
        case .accent:           return Theme.surface
        case .darkTranslucent:  return .white
        case .green:            return Theme.chipGreenText
        case .neutralOnCard:    return Theme.textSecondary
        }
    }

    private var background: Color {
        switch style {
        case .accent:           return Theme.accent
        case .darkTranslucent:  return .black.opacity(0.55)
        case .green:            return Theme.chipGreenBg
        case .neutralOnCard:    return Theme.divider.opacity(0.6)
        }
    }
}

// MARK: - PlayResultType convenience

extension PPOutcomeChip {
    /// Short scorebook abbreviation for a play result (1B/2B/3B/HR/BB/K/…).
    static func abbreviation(for result: PlayResultType) -> String {
        switch result {
        case .single, .pitchingSingleAllowed:   return "1B"
        case .double, .pitchingDoubleAllowed:   return "2B"
        case .triple, .pitchingTripleAllowed:   return "3B"
        case .homeRun, .pitchingHomeRunAllowed: return "HR"
        case .walk, .pitchingWalk:              return "BB"
        case .strikeout, .pitchingStrikeout:    return "K"
        case .groundOut:                        return "GO"
        case .flyOut:                           return "FO"
        case .batterHitByPitch, .hitByPitch:    return "HBP"
        case .ball:                             return "B"
        case .strike:                           return "STR"
        case .wildPitch:                        return "WP"
        }
    }

    /// Builds a chip for a tagged play. `overMedia` picks the darker neutral
    /// fill suited to sitting over a media tile vs on a light card.
    /// `highlighted` forces the accent fill (e.g. a starred clip).
    init(result: PlayResultType, overMedia: Bool = true, highlighted: Bool = false) {
        let label = Self.abbreviation(for: result)
        let style: Style
        if highlighted || result == .homeRun || result == .pitchingHomeRunAllowed {
            style = .accent
        } else {
            style = overMedia ? .darkTranslucent : .neutralOnCard
        }
        self.init(label: label, style: style)
    }
}
