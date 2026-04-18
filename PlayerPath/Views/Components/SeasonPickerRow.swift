//
//  SeasonPickerRow.swift
//  PlayerPath
//
//  Reusable season selector used by game, practice, and bulk-import flows
//  so content can be routed to any of the athlete's seasons — including past
//  ones — rather than being forced to the active season.
//

import SwiftUI

struct SeasonPickerRow: View {
    let athlete: Athlete?
    @Binding var selection: Season?
    var allowsNone: Bool = false
    var noneLabel: String = "No Season"

    private var seasons: [Season] {
        (athlete?.seasons ?? [])
            .sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
    }

    var body: some View {
        Picker("Season", selection: $selection) {
            if allowsNone {
                Text(noneLabel).tag(Optional<Season>.none)
            }
            ForEach(seasons, id: \.id) { season in
                Text(rowLabel(for: season)).tag(Optional(season))
            }
        }
    }

    private func rowLabel(for season: Season) -> String {
        season.isActive ? "\(season.displayName) · Active" : season.displayName
    }
}
