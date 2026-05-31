//
//  PPDateTile.swift
//  PlayerPath
//
//  Visual overhaul — the date tile.
//  A small (~46pt) rounded square, tile-colored, with a small-caps month label
//  over a condensed day number. Used as the leading element of Games rows.
//

import SwiftUI

struct PPDateTile: View {
    let date: Date
    var tileColor: Color = Theme.tileNavy
    var size: CGFloat = 46

    var body: some View {
        VStack(spacing: 0) {
            Text(month)
                .font(.ppCaptionBold)
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.8))
            Text(day)
                .font(.ppStat(20))                   // Archivo condensed
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .background(
            RoundedRectangle(cornerRadius: .cornerMedium, style: .continuous)
                .fill(tileColor)
        )
    }

    private var month: String {
        date.formatted(.dateTime.month(.abbreviated)).uppercased()
    }

    private var day: String {
        date.formatted(.dateTime.day())
    }
}
