//
//  AthleteStatBadge.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI

struct AthleteStatBadge: View {
    let icon: String
    let count: Int
    let label: String
    /// Tint for the icon + count — defaults to the base accent so callers that
    /// don't know the sport still match the palette. AthleteCard passes the
    /// sport-resolved accent (terracotta vs. golf green).
    var color: Color = Theme.accent

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text("\(count)")
                    .font(.ppStatSmall)
                    .monospacedDigit()
            }
            .foregroundColor(color)

            Text(label)
                .font(.labelSmall)
                .foregroundColor(.secondary)
        }
    }
}
