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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var authManager: ComprehensiveAuthManager

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }
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
        VStack(spacing: 0) {
            if let listenerError = sharedFolderManager.listenerError {
                folderErrorBanner(listenerError)
            }
            Group {
                if sharedFolderManager.isLoading && sharedFolderManager.coachFolders.isEmpty {
                    ProgressView("Loading athletes...")
                } else if sharedFolderManager.coachFolders.isEmpty {
                    CoachEmptyStateView(showingInvitations: $showingInvitations)
                } else {
                    athletesList
                }
            }
        }
        .navigationTitle("Athletes")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    // Inbox bell — mirrors Dashboard placement so coaches who
                    // spend most of their time on this tab can reach the
                    // activity feed without backing out to Dashboard.
                    NotificationBellToolbarButton()

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

                    Menu {
                        NavigationLink(destination: CoachMultiAthleteView()) {
                            Label("Multi-Athlete Stats", systemImage: "chart.bar.xaxis")
                        }
                        Button {
                            Haptics.light()
                            showingInviteAthlete = true
                        } label: {
                            Label("Invite Athlete", systemImage: "person.badge.plus")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.brandNavy)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search athletes")
        .refreshable {
            await reloadData()
        }
        // Re-run only when the signed-in coach changes — not on every appear
        // — so the initial folder group computation is stable across sheet
        // dismissals re-rendering this tab.
        .task(id: authManager.userID) { updateFolderGroups() }
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
            StartSessionSheet(onInviteAthlete: {
                showingInviteAthlete = true
            })
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

    // MARK: - Folder Error Banner

    /// Surfaces a stale-data warning when the shared-folders listener fails, so
    /// coaches don't make navigation decisions against silently cached folders.
    /// Retry re-runs the one-shot load.
    @ViewBuilder
    private func folderErrorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warning)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer(minLength: 8)
            Button("Retry") {
                Haptics.light()
                Task { await reloadData() }
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warning.opacity(0.1))
    }

    // MARK: - Athletes List

    private var athletesList: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Offline indicator
                if !ConnectivityMonitor.shared.isConnected {
                    Label("You're offline. Showing cached data.", systemImage: "wifi.slash")
                        .font(.subheadline)
                        .foregroundStyle(Theme.warning)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal)
                }

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
            .padding(.vertical)
            .padding(.horizontal, isRegularWidth ? 32 : 16)
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
            // Per-athlete grouping: multi-athlete parent accounts get one row per kid.
            // Legacy folders (no athleteUUID) fall back to the account UID.
            let key = folder.athleteUUID ?? folder.ownerAthleteID
            if archiveManager.isArchived(folder.id ?? "") {
                archivedFolders[key, default: []].append(folder)
            } else {
                activeFolders[key, default: []].append(folder)
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
