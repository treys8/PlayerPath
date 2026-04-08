//
//  CoachDashboardView.swift
//  PlayerPath
//
//  Created by Assistant on 11/21/25.
//  Dashboard tab for coaches — quick actions, recent activity, and
//  notification banners. Athletes list has moved to CoachAthletesTab.
//

import SwiftUI

/// Dashboard tab content for coaches — quick actions and recent athletes
struct CoachDashboardView: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    private var sharedFolderManager: SharedFolderManager { .shared }
    @Environment(CoachNavigationCoordinator.self) private var coordinator
    private var invitationManager: CoachInvitationManager { .shared }
    @ObservedObject private var activityNotifService = ActivityNotificationService.shared
    private var sessionManager: CoachSessionManager { .shared }
    @State private var showingStartSession = false
    @State private var showingInviteAthlete = false
    @State private var showingCamera = false
    @State private var isEndingSession = false
    @State private var isCompletingSession = false
    @State private var startingScheduledSessionID: String?
    @State private var showingCancelConfirmation = false
    @State private var sessionToCancel: CoachSession?
    private var archiveManager: CoachFolderArchiveManager { .shared }
    private var reviewQueue: ReviewQueueViewModel { .shared }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var cachedRecentFolders: [SharedFolder] = []
    @State private var cachedThisWeekSessionCount = 0
    @State private var cachedThisWeekClipCount = 0
    @State private var cachedThisWeekAthleteCount = 0
    @State private var isOverAthleteLimit = false
    @State private var fullAthleteCount = 0

    var body: some View {
        ZStack(alignment: .top) {
            if sharedFolderManager.isLoading && sharedFolderManager.coachFolders.isEmpty {
                DashboardSkeletonView()
            } else {
            ScrollView {
                VStack(spacing: 20) {
                    // Stale data warning
                    if let listenerError = sharedFolderManager.listenerError {
                        Label(listenerError, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }

                    // Live session card (top priority)
                    liveSessionSection

                    // Review queue (clips awaiting review across all folders)
                    reviewQueueSection

                    // Upcoming scheduled sessions
                    upcomingSessionsSection

                    // Over-limit banner
                    if isOverAthleteLimit {
                        CoachOverLimitBanner(
                            connectedCount: fullAthleteCount,
                            limit: authManager.coachAthleteLimit
                        )
                    }

                    // Quick Actions
                    quickActionsSection

                    if sharedFolderManager.coachFolders.isEmpty && sessionManager.sessions.isEmpty {
                        // Empty state for new coaches
                        gettingStartedSection
                    } else {
                        // Recent Athletes
                        if !cachedRecentFolders.isEmpty {
                            recentAthletesSection
                        }

                        // This week activity
                        thisWeekSection

                        // Summary stats
                        if !sharedFolderManager.coachFolders.isEmpty {
                            summarySection
                        }
                    }
                }
                .padding()
            }
            .refreshable {
                await reloadData()
            }

            } // end else (loading check)

            // In-app notification banner is handled by UserMainFlow's overlay
            // to avoid duplicate banners.
        }
        .navigationTitle(authManager.userDisplayName ?? "Dashboard")
        .alert("Cancel Session?", isPresented: $showingCancelConfirmation) {
            Button("Cancel Session", role: .destructive) {
                if let session = sessionToCancel, let sessionID = session.id {
                    Task {
                        do {
                            try await sessionManager.cancelScheduledSession(sessionID: sessionID)
                            Haptics.success()
                        } catch {
                            ErrorHandlerService.shared.handle(error, context: "CoachDashboard.cancelScheduled", showAlert: false)
                        }
                    }
                }
            }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("This scheduled session will be removed.")
        }
        .sheet(isPresented: $showingInviteAthlete) {
            InviteAthleteSheet()
        }
        .sheet(isPresented: $showingStartSession) {
            StartSessionSheet()
        }
        .fullScreenCover(isPresented: $showingCamera) {
            if let session = sessionManager.activeSession {
                DirectCameraRecorderView(
                    coachContext: CoachSessionContext(sessionID: session.id ?? "", session: session)
                )
            }
        }
        .onChange(of: showingCamera) { _, showing in
            if !showing {
                Task {
                    guard let coachID = authManager.userID else { return }
                    await sessionManager.fetchSessions(coachID: coachID)
                }
            }
        }
        .onChange(of: sessionManager.activeSession) { _, newValue in
            // Dismiss camera if session was ended/completed externally
            if newValue == nil && showingCamera {
                showingCamera = false
            }
        }
        .task {
            updateCachedValues()
            guard let coachID = authManager.userID else { return }
            reviewQueue.startListening(coachUID: coachID)
            await refreshAthleteLimit(coachID: coachID)
            if sessionManager.sessions.isEmpty {
                await sessionManager.fetchSessions(coachID: coachID)
            }
        }
        .onAppear {
            AnalyticsService.shared.trackScreenView(screenName: "Coach Dashboard", screenClass: "CoachDashboardView")
        }
        .onChange(of: sharedFolderManager.coachFolders) { _, _ in updateCachedValues() }
        .onChange(of: archiveManager.archivedFolderIDs) { _, _ in updateCachedValues() }
        .onChange(of: sessionManager.sessions) { _, _ in updateCachedValues() }
        .onChange(of: sessionManager.scheduledSessions) { _, _ in updateCachedValues() }
    }

    // MARK: - Live Session

    @State private var headerPulse = false

    @ViewBuilder
    private var liveSessionSection: some View {
        if let session = sessionManager.activeSession {
            let isLive = session.status == .live
            let headerColor: Color = isLive ? .red : .brandNavy

            VStack(spacing: 12) {
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(headerColor)
                            .frame(width: 8, height: 8)
                            .opacity(isLive && headerPulse ? 0.4 : 1.0)
                            .shadow(color: headerColor.opacity(0.8), radius: isLive && headerPulse ? 4 : 2)
                            .animation(isLive && !reduceMotion ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : nil, value: headerPulse)
                            .onAppear { if isLive { headerPulse = true } }

                        Text(isLive ? "Live Now" : "Session Ended")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [headerColor, headerColor.opacity(0.8)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                    }
                    Spacer()
                }

                LiveSessionCard(
                    session: session,
                    isEnding: isEndingSession,
                    onEnd: { endActiveSession(session) }
                )
                .contentShape(Rectangle())
                .onTapGesture { resumeSession(session) }

                if session.status == .reviewing {
                    HStack(spacing: 12) {
                        Button {
                            resumeSession(session)
                        } label: {
                            Label("Review Clips", systemImage: "eye")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.brandNavy)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }

                        Button {
                            completeActiveSession(session)
                        } label: {
                            Label("Complete", systemImage: "checkmark")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color(.secondarySystemBackground))
                                .foregroundColor(.primary)
                                .cornerRadius(10)
                        }
                        .disabled(isCompletingSession)
                    }
                }
            }
        }
    }

    // MARK: - Review Queue

    @ViewBuilder
    private var reviewQueueSection: some View {
        if reviewQueue.totalCount > 0 {
            ReviewQueueCard(
                groups: reviewQueue.groupedClips,
                totalCount: reviewQueue.totalCount,
                onReviewAll: {
                    // Navigate to the first athlete's folder
                    if let firstGroup = reviewQueue.groupedClips.first {
                        coordinator.navigateToFolder(
                            firstGroup.folderID,
                            folders: sharedFolderManager.coachFolders,
                            initialTab: .review
                        )
                    }
                },
                onNavigateToFolder: { folderID in
                    coordinator.navigateToFolder(
                        folderID,
                        folders: sharedFolderManager.coachFolders,
                        initialTab: .review
                    )
                }
            )
        }
    }

    // MARK: - Upcoming Sessions

    @ViewBuilder
    private var upcomingSessionsSection: some View {
        if !sessionManager.scheduledSessions.isEmpty {
            VStack(spacing: 12) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text("Upcoming Sessions")
                            .font(.title3)
                            .fontWeight(.bold)
                    }
                    Spacer()
                    Text("\(sessionManager.scheduledSessions.count)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.blue.opacity(0.12)))
                }

                ForEach(sessionManager.scheduledSessions) { session in
                    UpcomingSessionCard(
                        session: session,
                        isStarting: startingScheduledSessionID == session.id,
                        onStart: { startScheduledSession(session) },
                        onCancel: {
                            sessionToCancel = session
                            showingCancelConfirmation = true
                        }
                    )
                }
            }
        }
    }

    private func startScheduledSession(_ session: CoachSession) {
        guard let sessionID = session.id, startingScheduledSessionID == nil else { return }
        startingScheduledSessionID = sessionID
        Task {
            do {
                try await sessionManager.startScheduledSession(sessionID: sessionID)
                Haptics.success()
                showingCamera = true
            } catch {
                ErrorHandlerService.shared.handle(error, context: "CoachDashboard.startScheduledSession", showAlert: false)
            }
            startingScheduledSessionID = nil
        }
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(spacing: 16) {
            DashboardSectionHeader(title: "Quick Actions", icon: "bolt.fill", color: .brandNavy)

            HStack(spacing: 12) {
                if sessionManager.activeSession != nil {
                    QuickActionButton(
                        icon: "play.circle.fill",
                        title: "Resume Session",
                        color: .red
                    ) {
                        if let session = sessionManager.activeSession {
                            resumeSession(session)
                        }
                    }
                } else {
                    QuickActionButton(
                        icon: "plus.circle.fill",
                        title: "New Session",
                        color: .brandNavy
                    ) {
                        showingStartSession = true
                    }
                }

                QuickActionButton(
                    icon: "person.badge.plus",
                    title: "Invite Athlete",
                    color: .brandNavy.opacity(0.7)
                ) {
                    showingInviteAthlete = true
                }
            }
        }
    }

    // MARK: - Recent Athletes

    private var recentAthletesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DashboardSectionHeader(title: "Recent Athletes", icon: "clock.fill", color: .brandNavy)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(recentAthleteCards.prefix(5), id: \.athleteID) { card in
                        Button {
                            coordinator.selectedTab = .athletes
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: "figure.baseball")
                                    .font(.title2)
                                    .foregroundColor(.brandNavy)
                                    .frame(width: 40, height: 40)
                                    .background(Color.brandNavy.opacity(0.1))
                                    .clipShape(Circle())

                                Text(card.athleteName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)

                                HStack(spacing: 4) {
                                    Image(systemName: "video")
                                    Text("\(card.totalVideos)")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)

                                if card.unreadCount > 0 {
                                    HStack(spacing: 3) {
                                        Circle().fill(Color.red).frame(width: 6, height: 6)
                                        Text("\(card.unreadCount) new")
                                            .font(.caption2)
                                            .foregroundColor(.red)
                                    }
                                }
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

    private struct RecentAthleteCard {
        let athleteID: String
        let athleteName: String
        let totalVideos: Int
        let unreadCount: Int
        let mostRecentUpdate: Date
    }

    private var recentAthleteCards: [RecentAthleteCard] {
        let grouped = Dictionary(grouping: cachedRecentFolders) { $0.ownerAthleteID }
        return grouped.map { athleteID, folders in
            let name = folders.first?.ownerAthleteName ?? "Athlete"
            let videos = folders.reduce(0) { $0 + ($1.videoCount ?? 0) }
            let unread = folders.reduce(0) { total, folder in
                total + (activityNotifService.unreadCountByFolder[folder.id ?? ""] ?? 0)
            }
            let mostRecent = folders.compactMap(\.updatedAt).max() ?? .distantPast
            return RecentAthleteCard(
                athleteID: athleteID,
                athleteName: name,
                totalVideos: videos,
                unreadCount: unread,
                mostRecentUpdate: mostRecent
            )
        }.sorted { $0.mostRecentUpdate > $1.mostRecentUpdate }
    }

    // MARK: - Summary

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DashboardSectionHeader(title: "Overview", icon: "chart.bar.fill", color: .brandNavy)

            HStack(spacing: 12) {
                CoachSummaryCard(
                    icon: "figure.baseball",
                    title: "Athletes",
                    value: "\(uniqueAthleteCount)"
                )

                CoachSummaryCard(
                    icon: "folder.fill",
                    title: "Folders",
                    value: "\(sharedFolderManager.coachFolders.count)"
                )

                CoachSummaryCard(
                    icon: "video.fill",
                    title: "Shared Videos",
                    value: "\(totalVideoCount)"
                )
            }
        }
    }

    // MARK: - Getting Started (empty state)

    private var gettingStartedSection: some View {
        VStack(spacing: 16) {
            DashboardSectionHeader(title: "Getting Started", icon: "sparkles", color: .brandNavy)

            VStack(spacing: 12) {
                gettingStartedStep(
                    number: 1,
                    title: "Invite an Athlete",
                    description: "Tap \"Invite Athlete\" above to send an invitation to a player or parent.",
                    icon: "person.badge.plus"
                )

                gettingStartedStep(
                    number: 2,
                    title: "Athlete Accepts",
                    description: "Once they accept, a shared video folder is created automatically.",
                    icon: "folder.badge.person.crop"
                )

                gettingStartedStep(
                    number: 3,
                    title: "Start a Session",
                    description: "Record lesson clips, add notes, and track your athletes' progress.",
                    icon: "video.badge.checkmark"
                )
            }
        }
    }

    private func gettingStartedStep(number: Int, title: String, description: String, icon: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.brandNavy.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.brandNavy)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(number). \(title)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - This Week

    @ViewBuilder
    private var thisWeekSection: some View {
        if !sessionManager.sessions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                DashboardSectionHeader(title: "This Week", icon: "calendar", color: .brandNavy)

                HStack(spacing: 12) {
                    CoachSummaryCard(
                        icon: "video.badge.checkmark",
                        title: "Sessions",
                        value: "\(cachedThisWeekSessionCount)"
                    )

                    CoachSummaryCard(
                        icon: "film.stack",
                        title: "Clips",
                        value: "\(cachedThisWeekClipCount)"
                    )

                    CoachSummaryCard(
                        icon: "figure.baseball",
                        title: "Athletes",
                        value: "\(cachedThisWeekAthleteCount)"
                    )
                }
            }
        }
    }

    private func updateCachedValues() {
        cachedRecentFolders = sharedFolderManager.coachFolders
            .filter { !archiveManager.isArchived($0.id ?? "") }
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }

        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        cachedThisWeekSessionCount = sessionManager.sessions.filter {
            $0.status == .completed && ($0.startedAt ?? .distantPast) >= weekAgo
        }.count
        cachedThisWeekClipCount = sessionManager.sessions
            .filter { ($0.startedAt ?? .distantPast) >= weekAgo }
            .reduce(0) { $0 + $1.clipCount }
        cachedThisWeekAthleteCount = Set(sessionManager.sessions
            .filter { ($0.startedAt ?? .distantPast) >= weekAgo }
            .flatMap(\.athleteIDs)
        ).count
    }

    private func refreshAthleteLimit(coachID: String) async {
        isOverAthleteLimit = await SubscriptionGate.isCoachOverLimit(coachID: coachID, authManager: authManager)
        fullAthleteCount = await SubscriptionGate.fullConnectedAthleteCount(coachID: coachID)
    }

    // MARK: - Session Actions

    private func resumeSession(_ session: CoachSession) {
        if session.status == .live {
            showingCamera = true
        } else if session.athleteIDs.count == 1,
                  let athleteID = session.athleteIDs.first,
                  let folderID = session.folderIDs[athleteID] {
            // Single athlete — go directly to their folder's Needs Review tab
            coordinator.navigateToFolder(
                folderID,
                folders: sharedFolderManager.coachFolders,
                initialTab: .review
            )
        } else {
            // Multi-athlete — go to Athletes tab so coach can pick which folder
            coordinator.selectedTab = .athletes
        }
    }

    private func endActiveSession(_ session: CoachSession) {
        guard !isEndingSession, let sessionID = session.id else { return }
        isEndingSession = true
        Task {
            do {
                try await sessionManager.endSession(sessionID: sessionID)
            } catch {
                ErrorHandlerService.shared.handle(error, context: "CoachDashboard.endSession", showAlert: false)
            }
            isEndingSession = false
        }
    }

    private func completeActiveSession(_ session: CoachSession) {
        guard !isCompletingSession, let sessionID = session.id else { return }
        isCompletingSession = true
        Task {
            do {
                try await sessionManager.completeSession(sessionID: sessionID)
                Haptics.success()
            } catch {
                ErrorHandlerService.shared.handle(error, context: "CoachDashboard.completeSession", showAlert: false)
            }
            isCompletingSession = false
        }
    }

    private var uniqueAthleteCount: Int {
        Set(sharedFolderManager.coachFolders.map(\.ownerAthleteID)).count
    }

    private var totalVideoCount: Int {
        sharedFolderManager.coachFolders.reduce(0) { $0 + ($1.videoCount ?? 0) }
    }

    @MainActor private func reloadData() async {
        guard let coachID = authManager.userID else { return }
        do {
            try await sharedFolderManager.loadCoachFolders(coachID: coachID)
            await sessionManager.fetchSessions(coachID: coachID)
            if let coachEmail = authManager.userEmail {
                await invitationManager.checkPendingInvitations(forCoachEmail: coachEmail)
            }
        } catch {
            ErrorHandlerService.shared.handle(error, context: "CoachDashboard.reloadData", showAlert: true)
        }
    }

}

// MARK: - Summary Card

private struct CoachSummaryCard: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.brandNavy)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CoachDashboardView()
            .environmentObject(ComprehensiveAuthManager())
            .environment(CoachNavigationCoordinator())
    }
}
