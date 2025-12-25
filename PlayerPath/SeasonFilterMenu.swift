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
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                if selectedSeasonID != nil {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundColor(.blue)
                }
            }
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
            .font(.system(size: fontSize))
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(season.isActive ? Color.blue : Color.gray)
            .cornerRadius(4)
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
                .foregroundColor(.gray)

            Text("No Results")
                .font(.title2)
                .fontWeight(.bold)

            Text("No items match \(filterDescription)")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Clear Filters") {
                onClearFilters()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}
