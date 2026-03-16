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
import UIKit

/// Root view for coaches - replaces the athlete main tabs
struct CoachDashboardView: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @EnvironmentObject private var sharedFolderManager: SharedFolderManager
    @ObservedObject private var invitationManager = CoachInvitationManager.shared
    @ObservedObject private var activityNotifService = ActivityNotificationService.shared
    @State private var selectedTab: CoachTab = .myAthletes
    @State private var markReadTask: Task<Void, Never>?

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
        ZStack(alignment: .top) {
            TabView(selection: $selectedTab) {
                CoachAthletesListView()
                    .badge(activityNotifService.unreadCount > 0 ? activityNotifService.unreadCount : 0)
                    .tag(CoachTab.myAthletes)
                    .tabItem {
                        Label(CoachTab.myAthletes.rawValue, systemImage: CoachTab.myAthletes.icon)
                    }

                CoachProfileView()
                    .badge(invitationManager.pendingInvitationsCount > 0 ? invitationManager.pendingInvitationsCount : 0)
                    .tag(CoachTab.profile)
                    .tabItem {
                        Label(CoachTab.profile.rawValue, systemImage: CoachTab.profile.icon)
                    }
            }
            .tint(.green)

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
        .task {
            // Listeners are pre-started in AuthenticatedFlow. Just ensure
            // archive manager is configured (idempotent — guards on coachUID).
            if let coachID = authManager.userID {
                CoachFolderArchiveManager.shared.configure(coachUID: coachID)
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            // Mark all notifications read when coach views their athletes list
            if newTab == .myAthletes, let coachID = authManager.userID {
                markReadTask?.cancel()
                markReadTask = Task {
                    await ActivityNotificationService.shared.markAllRead(forUserID: coachID)
                }
            }
        }
        .onDisappear {
            // Listeners are managed by AuthenticatedFlow and guarded against
            // duplicate starts, so we only stop them when the coach flow
            // is fully torn down (sign-out).
            sharedFolderManager.stopCoachFoldersListener()
            Task { @MainActor in
                CoachInvitationManager.shared.stopInvitationsListener()
            }
            ActivityNotificationService.shared.stopListening()
        }
    }

    private func handleNotificationTap(_ notification: ActivityNotification) {
        switch notification.type {
        case .newVideo:
            // targetID is a folderID — switch to athletes tab and navigate to that folder
            if let folderID = notification.targetID {
                selectedTab = .myAthletes
                // Post after the current run loop tick so the tab switch completes first
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms — enough for tab transition
                    NotificationCenter.default.post(
                        name: .navigateToCoachFolder,
                        object: folderID
                    )
                }
            }
        case .invitationReceived, .invitationAccepted:
            // Open invitations sheet
            NotificationCenter.default.post(name: .openCoachInvitations, object: nil)
        case .coachComment, .accessRevoked:
            // Switch to athletes list — no specific deep link available without videoID+folderID pair
            selectedTab = .myAthletes
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
    @EnvironmentObject private var sharedFolderManager: SharedFolderManager
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @ObservedObject private var invitationManager = CoachInvitationManager.shared
    @ObservedObject private var archiveManager = CoachFolderArchiveManager.shared
    @State private var searchText = ""
    @State private var showingInvitations = false
    @State private var showingError = false
    @State private var errorMessage: String?
    @State private var navigationPath = NavigationPath()
    @State private var showingArchived = false
    @State private var hasAutoShownInvitations = false
    @State private var cachedActiveGroups: [CoachAthleteGroup] = []
    @State private var cachedArchivedGroups: [CoachAthleteGroup] = []
    @State private var cachedFilteredGroups: [CoachAthleteGroup] = []

    var body: some View {
        NavigationStack(path: $navigationPath) {
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
            .onAppear { AnalyticsService.shared.trackScreenView(screenName: "Coach Dashboard", screenClass: "CoachDashboardView") }
            .task { updateFolderGroups() }
            .onChange(of: searchText) { _, _ in updateFolderGroups() }
            .onChange(of: sharedFolderManager.coachFolders) { _, _ in updateFolderGroups() }
            .onChange(of: archiveManager.archivedFolderIDs) { _, _ in updateFolderGroups() }
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
            .navigationDestination(for: SharedFolder.self) { folder in
                CoachFolderDetailView(folder: folder)
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
                // Auto-open invitations sheet the first time a new coach with no accepted
                // folders lands on the dashboard and has pending invites waiting.
                guard !hasAutoShownInvitations,
                      count > 0,
                      sharedFolderManager.coachFolders.isEmpty else { return }
                hasAutoShownInvitations = true
                showingInvitations = true
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

    // MARK: - Cache

    private func updateFolderGroups() {
        // Single-pass partition: active vs archived folders, then group by athlete
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

        // Filter groups by athlete name or folder name matching searchText
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

// MARK: - Supporting Types

struct CoachAthleteGroup {
    let athleteID: String
    let athleteName: String
    let folders: [SharedFolder]
}

// MARK: - Athlete Section Component

struct AthleteSection: View {
    let athleteID: String
    let athleteName: String
    let folders: [SharedFolder]
    var isArchived: Bool = false

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
                        HStack(spacing: 6) {
                            Text(athleteName)
                                .font(.headline)
                                .foregroundColor(isArchived ? .secondary : .primary)
                            if isArchived {
                                Image(systemName: "archivebox.fill")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

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
                .cornerRadius(.cornerLarge)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(athleteName)
            .accessibilityHint(isExpanded ? "Collapse" : "Expand")

            // Folder list (expandable)
            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(folders) { folder in
                        NavigationLink(destination: CoachFolderDetailView(folder: folder)) {
                            CoachFolderRowView(folder: folder)
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

struct CoachFolderRowView: View {
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
                    Label("\(folder.videoCount ?? 0)", systemImage: "video")
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
    @State private var showingInviteAthlete = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "person.3.sequence")
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .green.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            // Welcome text
            VStack(spacing: 12) {
                Text("Welcome, Coach!")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Connect with athletes to view their game videos, send practice drills, and provide feedback.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            // Action buttons
            VStack(spacing: 12) {
                // Primary: Invite Athlete
                Button(action: {
                    Haptics.medium()
                    showingInviteAthlete = true
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "person.badge.plus")
                            .font(.title3)
                        Text("Invite an Athlete")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                }
                .buttonStyle(.plain)

                // Secondary: Check Invitations
                Button(action: {
                    Haptics.light()
                    showingInvitations = true
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "envelope.open")
                            .font(.title3)
                        Text("Check Pending Invitations")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color(.systemGray6))
                    .foregroundColor(.primary)
                    .cornerRadius(14)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .sheet(isPresented: $showingInviteAthlete) {
            InviteAthleteSheet()
        }
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
                .cornerRadius(.cornerLarge)
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

// MARK: - Coach Folder Archive Manager

/// Tracks which folders a coach has locally archived, stored in UserDefaults.
/// Archiving is per-coach (keyed by coach UID) and per-device — it only hides the folder
/// from the list without revoking Firestore access.
@MainActor
class CoachFolderArchiveManager: ObservableObject {
    static let shared = CoachFolderArchiveManager()

    @Published private(set) var archivedFolderIDs: Set<String> = []

    private var coachUID: String = ""
    private var defaultsKey: String { "archivedCoachFolders_\(coachUID)" }

    private init() {}

    func configure(coachUID: String) {
        guard coachUID != self.coachUID else { return }
        self.coachUID = coachUID
        let stored = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        archivedFolderIDs = Set(stored)
    }

    func archive(folderID: String) {
        archivedFolderIDs.insert(folderID)
        persist()
    }

    func unarchive(folderID: String) {
        archivedFolderIDs.remove(folderID)
        persist()
    }

    func isArchived(_ folderID: String) -> Bool {
        archivedFolderIDs.contains(folderID)
    }

    private func persist() {
        UserDefaults.standard.set(Array(archivedFolderIDs), forKey: defaultsKey)
    }
}

// MARK: - Coach Invitations Manager

@MainActor
class CoachInvitationManager: ObservableObject {
    static let shared = CoachInvitationManager()

    @Published var pendingInvitationsCount: Int = 0
    @Published var pendingInvitations: [CoachInvitation] = []
    @Published var listenerError: String?

    private var invitationsListener: ListenerRegistration?

    private init() {}

    deinit {
        invitationsListener?.remove()
        invitationsListener = nil
    }

    /// Starts a real-time listener for pending invitations. Replaces one-shot checkPendingInvitations.
    @MainActor
    func startInvitationsListener(forCoachEmail email: String) {
        // Skip if listener is already active
        guard invitationsListener == nil else { return }
        let db = Firestore.firestore()
        invitationsListener = db.collection("invitations")
            .whereField("coachEmail", isEqualTo: email.lowercased())
            .whereField("status", isEqualTo: "pending")
            .whereField("expiresAt", isGreaterThan: Timestamp(date: Date()))
            .limit(to: 50)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if error != nil {
                    Task { @MainActor in
                        self.listenerError = "Unable to refresh invitations."
                    }
                    return
                }
                let invitations = snapshot?.documents.compactMap { doc -> CoachInvitation? in
                    var inv = try? doc.data(as: CoachInvitation.self)
                    inv?.id = doc.documentID
                    return inv
                } ?? []
                Task { @MainActor in
                    self.listenerError = nil
                    self.pendingInvitations = invitations
                    self.pendingInvitationsCount = invitations.count
                }
            }
    }

    func stopInvitationsListener() {
        invitationsListener?.remove()
        invitationsListener = nil
        listenerError = nil
    }

    @MainActor
    func checkPendingInvitations(forCoachEmail email: String) async {
        do {
            let invitations = try await FirestoreManager.shared.fetchPendingInvitations(forEmail: email)
            pendingInvitations = invitations
            pendingInvitationsCount = invitations.count
        } catch {
            pendingInvitationsCount = 0
            pendingInvitations = []
        }
    }

    @MainActor
    func acceptInvitation(_ invitation: CoachInvitation, authManager: ComprehensiveAuthManager? = nil) async throws {
        // Accept the invitation via SharedFolderManager (passes authManager for athlete limit enforcement)
        try await SharedFolderManager.shared.acceptInvitation(invitation, authManager: authManager)

        // Refresh pending invitations
        await checkPendingInvitations(forCoachEmail: invitation.coachEmail)

        Haptics.success()
    }

    @MainActor
    func declineInvitation(_ invitation: CoachInvitation) async throws {
        // Decline the invitation via SharedFolderManager
        try await SharedFolderManager.shared.declineInvitation(invitation)

        // Refresh pending invitations
        await checkPendingInvitations(forCoachEmail: invitation.coachEmail)

        Haptics.light()
    }
}

// MARK: - Preview

#Preview {
    CoachDashboardView()
        .environmentObject(ComprehensiveAuthManager())
        .environmentObject(SharedFolderManager.shared)
}

