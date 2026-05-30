//
//  TournamentRow.swift
//  PlayerPath
//
//  List card for a multi-round golf tournament (SchemaV27). Shows the name,
//  date range, round count, and aggregate stroke-play total + to-par derived
//  from the tournament's scored rounds.
//

import SwiftUI

struct TournamentRow: View {
    let tournament: GolfTournament

    private var roundCount: Int { (tournament.rounds ?? []).count }

    private var dateText: String? {
        guard let start = tournament.startDate else { return nil }
        if let end = tournament.endDate, !Calendar.current.isDate(start, inSameDayAs: end) {
            return "\(DateFormatter.monthDay.string(from: start)) – \(DateFormatter.monthDay.string(from: end))"
        }
        return DateFormatter.mediumDate.string(from: start)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let dateText { parts.append(dateText) }
        if let loc = tournament.location, !loc.isEmpty { parts.append(loc) }
        parts.append(roundCount == 1 ? "1 round" : "\(roundCount) rounds")
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .foregroundStyle(Color.brandNavy)
                .font(.title3)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(tournament.name)
                    .font(.bodyMedium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.bodySmall)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let total = tournament.totalStrokes {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(total)")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let toPar = tournament.displayToPar {
                        Text(toPar)
                            .font(.bodySmall)
                            .foregroundStyle(toParColor)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tournament \(tournament.name), \(subtitle)" +
                            (tournament.totalStrokes.map { ", total \($0)" } ?? ""))
    }

    private var toParColor: Color {
        guard let toPar = tournament.totalToPar else { return .secondary }
        if toPar < 0 { return .green }
        if toPar > 0 { return .red }
        return .secondary
    }
}
