//
//  NeedsReviewQueueCard.swift
//  PlayerPath
//
//  Dashboard card showing aggregated athlete-shared clips that the coach
//  hasn't yet reviewed. Sibling of ReviewQueueCard ("My Drafts") — same
//  visual structure, different data source and accent color.
//

import SwiftUI

struct NeedsReviewQueueCard: View {
    let groups: [AthleteClipGroup]
    let totalCount: Int
    let onReviewAll: () -> Void
    let onNavigateToFolder: (String) -> Void

    private var accent: Color { .orange }

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(accent)
                    Text("Needs Your Review")
                        .font(.title3)
                        .fontWeight(.bold)
                        .fontDesign(.rounded)
                }

                Spacer()

                Text("\(totalCount) clip\(totalCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(accent.opacity(0.15)))
            }

            // Athlete rows
            VStack(spacing: 8) {
                ForEach(groups) { group in
                    Button {
                        onNavigateToFolder(group.folderID)
                    } label: {
                        athleteRow(group)
                    }
                    .buttonStyle(.plain)
                }
            }

            // CTA
            Button(action: onReviewAll) {
                Label("Review Clips", systemImage: "eye")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(accent)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: .cornerXLarge)
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.10), accent.opacity(0.03)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: .cornerXLarge)
                .stroke(accent.opacity(0.25), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
    }

    private func athleteRow(_ group: AthleteClipGroup) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.baseball")
                .font(.caption)
                .foregroundColor(accent)
                .frame(width: 28, height: 28)
                .background(accent.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(group.athleteName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text("\(group.clips.count) clip\(group.clips.count == 1 ? "" : "s") waiting")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: -8) {
                ForEach(Array(group.clips.prefix(3).enumerated()), id: \.element.id) { index, clip in
                    RemoteThumbnailView(
                        urlString: clip.thumbnailURL,
                        size: CGSize(width: 32, height: 32),
                        cornerRadius: 6,
                        folderID: clip.sharedFolderID,
                        videoFileName: clip.fileName
                    )
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(.systemBackground), lineWidth: 1.5)
                    )
                    .zIndex(Double(3 - index))
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
}
