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
}

// MARK: - Athlete Management View

struct AthleteManagementView: View {
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
    @State private var sortedAthletes: [Athlete] = []

    private var canAddMoreAthletes: Bool {
        (user.athletes ?? []).count < authManager.currentTier.athleteLimit
    }

    var body: some View {
        List {
            Section {
                ForEach(sortedAthletes) { athlete in
                    AthleteProfileRow(
                        athlete: athlete,
                        isSelected: athlete.id == selectedAthlete?.id
                    ) {
                        selectedAthlete = athlete
                    }
                }
                .onDelete { offsets in
                    if let index = offsets.first, index < sortedAthletes.count {
                        athletePendingDelete = sortedAthletes[index]
                        showingDeleteAthleteAlert = true
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
                .tint(.blue)
            }
        }
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
            updateSortedAthletes()
        }
        .onChange(of: user.athletes) { _, _ in
            updateSortedAthletes()
        }
    }

    private func updateSortedAthletes() {
        sortedAthletes = (user.athletes ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
