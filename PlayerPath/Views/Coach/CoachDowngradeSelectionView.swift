//
//  CoachDowngradeSelectionView.swift
//  PlayerPath
//
//  Full-screen blocker shown after the grace period expires.
//  The coach must choose which athletes to keep (up to their tier limit).
//  Unchosen athletes have their folder access and invitations revoked.
//

import SwiftUI
import FirebaseAuth
import os

private let selectionLog = Logger(subsystem: "com.playerpath.app", category: "CoachDowngradeSelection")

struct CoachDowngradeSelectionView: View {
    let coachID: String
    @State private var athletes: [ConnectedAthlete] = []
    @State private var selectedIDs: Set<String> = []
    @State private var isLoading = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showingPaywall = false
    @State private var showingConfirmation = false

    private var sharedFolderManager: SharedFolderManager { .shared }
    private var downgradeManager: CoachDowngradeManager { .shared }

    /// Read live from the manager so partial upgrades are reflected immediately.
    private var limit: Int { downgradeManager.currentLimit }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerSection
                Divider()
                if isLoading {
                    ProgressView("Loading athletes...")
                        .frame(maxHeight: .infinity)
                } else {
                    athleteList
                }
                Divider()
                bottomBar
            }
            .navigationTitle("Choose Athletes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Upgrade Instead") {
                        showingPaywall = true
                    }
                    .fontWeight(.medium)
                }
            }
            .interactiveDismissDisabled()
            .task { await loadAthletes() }
            .sheet(isPresented: $showingPaywall) {
                CoachPaywallView()
            }
            .confirmationDialog(
                "Remove \(athletes.count - selectedIDs.count) athlete\(athletes.count - selectedIDs.count == 1 ? "" : "s")?",
                isPresented: $showingConfirmation,
                titleVisibility: .visible
            ) {
                Button("Confirm", role: .destructive) {
                    Task { await submitSelection() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You will lose access to folders from athletes you don't select. They will be notified and can re-invite you later.")
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.minus")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("Select up to \(limit) athlete\(limit == 1 ? "" : "s") to keep")
                .font(.headline)

            Text("You have \(athletes.count) connected. Unselected athletes will be disconnected.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Athlete List

    private var athleteList: some View {
        List(athletes) { athlete in
            Button {
                toggleSelection(athlete.id)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: selectedIDs.contains(athlete.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(selectedIDs.contains(athlete.id) ? .green : .secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(athlete.name)
                            .font(.body)
                            .foregroundStyle(.primary)
                        Text("\(athlete.folderCount) folder\(athlete.folderCount == 1 ? "" : "s") · \(athlete.videoCount) video\(athlete.videoCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selectedIDs.contains(athlete.id) ? .isSelected : [])
            .accessibilityLabel("\(athlete.name). \(athlete.folderCount) folder\(athlete.folderCount == 1 ? "" : "s"), \(athlete.videoCount) video\(athlete.videoCount == 1 ? "" : "s")")
        }
        .listStyle(.plain)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Text("\(selectedIDs.count)/\(limit) selected")
                    .font(.subheadline)
                    .foregroundStyle(selectedIDs.count > limit ? .red : .secondary)

                Spacer()

                Button {
                    showingConfirmation = true
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .frame(width: 100)
                    } else {
                        Text("Confirm Selection")
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandNavy)
                .disabled(selectedIDs.isEmpty || selectedIDs.count > limit || isSubmitting)
            }
        }
        .padding()
    }

    // MARK: - Logic

    private func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else if selectedIDs.count < limit {
            selectedIDs.insert(id)
        } else {
            Haptics.warning()
        }
    }

    private func loadAthletes() async {
        let folders = sharedFolderManager.coachFolders

        // Group folders by athlete
        var athleteMap: [String: (name: String, folderCount: Int, videoCount: Int)] = [:]
        for folder in folders {
            let id = folder.ownerAthleteID
            let existing = athleteMap[id]
            athleteMap[id] = (
                name: existing?.name ?? folder.ownerAthleteName ?? "Unknown Athlete",
                folderCount: (existing?.folderCount ?? 0) + 1,
                videoCount: (existing?.videoCount ?? 0) + (folder.videoCount ?? 0)
            )
        }

        // Also include athletes connected via accepted invitations (no folder yet)
        // so the count matches SubscriptionGate.fullConnectedAthleteCount
        do {
            let invitationOnlyIDs = try await FirestoreManager.shared
                .fetchAcceptedCoachToAthleteAthleteIDs(coachID: coachID)
            for athleteID in invitationOnlyIDs where athleteMap[athleteID] == nil {
                // Fetch display name for invitation-only athletes
                let profile = try? await FirestoreManager.shared.fetchUserProfile(userID: athleteID)
                let name = profile?.email.components(separatedBy: "@").first
                athleteMap[athleteID] = (
                    name: name ?? "Unknown Athlete",
                    folderCount: 0,
                    videoCount: 0
                )
            }
        } catch {
            // Best-effort: proceed with folder-based athletes only
            ErrorHandlerService.shared.handle(error, context: "CoachDowngradeSelectionView.loadAthletes", showAlert: false)
        }

        athletes = athleteMap.map { id, info in
            ConnectedAthlete(id: id, name: info.name, folderCount: info.folderCount, videoCount: info.videoCount)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        isLoading = false
    }

    private func submitSelection() async {
        isSubmitting = true
        errorMessage = nil

        let athleteIDsToRevoke = athletes.map(\.id).filter { !selectedIDs.contains($0) }

        do {
            try await FirestoreManager.shared.batchRevokeCoachAccess(
                coachID: coachID,
                athleteIDsToRevoke: athleteIDsToRevoke
            )

            // End active sessions and notify affected athletes
            let revokeSet = Set(athleteIDsToRevoke)
            let affectedFolders = sharedFolderManager.coachFolders.filter {
                revokeSet.contains($0.ownerAthleteID)
            }
            let coachName = Auth.auth().currentUser?.displayName
                ?? Auth.auth().currentUser?.email?.components(separatedBy: "@").first
                ?? "Your coach"

            for folder in affectedFolders {
                guard let folderID = folder.id else { continue }
                await CoachSessionManager.shared.endSessionIfActive(forFolderID: folderID)
                await ActivityNotificationService.shared.postCoachAccessLostNotification(
                    folderID: folderID,
                    folderName: folder.name,
                    coachName: coachName,
                    coachID: coachID,
                    athleteUserID: folder.ownerAthleteID
                )
            }

            CoachDowngradeManager.shared.markResolved(coachID: coachID)
            Haptics.success()
            selectionLog.info("Revoked access for \(athleteIDsToRevoke.count) athletes")
        } catch {
            errorMessage = "Failed to update. Please try again."
            ErrorHandlerService.shared.handle(error, context: "CoachDowngradeSelectionView.submit", showAlert: false)
            selectionLog.error("Revocation failed: \(error.localizedDescription)")
        }

        isSubmitting = false
    }
}

// MARK: - Connected Athlete Model

private struct ConnectedAthlete: Identifiable {
    let id: String
    let name: String
    let folderCount: Int
    let videoCount: Int
}
