//
//  ReviewQueueCard.swift
//  PlayerPath
//
//  Dashboard card showing aggregated clips grouped by athlete.
//  Drives two dashboard queues via `ClipQueueStyle`: coach's own
//  draft clips ("My Drafts") and athlete-shared clips awaiting
//  coach feedback ("Needs Your Review").
//

import SwiftUI

enum ClipQueueStyle {
    case myDrafts
    case needsReview

    var accent: Color {
        switch self {
        case .myDrafts: return .brandNavy
        case .needsReview: return .orange
        }
    }

    var title: String {
        switch self {
        case .myDrafts: return "My Drafts"
        case .needsReview: return "Needs Your Review"
        }
    }

    var headerIcon: String {
        switch self {
        case .myDrafts: return "square.and.pencil"
        case .needsReview: return "tray.full.fill"
        }
    }

    var rowSubtitleSuffix: String {
        switch self {
        case .myDrafts: return "to review"
        case .needsReview: return "waiting"
        }
    }

    var badgeOpacity: Double {
        self == .myDrafts ? 0.12 : 0.15
    }

    var gradientTopOpacity: Double {
        self == .myDrafts ? 0.08 : 0.10
    }

    var strokeOpacity: Double {
        self == .myDrafts ? 0.20 : 0.25
    }

    var rowIconBackgroundOpacity: Double {
        self == .myDrafts ? 0.10 : 0.12
    }
}

struct ClipQueueCard: View {
    let style: ClipQueueStyle
    let groups: [AthleteClipGroup]
    let totalCount: Int
    let onReviewAll: () -> Void
    let onNavigateToFolder: (String) -> Void

    var body: some View {
        VStack(spacing: 12) {
            header

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

            Button(action: onReviewAll) {
                Label("Review Clips", systemImage: "eye")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(style.accent)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: .cornerXLarge)
                .fill(
                    LinearGradient(
                        colors: [style.accent.opacity(style.gradientTopOpacity), style.accent.opacity(0.03)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: .cornerXLarge)
                .stroke(style.accent.opacity(style.strokeOpacity), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: style.headerIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(style.accent)
                Text(style.title)
                    .font(.title3)
                    .fontWeight(.bold)
                    .fontDesign(.rounded)
            }

            Spacer()

            Text("\(totalCount) clip\(totalCount == 1 ? "" : "s")")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(style.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(style.accent.opacity(style.badgeOpacity)))
        }
    }

    private static let ageFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private func ageColor(for date: Date) -> Color {
        let age = -date.timeIntervalSinceNow
        let day: TimeInterval = 86_400
        if age < day { return .green }
        if age < 3 * day { return .yellow }
        return .red
    }

    private func athleteRow(_ group: AthleteClipGroup) -> some View {
        let oldest = group.clips.compactMap(\.createdAt).min()

        return HStack(spacing: 10) {
            Image(systemName: "figure.baseball")
                .font(.caption)
                .foregroundColor(style.accent)
                .frame(width: 28, height: 28)
                .background(style.accent.opacity(style.rowIconBackgroundOpacity))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(group.athleteName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("\(group.clips.count) clip\(group.clips.count == 1 ? "" : "s") \(style.rowSubtitleSuffix)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if style == .needsReview, let oldest {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(ageColor(for: oldest))
                                .frame(width: 6, height: 6)
                            Text("oldest \(Self.ageFormatter.localizedString(for: oldest, relativeTo: Date()))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
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
