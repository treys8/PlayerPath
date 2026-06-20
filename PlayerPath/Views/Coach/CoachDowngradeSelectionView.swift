//
//  CoachDowngradeSelectionView.swift
//  PlayerPath
//
//  Selection sheet opened from the downgrade resolve banner once the grace
//  period expires. The coach chooses which athletes to keep (up to their tier
//  limit); unchosen athletes have their folder access and invitations revoked.
//  Dismissable — the coach can defer and keep viewing (feedback delivery stays
//  blocked server-side until they resolve here or upgrade).
//

import SwiftUI
import FirebaseAuth
import os

private let selectionLog = Logger(subsystem: "com.playerpath.app", category: "CoachDowngradeSelection")

struct CoachDowngradeSelectionView: View {
    let coachID: String
    @Environment(\.dismiss) private var dismiss
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
                ToolbarItem(placement: .topBarLeading) {
                    Button("Later") { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Upgrade Instead") {
                        showingPaywall = true
                    }
                    .fontWeight(.medium)
                }
            }
            .interactiveDismissDisabled(isSubmitting)
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
                .foregroundStyle(Theme.warning)

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

        // Group folders by canonical PERSON key so a dual-sport person (two
        // profiles sharing one personGroupID) shows as ONE row — matching the
        // billing count (SubscriptionGate.connectedAthleteKeys). Alongside each
        // person we collect every identifier axis seen, so revocation can match
        // their folders/invitations regardless of which key each doc carries.
        // `keys` only includes the account UID for UUID-less (legacy) rows, so a
        // sibling profile under the same account is never swept into a revoke.
        typealias Acc = (name: String?, folderCount: Int, videoCount: Int, keys: Set<String>)
        var athleteMap: [String: Acc] = [:]
        for folder in folders {
            let canonical = folder.personGroupID ?? folder.athleteUUID ?? folder.ownerAthleteID
            var entry = athleteMap[canonical] ?? (name: nil, folderCount: 0, videoCount: 0, keys: [])
            if entry.name == nil { entry.name = folder.ownerAthleteName }
            entry.folderCount += 1
            entry.videoCount += (folder.videoCount ?? 0)
            if let pg = folder.personGroupID, !pg.isEmpty { entry.keys.insert(pg) }
            if let uuid = folder.athleteUUID, !uuid.isEmpty {
                entry.keys.insert(uuid)
            } else {
                entry.keys.insert(folder.ownerAthleteID)
            }
            athleteMap[canonical] = entry
        }

        // Also include athletes connected via accepted invitations whose folders
        // aren't present locally yet, so the count matches SubscriptionGate.
        // Reconcile on the canonical axis so an athlete already shown via a folder
        // is enriched (more revoke keys) rather than re-added as a phantom row.
        do {
            let invitationRefs = try await FirestoreManager.shared
                .fetchAcceptedCoachToAthleteRefs(coachID: coachID)
            let unmatched = SubscriptionGate.unmatchedInvitationRefs(folders: folders, invitationRefs: invitationRefs)
            for ref in unmatched {
                guard let key = ref.canonicalKey else { continue }
                var entry = athleteMap[key] ?? (name: nil, folderCount: 0, videoCount: 0, keys: [])
                // Name lookup uses the account UID (the Athlete UUID isn't a user doc ID).
                if entry.name == nil, let uid = ref.athleteUserID {
                    entry.name = (try? await FirestoreManager.shared.fetchUserProfile(userID: uid))?
                        .email.components(separatedBy: "@").first
                }
                if let pg = ref.personGroupID, !pg.isEmpty { entry.keys.insert(pg) }
                if let uuid = ref.athleteUUID, !uuid.isEmpty {
                    entry.keys.insert(uuid)
                } else if let uid = ref.athleteUserID, !uid.isEmpty {
                    entry.keys.insert(uid)
                }
                athleteMap[key] = entry
            }
        } catch {
            // Best-effort: proceed with folder-based athletes only
            ErrorHandlerService.shared.handle(error, context: "CoachDowngradeSelectionView.loadAthletes", showAlert: false)
        }

        athletes = athleteMap.map { id, info in
            ConnectedAthlete(id: id,
                             name: info.name ?? "Unknown Athlete",
                             folderCount: info.folderCount,
                             videoCount: info.videoCount,
                             revokeKeys: info.keys)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        isLoading = false
    }

    private func submitSelection() async {
        isSubmitting = true
        errorMessage = nil

        // Expand each unselected person to ALL their identifier axes so the revoke
        // matches their folders + invitations no matter which key each doc carries
        // (personGroupID / athleteUUID / account UID) — not just the display id.
        let revokeSet = athletes
            .filter { !selectedIDs.contains($0.id) }
            .reduce(into: Set<String>()) { $0.formUnion($1.revokeKeys) }
        let athleteIDsToRevoke = Array(revokeSet)

        do {
            try await FirestoreManager.shared.batchRevokeCoachAccess(
                coachID: coachID,
                athleteIDsToRevoke: athleteIDsToRevoke
            )

            // End active sessions and notify affected athletes
            let affectedFolders = sharedFolderManager.coachFolders.filter { folder in
                SubscriptionGate.personMatches(
                    personGroupID: folder.personGroupID,
                    athleteUUID: folder.athleteUUID,
                    accountID: folder.ownerAthleteID,
                    in: revokeSet
                )
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
            isSubmitting = false
            dismiss()
            return
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
    /// Every identifier axis (personGroupID / athleteUUID / account UID) that maps
    /// to this person across folders + invitations, so revocation matches all of
    /// their docs regardless of which key each one carries. See `personMatches`.
    let revokeKeys: Set<String>
}
