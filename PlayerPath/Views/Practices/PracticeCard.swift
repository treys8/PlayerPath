//
//  PracticeCard.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI

struct PracticeCard: View {
    let practice: Practice

    private var practiceType: PracticeType {
        practice.type
    }

    var body: some View {
        HStack(spacing: 0) {
            // Accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(practiceType.color)
                .frame(width: 4)
                .padding(.vertical, 4)

            HStack(spacing: 12) {
                // Type icon
                Image(systemName: practiceType.icon)
                    .font(.title3)
                    .foregroundStyle(practiceType.color)
                    .frame(width: 28)

                // Info
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text((practice.date ?? .distantPast).formatted(date: .abbreviated, time: .omitted))
                            .font(.headline)
                            .fontWeight(.semibold)
                            .lineLimit(1)

                        if let season = practice.season {
                            SeasonBadge(season: season, fontSize: 8)
                        }
                    }

                    Text(practiceType.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Counts
                HStack(spacing: 10) {
                    let videoCount = practice.videoClips?.count ?? 0
                    if videoCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "video")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(videoCount)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }

                    let noteCount = practice.notes?.count ?? 0
                    if noteCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "note.text")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(noteCount)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }

                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: .cornerLarge, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

struct EmptyPracticesView: View {
    let onAddPractice: () -> Void

    var body: some View {
        EmptyStateView(
            systemImage: "figure.baseball",
            title: "No Practice Sessions Yet",
            message: "Create your first practice to track training",
            actionTitle: "Add Practice",
            action: onAddPractice
        )
    }
}
