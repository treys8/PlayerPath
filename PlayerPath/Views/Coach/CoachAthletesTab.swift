//
//  CoachAthletesTab.swift
//  PlayerPath
//
//  Dedicated Athletes tab for coaches. Shows athlete list grouped by
//  athlete with folder navigation. Extracted from CoachDashboardView.
//

import SwiftUI

struct CoachAthletesTab: View {
    private var sharedFolderManager: SharedFolderManager { .shared }
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    private var invitationManager: CoachInvitationManager { .shared }
    private var archiveManager: CoachFolderArchiveManager { .shared }
    @State private var searchText = ""
    @State private var showingArchived = false
    @State private var showingInviteAthlete = false
    @State private var showingInvitations = false
    @State private var showingStartSession = false
    @State private var cachedActiveGroups: [CoachAthleteGroup] = []
    @State private var cachedArchivedGroups: [CoachAthleteGroup] = []
    @State private var cachedFilteredGroups: [CoachAthleteGroup] = []
    @State private var searchDebounceTask: Task<Void, Never>?

    var body: some View {
        Group {
            if sharedFolderManager.isLoading && sharedFolderManager.coachFolders.isEmpty {
                ProgressView("Loading athletes...")
            } else if sharedFolderManager.coachFolders.isEmpty {
                CoachEmptyStateView(showingInvitations: $showingInvitations)
            } else {
                athletesList
            }
        }
        .navigationTitle("Athletes")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    if invitationManager.pendingInvitationsCount > 0 {
                        Button {
                            Haptics.light()
                            showingInvitations = true
                        } label: {
                            Image(systemName: "envelope.badge")
                                .foregroundColor(.brandNavy)
                        }
                        .overlay(alignment: .topTrailing) {
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
                        Haptics.medium()
                        showingStartSession = true
                    } label: {
                        Image(systemName: "record.circle")
                            .foregroundColor(.brandNavy)
                    }

                    NavigationLink(destination: CoachMultiAthleteView()) {
                        Image(systemName: "chart.bar.xaxis")
                            .foregroundColor(.brandNavy)
                    }

                    Button {
                        Haptics.light()
                        showingInviteAthlete = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .foregroundColor(.brandNavy)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search athletes")
        .refreshable {
            await reloadData()
        }
        .task { updateFolderGroups() }
        .onChange(of: searchText) { _, _ in
            debouncedFolderGroupUpdate()
        }
        .onChange(of: sharedFolderManager.coachFolders) { _, _ in
            debouncedFolderGroupUpdate()
        }
        .onChange(of: archiveManager.archivedFolderIDs) { _, _ in
            debouncedFolderGroupUpdate()
        }
        .onChange(of: invitationManager.pendingInvitationsCount) { _, count in
            if count > 0 && sharedFolderManager.coachFolders.isEmpty {
                showingInvitations = true
            }
        }
        .sheet(isPresented: $showingStartSession) {
            StartSessionSheet { _ in }
        }
        .sheet(isPresented: $showingInviteAthlete) {
            InviteAthleteSheet()
        }
        .sheet(isPresented: $showingInvitations) {
            NavigationStack {
                CoachInvitationsView()
                    .environmentObject(authManager)
            }
        }
        .onAppear {
            AnalyticsService.shared.trackScreenView(screenName: "Coach Athletes", screenClass: "CoachAthletesTab")
        }
    }

    // MARK: - Athletes List

    private var athletesList: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Pending invitations banner at top
                PendingInvitationsBanner(showingInvitations: $showingInvitations)

                ForEach(cachedFilteredGroups, id: \.athleteID) { group in
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
                        ForEach(cachedArchivedGroups, id: \.athleteID) { group in
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
            .padding()
        }
    }

    // MARK: - Data

    private func debouncedFolderGroupUpdate() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            updateFolderGroups()
        }
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

    @MainActor
    private func reloadData() async {
        guard let coachID = authManager.userID else { return }
        do {
            try await sharedFolderManager.loadCoachFolders(coachID: coachID)
            if let coachEmail = authManager.userEmail {
                await invitationManager.checkPendingInvitations(forCoachEmail: coachEmail)
            }
        } catch {
            ErrorHandlerService.shared.handle(error, context: "CoachAthletesTab.reloadData", showAlert: true)
        }
    }
}
