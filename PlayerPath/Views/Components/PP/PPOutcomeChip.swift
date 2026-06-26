//
//  PPOutcomeChip.swift
//  PlayerPath
//
//  Visual overhaul — the outcome chip.
//  A small tag for the tagged play: HR / 2B / 1B / BB / K (baseball) or
//  GOLF / PRACTICE (context). Accent fill for home runs and highlighted clips;
//  dark-translucent otherwise; green for golf/result context.
//
//  Reads the short abbreviation from PlayResultType.abbreviation. Color meaning
//  here is intentionally NOT PlayResultType.color (which uses many hues) — the
//  overhaul rule is one accent only. Significance (HR / highlighted hit) gets
//  the accent; negative outcomes (outs, hits/HR allowed — `valence == .negative`)
//  get a quieter recede tier so they sit below routine plays; everything else
//  stays neutral.
//

import SwiftUI

struct PPOutcomeChip: View {

    enum Style {
        case accent          // significance — HR / highlighted clip
        case darkTranslucent // neutral outcome over media
        case green           // golf / result context
        case neutralOnCard   // outcome shown on a light card (not over media)
        case negativeOnMedia // negative outcome (out / hit allowed) over media — recedes
        case negativeOnCard  // negative outcome on a light card — recedes
    }

    let label: String
    let style: Style
    @Environment(\.ppAccent) private var ppAccent

    init(label: String, style: Style) {
        self.label = label
        self.style = style
    }

    /// True when this chip uses the accent fill — the card's "this mattered"
    /// signal (a home run, or a starred clip). The media-tile star reads this to
    /// avoid double-signaling significance on the same tile.
    var isAccent: Bool { style == .accent }

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
        case .negativeOnMedia:  return .white.opacity(0.75)
        case .negativeOnCard:   return Theme.textTertiary
        }
    }

    private var background: Color {
        switch style {
        case .accent:           return ppAccent
        case .darkTranslucent:  return .black.opacity(0.55)
        case .green:            return Theme.chipGreenBg
        case .neutralOnCard:    return Theme.divider.opacity(0.6)
        case .negativeOnMedia:  return .black.opacity(0.35)
        case .negativeOnCard:   return Theme.divider.opacity(0.4)
        }
    }
}

// MARK: - PlayResultType convenience

extension PPOutcomeChip {
    /// Builds a chip for a tagged play.
    ///
    /// Style tiers, in order:
    /// 1. `highlighted` or a batter's home run → accent (the "this mattered" fill).
    ///    A HR *allowed* is NOT significance — it's a pitcher negative and falls
    ///    to the recede tier below.
    /// 2. `valence == .negative` (outs, hits/HR allowed) → recede tier, quieter
    ///    than neutral so it sits below routine plays.
    /// 3. everything else → neutral.
    ///
    /// `overMedia` picks the over-a-media-tile fill vs the light-card fill.
    init(result: PlayResultType, overMedia: Bool = true, highlighted: Bool = false) {
        let label = result.abbreviation
        let style: Style
        if highlighted || result == .homeRun {
            style = .accent
        } else if result.valence == .negative {
            style = overMedia ? .negativeOnMedia : .negativeOnCard
        } else {
            style = overMedia ? .darkTranslucent : .neutralOnCard
        }
        self.init(label: label, style: style)
    }
}
