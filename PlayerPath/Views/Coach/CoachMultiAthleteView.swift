//
//  CoachMultiAthleteView.swift
//  PlayerPath
//
//  Side-by-side comparison of athletes for coaches.
//  Shows recent activity and video counts per athlete.
//

import SwiftUI

struct CoachMultiAthleteView: View {
    private var sharedFolderManager: SharedFolderManager { .shared }
    private var archiveManager: CoachFolderArchiveManager { .shared }
    @Environment(\.dismiss) private var dismiss

    private var athleteGroups: [AthleteComparisonData] {
        let grouped = Dictionary(grouping: sharedFolderManager.coachFolders.filter {
            !archiveManager.isArchived($0.id ?? "")
        }) { $0.ownerAthleteID }

        return grouped.map { athleteID, folders in
            AthleteComparisonData(
                athleteID: athleteID,
                athleteName: folders.first?.ownerAthleteName ?? "Unknown",
                folderCount: folders.count,
                totalVideos: folders.reduce(0) { $0 + ($1.videoCount ?? 0) },
                lastActivity: folders.compactMap(\.updatedAt).max()
            )
        }.sorted { $0.athleteName < $1.athleteName }
    }

    var body: some View {
        List {
            if athleteGroups.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "figure.baseball")
                        .font(.system(size: 40))
                        .foregroundColor(.brandNavy.opacity(0.4))
                    Text("No Athletes Yet")
                        .font(.headline)
                    Text("Athletes will appear here once they accept your invitation.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowBackground(Color.clear)
            } else {
                ForEach(athleteGroups) { athlete in
                    AthleteComparisonRow(data: athlete)
                }
            }
        }
        .navigationTitle("Athletes Overview")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Data Model

struct AthleteComparisonData: Identifiable {
    var id: String { athleteID }
    let athleteID: String
    let athleteName: String
    let folderCount: Int
    let totalVideos: Int
    let lastActivity: Date?
}

// MARK: - Row

private struct AthleteComparisonRow: View {
    let data: AthleteComparisonData

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "figure.baseball")
                    .foregroundColor(.brandNavy)
                    .frame(width: 32, height: 32)
                    .background(Color.brandNavy.opacity(0.1))
                    .clipShape(Circle())

                Text(data.athleteName)
                    .font(.headline)
            }

            HStack(spacing: 16) {
                StatPill(icon: "folder.fill", value: "\(data.folderCount)", label: "Folders")
                StatPill(icon: "video.fill", value: "\(data.totalVideos)", label: "Videos")

                if let lastActivity = data.lastActivity {
                    Spacer()
                    Text(lastActivity.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Stat Pill

private struct StatPill: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(.brandNavy)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
