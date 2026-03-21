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
import FirebaseFirestore
import Combine

/// Root view for coaches — card-based dashboard with quick actions
struct CoachDashboardView: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @EnvironmentObject private var sharedFolderManager: SharedFolderManager
    @ObservedObject private var invitationManager = CoachInvitationManager.shared
    @ObservedObject private var activityNotifService = ActivityNotificationService.shared
    @State private var showingQuickRecord = false
    @State private var showingInviteAthlete = false
    @State private var showingProfile = false
    @State private var showingInvitations = false
    @State private var navigationPath = NavigationPath()
    @ObservedObject private var archiveManager = CoachFolderArchiveManager.shared

    /// Recent folders sorted by updatedAt, excluding archived
    private var recentFolders: [SharedFolder] {
        sharedFolderManager.coachFolders
            .filter { !archiveManager.isArchived($0.id ?? "") }
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(spacing: 20) {
                        // Pending invitations banner
                        PendingInvitationsBanner(showingInvitations: $showingInvitations)

                        // Quick Actions
                        quickActionsSection

                        // Recent Athletes
                        if !recentFolders.isEmpty {
                            recentAthletesSection
                        }

                        // All Athletes list
                        CoachAthletesListView(showingInvitations: $showingInvitations)
                    }
                    .padding()
                }
                .refreshable {
                    await reloadData()
                }

                // In-app notification banner
                if let banner = activityNotifService.incomingBanner {
                    ActivityNotificationBanner(notification: banner, onDismiss: {
                        activityNotifService.dismissBanner()
                    }, onTap: {
                        handleNotificationTap(banner)
                    })
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: banner.id)
                    .zIndex(100)
                }
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            Haptics.light()
                            showingInvitations = true
                        } label: {
                            Image(systemName: "envelope.badge")
                                .foregroundColor(.green)
                        }
                        .overlay(alignment: .topTrailing) {
                            if invitationManager.pendingInvitationsCount > 0 {
                                Text("\(invitationManager.pendingInvitationsCount)")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .frame(width: 16, height: 16)
                                    .background(Color.red)
                                    .clipShape(Circle())
                                    .offset(x: 6, y: -6)
                            }
                        }

                        Button {
                            showingProfile = true
                        } label: {
                            Image(systemName: "gearshape")
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            .navigationDestination(for: SharedFolder.self) { folder in
                CoachFolderDetailView(folder: folder)
            }
            .sheet(isPresented: $showingInvitations) {
                CoachInvitationsView()
            }
            .sheet(isPresented: $showingProfile) {
                NavigationStack {
                    CoachProfileView()
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") { showingProfile = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $showingInviteAthlete) {
                InviteAthleteSheet()
            }
            .fullScreenCover(isPresented: $showingQuickRecord) {
                CoachQuickRecordFlow()
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToCoachFolder)) { note in
                guard let folderID = note.object as? String,
                      let folder = sharedFolderManager.coachFolders.first(where: { $0.id == folderID }) else { return }
                navigationPath.append(folder)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openCoachInvitations)) { _ in
                showingInvitations = true
            }
            .onChange(of: invitationManager.pendingInvitationsCount) { _, count in
                // Auto-open invitations for new coaches with pending invites and no folders
                guard count > 0, sharedFolderManager.coachFolders.isEmpty else { return }
                showingInvitations = true
            }
        }
        .tint(.green)
        .task {
            if let coachID = authManager.userID {
                CoachFolderArchiveManager.shared.configure(coachUID: coachID)
            }
        }
        .onDisappear {
            sharedFolderManager.stopCoachFoldersListener()
            Task { @MainActor in
                CoachInvitationManager.shared.stopInvitationsListener()
            }
            ActivityNotificationService.shared.stopListening()
        }
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        HStack(spacing: 12) {
            // Record Practice button
            Button {
                Haptics.medium()
                showingQuickRecord = true
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "video.fill.badge.plus")
                        .font(.title2)
                    Text("Record Practice")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 80)
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(14)
            }

            // Invite Athlete button
            Button {
                Haptics.light()
                showingInviteAthlete = true
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "person.badge.plus")
                        .font(.title2)
                    Text("Invite Athlete")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 80)
                .background(Color(.secondarySystemBackground))
                .foregroundColor(.primary)
                .cornerRadius(14)
            }
        }
    }

    // MARK: - Recent Athletes

    private var recentAthletesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(recentFolders.prefix(5)) { folder in
                        Button {
                            navigationPath.append(folder)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: "figure.baseball")
                                    .font(.title2)
                                    .foregroundColor(.green)
                                    .frame(width: 40, height: 40)
                                    .background(Color.green.opacity(0.1))
                                    .clipShape(Circle())

                                Text(folder.ownerAthleteName ?? folder.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)

                                HStack(spacing: 4) {
                                    Image(systemName: "video")
                                    Text("\(folder.videoCount ?? 0)")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            .frame(width: 120)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
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
            ErrorHandlerService.shared.handle(error, context: "CoachDashboard.reloadData", showAlert: false)
        }
    }

    private func handleNotificationTap(_ notification: ActivityNotification) {
        switch notification.type {
        case .newVideo:
            if let folderID = notification.targetID {
                NotificationCenter.default.post(
                    name: .navigateToCoachFolder,
                    object: folderID
                )
            }
        case .invitationReceived, .invitationAccepted:
            showingInvitations = true
        case .coachComment, .accessRevoked:
            break // Already on the dashboard
        }

        // Mark the notification as read
        if let notifID = notification.id, let coachID = authManager.userID {
            Task {
                await ActivityNotificationService.shared.markRead(notifID, forUserID: coachID)
            }
        }
    }
}

// MARK: - My Athletes List View

struct CoachAthletesListView: View {
    @Binding var showingInvitations: Bool
    @EnvironmentObject private var sharedFolderManager: SharedFolderManager
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @ObservedObject private var invitationManager = CoachInvitationManager.shared
    @ObservedObject private var archiveManager = CoachFolderArchiveManager.shared
    @State private var searchText = ""
    @State private var showingArchived = false
    @State private var cachedActiveGroups: [CoachAthleteGroup] = []
    @State private var cachedArchivedGroups: [CoachAthleteGroup] = []
    @State private var cachedFilteredGroups: [CoachAthleteGroup] = []

    var body: some View {
        Group {
            if sharedFolderManager.isLoading && sharedFolderManager.coachFolders.isEmpty {
                ProgressView("Loading athletes...")
            } else if sharedFolderManager.coachFolders.isEmpty {
                CoachEmptyStateView(showingInvitations: $showingInvitations)
            } else {
                LazyVStack(spacing: 20) {
                        ForEach(cachedFilteredGroups, id: \CoachAthleteGroup.athleteID) { group in
                            AthleteSection(
                                athleteID: group.athleteID,
                                athleteName: group.athleteName,
                                folders: group.folders
                            )
                        }

                        // Archived folders toggle
                        if !cachedArchivedGroups.isEmpty {
                            Button {
                                withAnimation { showingArchived.toggle() }
                                Haptics.light()
                            } label: {
                                HStack {
                                    Image(systemName: showingArchived ? "archivebox.fill" : "archivebox")
                                        .foregroundColor(.secondary)
                                    Text(showingArchived ? "Hide Archived" : "Show Archived (\(cachedArchivedGroups.flatMap(\.folders).count))")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Image(systemName: showingArchived ? "chevron.up" : "chevron.down")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(.cornerLarge)
                            }
                            .buttonStyle(.plain)

                            if showingArchived {
                                ForEach(cachedArchivedGroups, id: \CoachAthleteGroup.athleteID) { group in
                                    AthleteSection(
                                        athleteID: group.athleteID,
                                        athleteName: group.athleteName,
                                        folders: group.folders,
                                        isArchived: true
                                    )
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                }
            }
        }
        .onAppear { AnalyticsService.shared.trackScreenView(screenName: "Coach Dashboard", screenClass: "CoachDashboardView") }
        .task { updateFolderGroups() }
        .searchable(text: $searchText, prompt: "Search athletes")
        .onChange(of: searchText) { _, _ in updateFolderGroups() }
        .onChange(of: sharedFolderManager.coachFolders) { _, _ in updateFolderGroups() }
        .onChange(of: archiveManager.archivedFolderIDs) { _, _ in updateFolderGroups() }
    }

    private func updateFolderGroups() {
        var activeFolders: [String: [SharedFolder]] = [:]
        var archivedFolders: [String: [SharedFolder]] = [:]

        for folder in sharedFolderManager.coachFolders {
            if archiveManager.isArchived(folder.id ?? "") {
                archivedFolders[folder.ownerAthleteID, default: []].append(folder)
            } else {
                activeFolders[folder.ownerAthleteID, default: []].append(folder)
            }
        }

        func buildGroups(_ dict: [String: [SharedFolder]]) -> [CoachAthleteGroup] {
            dict.map { athleteID, folders in
                CoachAthleteGroup(
                    athleteID: athleteID,
                    athleteName: folders.first?.ownerAthleteName ?? "Unknown Athlete",
                    folders: folders
                )
            }.sorted { $0.athleteName < $1.athleteName }
        }

        let activeGroups = buildGroups(activeFolders)
        cachedArchivedGroups = buildGroups(archivedFolders)
        cachedActiveGroups = activeGroups

        if searchText.isEmpty {
            cachedFilteredGroups = activeGroups
        } else {
            let q = searchText.lowercased()
            cachedFilteredGroups = activeGroups.filter {
                $0.athleteName.lowercased().contains(q) ||
                $0.folders.contains(where: { $0.name.lowercased().contains(q) })
            }
        }
    }
}

// MARK: - Preview

#Preview {
    CoachDashboardView()
        .environmentObject(ComprehensiveAuthManager())
        .environmentObject(SharedFolderManager.shared)
}

