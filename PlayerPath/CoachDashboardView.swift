//
//  CoachDashboardView.swift
//  PlayerPath
//
//  Created by Assistant on 11/21/25.
//  Main dashboard for coaches showing all athletes and shared folders
//  Updated with critical bug fixes and improvements
//

import SwiftUI
import FirebaseAuth
import Combine
import UIKit

/// Root view for coaches - replaces the athlete main tabs
struct CoachDashboardView: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @EnvironmentObject private var sharedFolderManager: SharedFolderManager
    @ObservedObject private var invitationManager = CoachInvitationManager.shared
    @State private var selectedTab: CoachTab = .myAthletes
    @State private var loadTask: Task<Void, Never>?

    enum CoachTab: String, CaseIterable {
        case myAthletes = "My Athletes"
        case profile = "Profile"

        var icon: String {
            switch self {
            case .myAthletes: return "person.3.fill"
            case .profile: return "person.circle.fill"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            CoachAthletesListView()
                .tag(CoachTab.myAthletes)
                .tabItem {
                    Label(CoachTab.myAthletes.rawValue, systemImage: CoachTab.myAthletes.icon)
                }

            Group {
                if invitationManager.pendingInvitationsCount > 0 {
                    CoachProfileView()
                        .badge(invitationManager.pendingInvitationsCount)
                        .tag(CoachTab.profile)
                        .tabItem {
                            Label(CoachTab.profile.rawValue, systemImage: CoachTab.profile.icon)
                        }
                } else {
                    CoachProfileView()
                        .tag(CoachTab.profile)
                        .tabItem {
                            Label(CoachTab.profile.rawValue, systemImage: CoachTab.profile.icon)
                        }
                }
            }
        }
        .tint(.green) // Coach theme color
        .task {
            loadTask = Task {
                await loadCoachData()
                guard !Task.isCancelled else { return }

                if let coachEmail = authManager.userEmail {
                    await invitationManager.checkPendingInvitations(forCoachEmail: coachEmail)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task {
                guard !Task.isCancelled else { return }
                if let coachEmail = authManager.userEmail {
                    await invitationManager.checkPendingInvitations(forCoachEmail: coachEmail)
                }
            }
        }
        .onDisappear {
            loadTask?.cancel()
        }
    }

    private func loadCoachData() async {
        guard let coachID = authManager.userID else { return }

        do {
            try await sharedFolderManager.loadCoachFolders(coachID: coachID)
        } catch {
            print("❌ Failed to load coach folders: \(error)")
        }
    }
}

// MARK: - My Athletes List View

struct CoachAthletesListView: View {
    @EnvironmentObject private var sharedFolderManager: SharedFolderManager
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @ObservedObject private var invitationManager = CoachInvitationManager.shared
    @State private var searchText = ""
    @State private var showingInvitations = false
    @State private var showingError = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                if sharedFolderManager.isLoading {
                    ProgressView("Loading athletes...")
                } else if sharedFolderManager.coachFolders.isEmpty {
                    CoachEmptyStateView(showingInvitations: $showingInvitations)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 20, pinnedViews: [.sectionHeaders]) {
                            Section {
                                PendingInvitationsBanner(showingInvitations: $showingInvitations)

                                ForEach(filteredGroups, id: \.athleteID) { group in
                                    AthleteSection(
                                        athleteID: group.athleteID,
                                        athleteName: group.athleteName,
                                        folders: group.folders
                                    )
                                }
                            } header: {
                                PendingInvitationsStickyHeader(showingInvitations: $showingInvitations)
                            }
                        }
                        .padding()
                    }
                    .searchable(text: $searchText, prompt: "Search athletes")
                    .refreshable {
                        await reloadData()
                    }
                }
            }
            .navigationTitle("My Athletes")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Haptics.light()
                        showingInvitations = true
                    } label: {
                        Image(systemName: "envelope.badge")
                            .foregroundColor(.green)
                    }
                    .accessibilityLabel("Open Invitations")
                    .accessibilityHint("View and manage pending invitations")
                }
            }
            .sheet(isPresented: $showingInvitations) {
                CoachInvitationsView()
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {
                    Haptics.light()
                }
            } message: {
                Text(errorMessage ?? "An error occurred")
            }
        }
    }

    @MainActor private func reloadData() async {
        guard let coachID = authManager.userID else { return }
        do {
            try await sharedFolderManager.loadCoachFolders(coachID: coachID)

            if let coachEmail = authManager.userEmail {
                await invitationManager.checkPendingInvitations(forCoachEmail: coachEmail)
            }
        } catch {
            errorMessage = "Failed to reload data: \(error.localizedDescription)"
            showingError = true
            Haptics.error()
        }
    }

    // Group folders by athlete
    private var groupedFolders: [AthleteGroup] {
        let grouped = Dictionary(grouping: sharedFolderManager.coachFolders) { $0.ownerAthleteID }

        return grouped.map { athleteID, folders in
            AthleteGroup(
                athleteID: athleteID,
                athleteName: folders.first?.ownerAthleteName ?? "Unknown Athlete",
                folders: folders
            )
        }.sorted { $0.athleteName < $1.athleteName }
    }

    // Filter groups by athlete name or folder name matching searchText
    private var filteredGroups: [AthleteGroup] {
        guard !searchText.isEmpty else {
            return groupedFolders
        }
        let lowercasedSearch = searchText.lowercased()

        return groupedFolders.filter { group in
            if group.athleteName.lowercased().contains(lowercasedSearch) {
                return true
            }
            // Check if any folder name matches search text
            if group.folders.contains(where: { $0.name.lowercased().contains(lowercasedSearch) }) {
                return true
            }
            return false
        }
    }
}

// MARK: - Supporting Types

struct AthleteGroup {
    let athleteID: String
    let athleteName: String
    let folders: [SharedFolder]
}

// MARK: - Athlete Section Component

struct AthleteSection: View {
    let athleteID: String
    let athleteName: String
    let folders: [SharedFolder]

    @State private var isExpanded = true

    var body: some View {
        VStack(spacing: 12) {
            // Athlete header
            Button(action: {
                Haptics.selection()
                withAnimation {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: "figure.baseball")
                        .font(.title3)
                        .foregroundColor(.green)
                        .frame(width: 40, height: 40)
                        .background(Color.green.opacity(0.1))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(athleteName)
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text("\(folders.count) shared folder\(folders.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.gray)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(athleteName)
            .accessibilityHint(isExpanded ? "Collapse" : "Expand")

            // Folder list (expandable)
            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(folders) { folder in
                        NavigationLink(destination: CoachFolderDetailView(folder: folder)) {
                            FolderRowView(folder: folder)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 12)
            }
        }
    }
}

// MARK: - Folder Row Component

struct FolderRowView: View {
    let folder: SharedFolder
    @EnvironmentObject private var authManager: ComprehensiveAuthManager

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.title2)
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text(folder.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                HStack(spacing: 12) {
                    Label("\(folder.videoCount ?? 0)", systemImage: "video.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let coachID = authManager.userID,
                       let permissions = folder.getPermissions(for: coachID) {
                        if permissions.canUpload {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        if permissions.canComment {
                            Image(systemName: "bubble.left.fill")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(folder.name)
    }
}

// MARK: - Empty State View

struct CoachEmptyStateView: View {
    @Binding var showingInvitations: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.3.sequence")
                .font(.system(size: 70))
                .foregroundColor(.gray.opacity(0.5))

            Text("No Athletes Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("You'll see shared folders here once athletes invite you to view their content.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: {
                Haptics.light()
                showingInvitations = true
            }) {
                Label("Check Invitations", systemImage: "envelope.open")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding()
    }
}

// MARK: - Pending Invitations Banner

struct PendingInvitationsBanner: View {
    @Binding var showingInvitations: Bool
    @ObservedObject private var invitationManager = CoachInvitationManager.shared

    var body: some View {
        if invitationManager.pendingInvitationsCount > 0 {
            Button(action: {
                Haptics.light()
                showingInvitations = true
            }) {
                HStack {
                    Image(systemName: "envelope.badge.fill")
                        .foregroundColor(.green)

                    Text("You have \(invitationManager.pendingInvitationsCount) pending invitation\(invitationManager.pendingInvitationsCount == 1 ? "" : "s")")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .padding()
                .background(
                    LinearGradient(
                        colors: [Color.green.opacity(0.1), Color.green.opacity(0.05)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pending Invitations")
            .accessibilityHint("Tap to view and respond to invitations")
        }
    }
}

struct PendingInvitationsStickyHeader: View {
    @Binding var showingInvitations: Bool
    @ObservedObject private var invitationManager = CoachInvitationManager.shared

    var body: some View {
        if invitationManager.pendingInvitationsCount > 0 {
            PendingInvitationsBanner(showingInvitations: $showingInvitations)
                .padding(.bottom, 8)
                .background(.thinMaterial)
        }
    }
}

// MARK: - Coach Invitations Manager

class CoachInvitationManager: ObservableObject {
    static let shared = CoachInvitationManager()

    @Published var pendingInvitationsCount: Int = 0
    @Published var pendingInvitations: [CoachInvitation] = []

    private init() {}

    @MainActor
    func checkPendingInvitations(forCoachEmail email: String) async {
        do {
            // Query Firestore for pending invitations
            let invitations = try await fetchPendingInvitations(for: email)
            pendingInvitations = invitations
            pendingInvitationsCount = invitations.count
        } catch {
            print("❌ Error checking invitations: \(error)")
            pendingInvitationsCount = 0
            pendingInvitations = []
        }
    }

    private func fetchPendingInvitations(for email: String) async throws -> [CoachInvitation] {
        // TODO: Implement actual Firestore query
        // For now, return empty array - this should query:
        // db.collection("coachInvitations")
        //   .whereField("coachEmail", isEqualTo: email)
        //   .whereField("status", isEqualTo: "pending")
        //   .getDocuments()

        return []
    }

    @MainActor
    func acceptInvitation(_ invitation: CoachInvitation) async throws {
        // TODO: Implement acceptance logic
        // 1. Update invitation status to "accepted"
        // 2. Add coach ID to folder's sharedWithCoachIDs array
        // 3. Add permissions to folder
        // 4. Refresh pending invitations

        await checkPendingInvitations(forCoachEmail: invitation.coachEmail)
    }

    @MainActor
    func declineInvitation(_ invitation: CoachInvitation) async throws {
        // TODO: Implement decline logic
        // 1. Update invitation status to "declined"
        // 2. Refresh pending invitations

        await checkPendingInvitations(forCoachEmail: invitation.coachEmail)
    }
}

// MARK: - Preview

#Preview {
    CoachDashboardView()
        .environmentObject(ComprehensiveAuthManager())
        .environmentObject(SharedFolderManager.shared)
}
