//
//  SeasonFilterMenu.swift
//  PlayerPath
//
//  Created by Assistant on 12/21/25.
//  Reusable season filter menu component
//

import SwiftUI
import SwiftData

/// Reusable season filter menu that maintains consistent UX across all views
struct SeasonFilterMenu: View {
    @Binding var selectedSeasonID: String? // nil = All Seasons
    let availableSeasons: [Season]
    let showNoSeasonOption: Bool

    var body: some View {
        Menu {
            Button {
                selectedSeasonID = nil
            } label: {
                HStack {
                    Text("All Seasons")
                    if selectedSeasonID == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Divider()

            ForEach(availableSeasons) { season in
                Button {
                    selectedSeasonID = season.id.uuidString
                } label: {
                    HStack {
                        Text(season.displayName)
                        if selectedSeasonID == season.id.uuidString {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            if showNoSeasonOption {
                Divider()
                Button {
                    selectedSeasonID = "no_season"
                } label: {
                    HStack {
                        Text("No Season")
                        if selectedSeasonID == "no_season" {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: selectedSeasonID != nil
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
                .foregroundColor(.brandNavy)
        }
        .accessibilityLabel("Filter by season")
        .accessibilityValue(selectedSeasonID == nil ? "All seasons" : selectedSeasonName)
        .accessibilityHint("Double tap to change season filter")
    }

    private var selectedSeasonName: String {
        if let id = selectedSeasonID {
            if id == "no_season" {
                return "No season"
            }
            if let season = availableSeasons.first(where: { $0.id.uuidString == id }) {
                return season.displayName
            }
        }
        return "All seasons"
    }
}

/// Reusable season badge component for consistent display across views
struct SeasonBadge: View {
    let season: Season
    let fontSize: CGFloat

    init(season: Season, fontSize: CGFloat = 8) {
        self.season = season
        self.fontSize = fontSize
    }

    var body: some View {
        Text(season.displayName)
            .font(.custom("Inter18pt-SemiBold", size: fontSize))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .badgeSmall()
            .background(season.isActive ? Color.brandNavy : Color.gray, in: Capsule())
            .accessibilityLabel("\(season.displayName), \(season.isActive ? "Active" : "Archived") season")
    }
}

/// Filtered empty state view for when filters produce no results
struct FilteredEmptyStateView: View {
    let filterDescription: String
    let onClearFilters: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundStyle(.gray)

            Text("No Results")
                .font(.displayMedium)

            Text("No items match \(filterDescription)")
                .font(.bodyMedium)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Clear Filters") {
                onClearFilters()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}
