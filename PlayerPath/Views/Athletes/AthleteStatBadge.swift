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

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text("\(count)")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(.blue)

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
