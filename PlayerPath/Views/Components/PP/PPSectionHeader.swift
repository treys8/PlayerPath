//
//  PPSectionHeader.swift
//  PlayerPath
//
//  Visual overhaul — the shared section header.
//  Editorial serif title (Fraunces) with an optional small-caps overline and an
//  optional trailing action. Replaces the ad-hoc `HStack { Text; Spacer; Button }`
//  headers scattered across the app (e.g. StatisticsView's inline SectionHeader).
//

import SwiftUI

struct PPSectionHeader<Trailing: View>: View {
    let title: String
    var overline: String?
    let trailing: Trailing

    init(_ title: String, overline: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.overline = overline
        self.trailing = trailing()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let overline {
                Text(overline).smallCapsLabel()
            }
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.ppTitle2)               // Fraunces serif
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: .spacingMedium)
                trailing
            }
        }
    }
}

// Convenience for headers with no trailing action.
extension PPSectionHeader where Trailing == EmptyView {
    init(_ title: String, overline: String? = nil) {
        self.init(title, overline: overline) { EmptyView() }
    }
}
