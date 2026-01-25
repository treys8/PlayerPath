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
    @State private var showingAddAthlete = false

    @State private var searchText: String = ""

    private var filteredAthletes: [Athlete] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return user.athletes ?? [] }
        return (user.athletes ?? []).filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            VStack {
                if (user.athletes ?? []).isEmpty {
                    // This shouldn't happen with the new flow, but keeping as fallback
                    VStack(spacing: 30) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 80))
                            .foregroundColor(.blue)

                        Text("Add Your First Athlete")
                            .font(.title)
                            .fontWeight(.bold)

                        Text("Create a profile to start tracking baseball performance")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button(action: { showingAddAthlete = true }) {
                            Text("Add Athlete")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .accessibilityLabel("Add new athlete")
                        .accessibilityHint("Creates a new athlete profile to start tracking performance")

                        HStack {
                            Image(systemName: "icloud")
                                .foregroundColor(.green)
                            Text("Videos will sync across devices")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .padding()
                } else {
                    VStack(spacing: 20) {
                        // Header for multiple athletes
                        VStack(spacing: 8) {
                            Text("Select Athlete")
                                .font(.title)
                                .fontWeight(.bold)

                            Text("Choose which athlete's profile to view")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top)

                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                                ForEach(filteredAthletes) { athlete in
                                    AthleteCard(athlete: athlete) {
                                        selectedAthlete = athlete
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .navigationTitle((user.athletes ?? []).count > 1 ? "Choose Athlete" : "Athletes")
            .navigationBarTitleDisplayMode((user.athletes ?? []).count > 1 ? .inline : .large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Sign Out", role: .destructive) {
                        Task {
                            await authManager.signOut()
                        }
                    }
                    .accessibilityLabel("Sign out")
                    .accessibilityHint("Sign out of your account")
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
            .searchable(text: $searchText)
        }
        .sheet(isPresented: $showingAddAthlete) {
            AddAthleteView(user: user, selectedAthlete: $selectedAthlete, isFirstAthlete: false)
        }
    }
}
