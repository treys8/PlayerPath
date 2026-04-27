//
//  AthleteSelectionView.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI
import SwiftData

struct AthleteSelectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let user: User
    @Binding var selectedAthlete: Athlete?
    let authManager: ComprehensiveAuthManager
    var onDismiss: (() -> Void)? = nil
    @State private var showingAddAthlete = false
    @State private var showingSignOutConfirmation = false

    @State private var searchText: String = ""

    private var athletes: [Athlete] { user.athletes ?? [] }
    private var hasMultipleAthletes: Bool { athletes.count > 1 }

    private var filteredAthletes: [Athlete] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return athletes }
        return athletes.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            VStack {
                if athletes.isEmpty {
                    // This shouldn't happen with the new flow, but keeping as fallback
                    VStack(spacing: 30) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 80))
                            .foregroundColor(.brandNavy)

                        Text("Add Your First Athlete")
                            .font(.displayMedium)

                        Text("Create a profile to start tracking baseball performance")
                            .font(.bodyMedium)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button(action: { showingAddAthlete = true }) {
                            Text("Add Athlete")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.brandNavy)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .accessibilityLabel("Add new athlete")
                        .accessibilityHint("Creates a new athlete profile to start tracking performance")

                        HStack {
                            Image(systemName: "icloud")
                                .foregroundColor(.green)
                            Text("Videos will sync across devices")
                                .font(.bodySmall)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .padding()
                } else {
                    VStack(spacing: 20) {
                        // Header — adapts copy based on athlete count
                        VStack(spacing: 8) {
                            Text(hasMultipleAthletes ? "Select Athlete" : "Your Athlete")
                                .font(.displayMedium)

                            Text(hasMultipleAthletes
                                 ? "Choose which athlete's profile to view"
                                 : "Tap to open, or add another athlete")
                                .font(.bodyMedium)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top)

                        if filteredAthletes.isEmpty && !searchText.isEmpty {
                            ContentUnavailableView.search(text: searchText)
                        } else {
                            ScrollView {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                                    ForEach(filteredAthletes) { athlete in
                                        AthleteCard(athlete: athlete) {
                                            selectedAthlete = athlete
                                            onDismiss?()
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                            .scrollBounceBehavior(.basedOnSize)
                        }
                    }
                }
            }
            .navigationTitle(hasMultipleAthletes ? "Choose Athlete" : "Athletes")
            .navigationBarTitleDisplayMode(hasMultipleAthletes ? .inline : .large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if onDismiss != nil {
                        // User navigated here from Dashboard — show Back
                        Button {
                            onDismiss?()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                        }
                        .accessibilityLabel("Go back")
                        .accessibilityHint("Return to the previous screen")
                    } else {
                        // Root view (e.g. first launch) — show Sign Out
                        Button("Sign Out", role: .destructive) {
                            showingSignOutConfirmation = true
                        }
                        .accessibilityLabel("Sign out")
                        .accessibilityHint("Sign out of your account")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if authManager.userRole == .athlete {
                        Button(action: { showingAddAthlete = true }) {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add athlete")
                        .accessibilityHint("Add a new athlete to your roster")
                    }
                }
            }
            .if(hasMultipleAthletes) { view in
                view.searchable(text: $searchText)
            }
        }
        .sheet(isPresented: $showingAddAthlete) {
            AddAthleteView(user: user, selectedAthlete: .constant(nil), isFirstAthlete: false)
        }
        .confirmationDialog(
            "Sign Out",
            isPresented: $showingSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                Task {
                    await authManager.signOut()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to sign out? Any unsynced data will be uploaded when you sign back in.")
        }
    }
}
