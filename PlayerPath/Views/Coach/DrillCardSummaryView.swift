//
//  DrillCardSummaryView.swift
//  PlayerPath
//
//  Read-only card view for displaying drill card results.
//

import SwiftUI

struct DrillCardSummaryView: View {
    let card: DrillCard
    /// Coach-only edit/delete affordances. When either is provided, an overflow
    /// menu appears in the header. Nil for the athlete (read-only) side.
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    private var hasActions: Bool { onEdit != nil || onDelete != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "clipboard.fill")
                    .foregroundColor(.brandNavy)
                Text(card.template?.displayName ?? "Drill Card")
                    .font(.headline)
                Spacer()
                if let overall = card.overallRating {
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= overall ? "star.fill" : "star")
                                .font(.caption2)
                                .foregroundColor(star <= overall ? ratingColor(overall) : .gray.opacity(0.3))
                        }
                    }
                }
                if hasActions {
                    Menu {
                        if let onEdit {
                            Button {
                                onEdit()
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                        }
                        if let onDelete {
                            Button(role: .destructive) {
                                onDelete()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Drill card options")
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
                            .lineLimit(2)
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
