//
//  MainAppView_New.swift
//  PlayerPath
//
//  Clean version with comprehensive authentication
//

import SwiftUI
import SwiftData

struct MainAppView_New: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var authManager = ComprehensiveAuthManager()
    @Query private var users: [User]
    @State private var currentUser: User?
    @State private var selectedAthlete: Athlete?
    
    var body: some View {
        Group {
            if !authManager.isSignedIn {
                // Show comprehensive sign-in screen
                ComprehensiveSignInView()
            } else {
                // User is signed in
                if let user = currentUser {
                    if user.athletes.isEmpty {
                        AthleteSelectionView_New(
                            user: user,
                            selectedAthlete: $selectedAthlete,
                            authManager: authManager
                        )
                    } else {
                        MainTabView(
                            user: user,
                            selectedAthlete: $selectedAthlete
                        )
                        .overlay(alignment: .top) {
                            // Show trial status
                            TrialStatusView(authManager: authManager)
                                .padding()
                        }
                    }
                } else {
                    // Loading or creating user profile
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Setting up your profile...")
                            .font(.headline)
                    }
                    .onAppear {
                        createOrFindLocalUser()
                    }
                }
            }
        }
        .environmentObject(authManager)
        .onChange(of: authManager.isSignedIn) { _, isSignedIn in
            if isSignedIn {
                createOrFindLocalUser()
            } else {
                currentUser = nil
                selectedAthlete = nil
            }
        }
    }
    
    private func createOrFindLocalUser() {
        guard let authUser = authManager.currentUser else { return }
        
        // Try to find existing user by email
        let existingUser = users.first { user in
            user.email == authUser.email
        }
        
        if let existingUser = existingUser {
            currentUser = existingUser
            selectedAthlete = existingUser.athletes.first
        } else {
            // Create new local user to match authenticated user
            let newUser = User(
                username: authUser.displayName,
                email: authUser.email
            )
            
            modelContext.insert(newUser)
            
            do {
                try modelContext.save()
                currentUser = newUser
            } catch {
                print("Failed to create local user: \(error)")
            }
        }
    }
}

// MARK: - Clean Athlete Selection View
struct AthleteSelectionView_New: View {
    @Environment(\.modelContext) private var modelContext
    let user: User
    @Binding var selectedAthlete: Athlete?
    let authManager: ComprehensiveAuthManager
    @State private var showingAddAthlete = false
    
    var body: some View {
        NavigationStack {
            VStack {
                // Trial status banner
                TrialStatusView(authManager: authManager)
                    .padding(.horizontal)
                
                if user.athletes.isEmpty {
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
                        
                        // Show sync status
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
                    List {
                        ForEach(user.athletes) { athlete in
                            AthleteRowView(athlete: athlete) {
                                selectedAthlete = athlete
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Athlete")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button("Sign Out") {
                            authManager.signOut()
                        }
                        
                        if !authManager.isPremiumUser {
                            Button("Upgrade to Premium") {
                                Task {
                                    await authManager.upgradeToPremium()
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "person.circle")
                            Text(authManager.currentUser?.displayName ?? "User")
                        }
                    }
                }
                
                if !user.athletes.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { showingAddAthlete = true }) {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddAthlete) {
            AddAthleteView_New(user: user, selectedAthlete: $selectedAthlete)
        }
    }
}

struct AthleteRowView: View {
    let athlete: Athlete
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading) {
                    Text(athlete.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("Created \(athlete.createdAt, formatter: DateFormatter.shortDate)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .padding(.vertical, 5)
        }
    }
}

struct AddAthleteView_New: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let user: User
    @Binding var selectedAthlete: Athlete?
    @State private var athleteName = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                VStack {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("Add New Athlete")
                        .font(.title)
                        .fontWeight(.bold)
                }
                
                TextField("Athlete Name", text: $athleteName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("New Athlete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveAthlete()
                    }
                    .disabled(athleteName.isEmpty)
                }
            }
        }
    }
    
    private func saveAthlete() {
        let athlete = Athlete(name: athleteName)
        athlete.user = user
        athlete.statistics = Statistics()
        
        // Add athlete to user's athletes array
        user.athletes.append(athlete)
        modelContext.insert(athlete)
        
        // Also insert the statistics
        if let statistics = athlete.statistics {
            statistics.athlete = athlete
            modelContext.insert(statistics)
        }
        
        do {
            try modelContext.save()
            // Auto-select the new athlete
            selectedAthlete = athlete
            dismiss()
        } catch {
            print("Failed to save athlete: \(error)")
        }
    }
}