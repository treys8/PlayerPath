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
    @EnvironmentObject private var sharedFolderManager: SharedFolderManager
    @Environment(CoachNavigationCoordinator.self) private var coordinator
    @ObservedObject private var invitationManager = CoachInvitationManager.shared
    @ObservedObject private var activityNotifService = ActivityNotificationService.shared
    @State private var showingQuickRecord = false
    @State private var showingInviteAthlete = false
    @ObservedObject private var archiveManager = CoachFolderArchiveManager.shared

    /// Recent folders sorted by updatedAt, excluding archived
    private var recentFolders: [SharedFolder] {
        sharedFolderManager.coachFolders
            .filter { !archiveManager.isArchived($0.id ?? "") }
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 20) {
                    // Over-limit banner
                    if SubscriptionGate.isCoachOverLimit(authManager: authManager) {
                        CoachOverLimitBanner(
                            connectedCount: SubscriptionGate.connectedAthleteCount(),
                            limit: authManager.coachAthleteLimit
                        )
                    }

                    // Quick Actions
                    quickActionsSection

                    // Recent Athletes
                    if !recentFolders.isEmpty {
                        recentAthletesSection
                    }

                    // Summary stats
                    if !sharedFolderManager.coachFolders.isEmpty {
                        summarySection
                    }
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
        .sheet(isPresented: $showingInviteAthlete) {
            InviteAthleteSheet()
        }
        .fullScreenCover(isPresented: $showingQuickRecord) {
            CoachQuickRecordFlow()
        }
        .onAppear {
            AnalyticsService.shared.trackScreenView(screenName: "Coach Dashboard", screenClass: "CoachDashboardView")
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
                    Text("Record Instruction")
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
                            coordinator.navigateToFolder(
                                folder.id ?? "",
                                folders: sharedFolderManager.coachFolders
                            )
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

    // MARK: - Summary

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overview")
                .font(.headline)

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
                coordinator.navigateToFolder(folderID, folders: sharedFolderManager.coachFolders)
            }
        case .invitationReceived, .invitationAccepted:
            coordinator.navigateToInvitations()
        case .coachComment, .accessRevoked:
            break
        }

        if let notifID = notification.id, let coachID = authManager.userID {
            Task {
                await ActivityNotificationService.shared.markRead(notifID, forUserID: coachID)
            }
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
                .foregroundColor(.green)

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
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CoachDashboardView()
            .environmentObject(ComprehensiveAuthManager())
            .environmentObject(SharedFolderManager.shared)
            .environment(CoachNavigationCoordinator())
    }
}
