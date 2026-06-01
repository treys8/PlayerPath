//
//  ChartsPromptCard.swift
//  PlayerPath
//
//  Created by Trey Schilling on 3/21/26.
//

import SwiftUI

// MARK: - Charts Prompt Card

struct ChartsPromptCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.accent)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Visualize Your Performance")
                        .font(.ppTitle3)
                        .foregroundStyle(Theme.textPrimary)

                    Text("View interactive charts and trends")
                        .font(.ppSubheadline)
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.accent)
            }
            .padding()
            .ppCard()
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
}
