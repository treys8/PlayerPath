//
//  DrillCardSummaryView.swift
//  PlayerPath
//
//  Read-only card view for displaying drill card results.
//

import SwiftUI

struct DrillCardSummaryView: View {
    let card: DrillCard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "clipboard.fill")
                    .foregroundColor(.green)
                Text(card.template?.displayName ?? "Drill Card")
                    .font(.headline)
                Spacer()
                if let overall = card.overallRating {
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= overall ? "star.fill" : "star")
                                .font(.caption2)
                                .foregroundColor(star <= overall ? .yellow : .gray.opacity(0.3))
                        }
                    }
                }
            }

            // Coach info
            HStack(spacing: 4) {
                Image(systemName: "person.fill.checkmark")
                    .font(.caption2)
                Text(card.coachName)
                    .font(.caption)
                if let date = card.createdAt {
                    Text("·")
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                }
            }
            .foregroundColor(.secondary)

            // Category ratings
            ForEach(card.categories, id: \.name) { cat in
                HStack {
                    Text(cat.name)
                        .font(.caption)
                        .frame(width: 100, alignment: .leading)

                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= cat.rating ? "star.fill" : "star")
                                .font(.caption2)
                                .foregroundColor(star <= cat.rating ? ratingColor(cat.rating) : .gray.opacity(0.3))
                        }
                    }

                    if let notes = cat.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            // Summary
            if let summary = card.summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
    }

    private func ratingColor(_ rating: Int) -> Color {
        switch rating {
        case 1...2: return .red
        case 3: return .orange
        case 4...5: return .green
        default: return .gray
        }
    }
}
