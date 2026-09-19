//
//  PPDateTile.swift
//  PlayerPath
//
//  Visual overhaul — the date tile.
//  A small (~46pt) rounded square, accent-tinted, with a small-caps month label
//  over a condensed day number. Used as the leading element of Games rows.
//  Tinted (not a solid dark tile) so it matches the cream palette — the accent
//  is sport-aware via `\.ppAccent` (terracotta / golf green).
//

import SwiftUI

struct PPDateTile: View {
    let date: Date
    var size: CGFloat = 46

    @Environment(\.ppAccent) private var ppAccent

    var body: some View {
        VStack(spacing: 0) {
            Text(month)
                .font(.ppCaptionBold)
                .tracking(0.6)
                .foregroundStyle(ppAccent)
            Text(day)
                .font(.ppStat(20))                   // Archivo condensed
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(width: size, height: size)
        .background(
            RoundedRectangle(cornerRadius: .cornerMedium, style: .continuous)
                .fill(ppAccent.opacity(0.12))
        )
    }

    private var month: String {
        date.formatted(.dateTime.month(.abbreviated)).uppercased()
    }

    private var day: String {
        date.formatted(.dateTime.day())
    }
}
