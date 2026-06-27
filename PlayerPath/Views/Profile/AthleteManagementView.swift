//
//  AthleteManagementView.swift
//  PlayerPath
//
//  Manage athletes list with add and delete functionality.
//

import SwiftUI
import SwiftData

// MARK: - Shared Athlete Delete Helper

/// Single source of truth for athlete deletion. Called from both ProfileView and AthleteManagementView.
func performDeleteAthlete(_ athlete: Athlete, selectedAthlete: Binding<Athlete?>, user: User, modelContext: ModelContext) throws {
    // Capture values before deletion — accessing SwiftData object properties after
    // delete is undefined behavior.
    let athleteID = athlete.id

    // Capture Firestore IDs before local hard-delete so we can sync deletions
    let userId = user.firebaseAuthUid ?? user.id.uuidString
    let athleteFirestoreId = athlete.firestoreId
    let seasonFirestoreIds = (athlete.seasons ?? []).compactMap { $0.firestoreId }
    let gameFirestoreIds = (athlete.games ?? []).compactMap { $0.firestoreId }
    let practiceFirestoreIds = (athlete.practices ?? []).compactMap { $0.firestoreId }
    let coachFirestoreIds = (athlete.coaches ?? []).compactMap { $0.firestoreId }
    // Practice notes: pair each note's firestoreId with its practice's firestoreId
    var noteIds: [(noteId: String, practiceId: String)] = []
    for practice in athlete.practices ?? [] {
        guard let pId = practice.firestoreId else { continue }
        for note in practice.notes ?? [] {
            if let nId = note.firestoreId {
                noteIds.append((noteId: nId, practiceId: pId))
            }
        }
    }

    if athleteID == selectedAthlete.wrappedValue?.id {
        let remaining = (user.athletes ?? []).filter { $0.id != athleteID }
        selectedAthlete.wrappedValue = remaining.first
    }
    athlete.delete(in: modelContext)
    try modelContext.save()
    AnalyticsService.shared.trackAthleteDeleted(athleteID: athleteID.uuidString)
    if (user.athletes ?? []).isEmpty {
        selectedAthlete.wrappedValue = nil
    }

    // Cancel scheduled local notifications keyed by athlete UUID. Without this
    // the Sunday 6 PM weekly summary keeps firing for a deleted athlete until
    // the user reinstalls (WeeklySummaryScheduler.scheduleAll only adds, never
    // sweeps stale identifiers).
    let weeklySummaryNotifID = "weekly_summary_\(athleteID.uuidString)"
    Task { @MainActor in
        PushNotificationService.shared.cancelNotifications(withIdentifiers: [weeklySummaryNotifID])
    }

    // Sync deletions to Firestore (fire-and-forget — local delete is already committed)
    Task {
        // Soft-delete child entities first, then parents, then the athlete
        for (noteId, practiceId) in noteIds {
            await retryAsync { try await FirestoreManager.shared.deletePracticeNote(userId: userId, practiceFirestoreId: practiceId, noteId: noteId) }
        }
        for id in gameFirestoreIds {
            await retryAsync { try await FirestoreManager.shared.deleteGame(userId: userId, gameId: id) }
        }
        for id in practiceFirestoreIds {
            await retryAsync { try await FirestoreManager.shared.deletePractice(userId: userId, practiceId: id) }
        }
        for id in seasonFirestoreIds {
            await retryAsync { try await FirestoreManager.shared.deleteSeason(userId: userId, seasonId: id) }
        }
        if let athleteFirestoreId {
            for id in coachFirestoreIds {
                await retryAsync { try await FirestoreManager.shared.deleteCoach(userId: userId, athleteFirestoreId: athleteFirestoreId, coachId: id) }
            }
            await retryAsync { try await FirestoreManager.shared.deleteAthlete(userId: userId, athleteId: athleteFirestoreId) }
        }
    }
}

// MARK: - Athlete Management View

struct AthleteManagementView: View {
    @Environment(\.ppAccent) private var ppAccent
    let user: User
    @Binding var selectedAthlete: Athlete?
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @State private var showingAddAthlete = false
    @State private var showingPaywall = false
    @State private var athletePendingDelete: Athlete?
    @State private var showingDeleteAthleteAlert = false
    @State private var showDeleteError = false
    @State private var deleteErrorMessage = ""
    @State private var isDeletingAthlete = false
    /// Athletes collapsed into one entry per person (linked sport-variant
    /// profiles share a `personGroupID`). A multi-sport person renders as a
    /// named section with one row per sport; singletons stay a plain row.
    @State private var athleteGroups: [AthletePersonGroup] = []

    private var canAddMoreAthletes: Bool {
        // Use the canonical slot count: linked sport-variant profiles
        // (same personGroupID) count as ONE slot, matching the tier gate.
        user.athleteSlotsUsed < authManager.currentTier.athleteLimit
    }

    var body: some View {
        List {
            // Single-sport people stay one tight section (unchanged look for the
            // common case). Delete maps the row offset back to this flat list.
            if !singletonAthletes.isEmpty {
                Section {
                    ForEach(singletonAthletes) { athlete in
                        AthleteProfileRow(
                            athlete: athlete,
                            isSelected: athlete.id == selectedAthlete?.id
                        ) {
                            selectedAthlete = athlete
                        }
                    }
                    .onDelete { offsets in
                        if let index = offsets.first, index < singletonAthletes.count {
                            Haptics.warning()
                            athletePendingDelete = singletonAthletes[index]
                            showingDeleteAthleteAlert = true
                        }
                    }
                }
            }

            // A dual-sport person gets a name-headed section with one row per
            // sport — so the two linked profiles read as ONE person, not two.
            ForEach(multiSportGroups) { group in
                Section(header: Text(group.displayName)) {
                    ForEach(group.profiles) { athlete in
                        AthleteProfileRow(
                            athlete: athlete,
                            isSelected: athlete.id == selectedAthlete?.id,
                            titleOverride: athlete.sportType.displayName
                        ) {
                            selectedAthlete = athlete
                        }
                    }
                    .onDelete { offsets in
                        if let index = offsets.first, index < group.profiles.count {
                            Haptics.warning()
                            athletePendingDelete = group.profiles[index]
                            showingDeleteAthleteAlert = true
                        }
                    }
                }
            }

            Section {
                Button(action: {
                    if canAddMoreAthletes {
                        showingAddAthlete = true
                    } else {
                        Haptics.warning()
                        showingPaywall = true
                    }
                }) {
                    Label("Add Athlete", systemImage: "person.badge.plus")
                }
                .tint(ppAccent)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.surface)
        .tint(ppAccent)
        .navigationTitle("Manage Athletes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
        }
        .sheet(isPresented: $showingAddAthlete) {
            AddAthleteView(user: user, selectedAthlete: $selectedAthlete, isFirstAthlete: (user.athletes ?? []).isEmpty)
        }
        .alert("Delete Athlete", isPresented: $showingDeleteAthleteAlert) {
            Button("Cancel", role: .cancel) { athletePendingDelete = nil }
            Button("Delete", role: .destructive) {
                Haptics.heavy()
                if let athlete = athletePendingDelete {
                    delete(athlete: athlete)
                }
                athletePendingDelete = nil
            }
        } message: {
            Text("This will delete the athlete and related data. This action cannot be undone.")
        }
        .alert("Failed to Delete", isPresented: $showDeleteError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(deleteErrorMessage.isEmpty ? "Please try again." : deleteErrorMessage)
        }
        .sheet(isPresented: $showingPaywall) {
            ImprovedPaywallView(user: user)
        }
        .onAppear {
            updateAthleteGroups()
        }
        .onChange(of: user.athletes) { _, _ in
            updateAthleteGroups()
        }
    }

    /// Single-sport people, flattened back to one row each for the tight section.
    private var singletonAthletes: [Athlete] {
        athleteGroups.filter { !$0.isMultiSport }.flatMap { $0.profiles }
    }

    /// People with 2+ linked sport profiles — each gets its own named section.
    private var multiSportGroups: [AthletePersonGroup] {
        athleteGroups.filter { $0.isMultiSport }
    }

    private func updateAthleteGroups() {
        // groupedByPerson() already sorts groups by name (then by sport within a
        // group), matching the prior name-sorted flat order for singletons.
        athleteGroups = (user.athletes ?? []).groupedByPerson()
    }

    private func delete(athlete: Athlete) {
        guard !isDeletingAthlete else { return }
        isDeletingAthlete = true
        do {
            try performDeleteAthlete(athlete, selectedAthlete: $selectedAthlete, user: user, modelContext: modelContext)
            Haptics.success()
        } catch {
            ErrorHandlerService.shared.reportError(error, context: "ProfileView.deleteAthlete", message: $deleteErrorMessage, isPresented: $showDeleteError, userMessage: String(format: ProfileStrings.deleteFailed, error.localizedDescription))
        }
        isDeletingAthlete = false
    }
}
