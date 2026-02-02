//
//  CoachMyAthletesView.swift
//  PlayerPath
//
//  Created by Assistant on 12/2/25.
//  Unified view showing all athletes a coach works with
//

import SwiftUI

/// Unified dashboard showing all athletes the coach has access to
struct CoachMyAthletesView: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @EnvironmentObject private var sharedFolderManager: SharedFolderManager
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var athleteGroups: [AthleteGroup] = []

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading athletes...")
            } else if athleteGroups.isEmpty {
                EmptyAthletesView()
            } else {
                List {
                    ForEach(athleteGroups) { group in
                        Section {
                            NavigationLink(destination: AthleteDetailView(athleteGroup: group)) {
                                AthleteGroupRow(group: group)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("My Athletes")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadAthletes()
        }
        .refreshable {
            await loadAthletes()
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
    }

    private func loadAthletes() async {
        guard let coachID = authManager.userID else {
            errorMessage = "Not authenticated"
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            // Load all folders shared with this coach
            try await sharedFolderManager.loadCoachFolders(coachID: coachID)

            // Group folders by athlete
            athleteGroups = groupFoldersByAthlete(sharedFolderManager.coachFolders)
        } catch {
            errorMessage = "Failed to load athletes: \(error.localizedDescription)"
        }
    }

    private func groupFoldersByAthlete(_ folders: [SharedFolder]) -> [AthleteGroup] {
        var groups: [String: AthleteGroup] = [:]

        for folder in folders {
            let athleteID = folder.ownerAthleteID
            let athleteName = folder.ownerAthleteName ?? "Unknown Athlete"

            if var existing = groups[athleteID] {
                existing.folders.append(folder)
                groups[athleteID] = existing
            } else {
                groups[athleteID] = AthleteGroup(
                    athleteID: athleteID,
                    athleteName: athleteName,
                    folders: [folder]
                )
            }
        }

        return groups.values.sorted { $0.athleteName < $1.athleteName }
    }
}

// MARK: - Athlete Group Model

struct AthleteGroup: Identifiable {
    let athleteID: String
    let athleteName: String
    var folders: [SharedFolder]

    var id: String { athleteID }

    var totalVideos: Int {
        folders.reduce(0) { $0 + ($1.videoCount ?? 0) }
    }

    var folderCount: Int {
        folders.count
    }
}

// MARK: - Athlete Group Row

struct AthleteGroupRow: View {
    let group: AthleteGroup

    var body: some View {
        HStack(spacing: 16) {
            // Athlete icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 60, height: 60)

                Image(systemName: "figure.run")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(group.athleteName)
                    .font(.headline)

                HStack(spacing: 12) {
                    Label("\(group.folderCount)", systemImage: "folder.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Label("\(group.totalVideos)", systemImage: "video")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Athlete Detail View

struct AthleteDetailView: View {
    let athleteGroup: AthleteGroup
    @EnvironmentObject private var authManager: ComprehensiveAuthManager

    var body: some View {
        List {
            // Summary Section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(athleteGroup.athleteName)
                                .font(.title2)
                                .fontWeight(.bold)

                            HStack(spacing: 12) {
                                Label("\(athleteGroup.folderCount) folder\(athleteGroup.folderCount == 1 ? "" : "s")", systemImage: "folder")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Label("\(athleteGroup.totalVideos) video\(athleteGroup.totalVideos == 1 ? "" : "s")", systemImage: "video")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()
                    }
                }
                .padding(.vertical, 8)
            }

            // Folders Section
            Section("Shared Folders") {
                ForEach(athleteGroup.folders) { folder in
                    NavigationLink(destination: CoachFolderDetailView(folder: folder)) {
                        FolderRowView(folder: folder)
                    }
                }
            }

            // Recent Activity (TODO: Implement)
            Section("Recent Activity") {
                Text("Recent video uploads and updates will appear here")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
        .navigationTitle(athleteGroup.athleteName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Folder Row View

struct FolderRowView: View {
    let folder: SharedFolder

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.title2)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text(folder.name)
                    .font(.headline)

                if let videoCount = folder.videoCount {
                    Text("\(videoCount) video\(videoCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let updatedAt = folder.updatedAt {
                    Text("Updated \(updatedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Empty State

struct EmptyAthletesView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.3")
                .font(.system(size: 70))
                .foregroundStyle(.gray.opacity(0.5))

            Text("No Athletes Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("When athletes invite you to view their videos, they will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CoachMyAthletesView()
            .environmentObject(ComprehensiveAuthManager())
            .environmentObject(SharedFolderManager.shared)
    }
}
