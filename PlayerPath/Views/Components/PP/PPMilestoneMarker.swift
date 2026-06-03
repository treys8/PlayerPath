//
//  PPMilestoneMarker.swift
//  PlayerPath
//
//  Visual overhaul — the milestone star marker.
//  One consistent "this mattered" signal across all screens: an accent star
//  plus a small-caps label ("SEASON FIRST", "PERSONAL BEST"). Driven by the
//  milestone engine (added later); purely presentational here.
//

import SwiftUI

struct PPMilestoneMarker: View {
    let label: String
    /// Use a lighter accent when sitting over a dark media surface.
    var overDarkSurface: Bool = false

    @Environment(\.ppAccent) private var ppAccent
    @Environment(\.ppAccentLight) private var ppAccentLight

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "star.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(starColor)
            Text(label)
                .smallCapsLabel(color: textColor)
        }
    }

    private var starColor: Color {
        overDarkSurface ? ppAccentLight : ppAccent
    }

    private var textColor: Color {
        overDarkSurface ? ppAccentLight : ppAccent
    }
}
