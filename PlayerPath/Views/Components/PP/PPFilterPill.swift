//
//  PPFilterPill.swift
//  PlayerPath
//
//  Visual overhaul — the filter pill + horizontal pill row.
//  Selected = dark fill (textPrimary) with cream text; unselected = pillBorder
//  outline with muted text. Fully rounded. Used by Journal / Games / Clips
//  filter bars (All / Games / Golf / Highlights, etc.).
//

import SwiftUI

struct PPFilterPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.ppCallout)                       // Inter medium
                .foregroundStyle(isSelected ? Theme.surface : Theme.textSecondary)
                .padding(.horizontal, .spacingLarge)
                .padding(.vertical, .spacingSmall)
                .background(
                    Capsule().fill(isSelected ? Theme.textPrimary : Color.clear)
                )
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? Color.clear : Theme.pillBorder,
                        lineWidth: 1
                    )
                )
                // Without an explicit hit shape, a .plain button only registers
                // taps on its opaque content. Unselected pills have a clear fill,
                // so taps in their interior would fall through to whatever sits
                // behind them in the feed (the first card's link). Make the whole
                // capsule tappable.
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Horizontal, scrollable row of filter pills bound to a selection.
/// Generic over any `Hashable` option (enum, string, …) with a title mapper.
struct PPFilterPillRow<Option: Hashable>: View {
    let options: [Option]
    let title: (Option) -> String
    @Binding var selection: Option

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: .spacingSmall) {
                ForEach(options, id: \.self) { option in
                    PPFilterPill(
                        title: title(option),
                        isSelected: option == selection
                    ) {
                        selection = option
                    }
                }
            }
            .padding(.horizontal, 18)                    // screen horizontal padding
            .padding(.vertical, 2)                       // breathing room for the outline
        }
    }
}
