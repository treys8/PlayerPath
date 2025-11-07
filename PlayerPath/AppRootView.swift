//
//  UserManager.swift
//  PlayerPath
//
//  Created by Assistant on 11/1/25.
//

import SwiftUI
import SwiftData
import FirebaseAuth

/// Simplified user management that bridges Firebase Auth with local data
@MainActor
@Observable
final class UserManager {
    var currentUser: User?
    var isLoading = false
    
    private var modelContext: ModelContext?
    private var authManager: AuthenticationManager?
    
    func setup(context: ModelContext, authManager: AuthenticationManager) {
        self.modelContext = context
        self.authManager = authManager
        
        // Load user when authenticated
        if authManager.isAuthenticated {
            Task { await loadUser() }
        }
    }
    
    func loadUser() async {
        guard let authManager = authManager,
              let firebaseUser = authManager.currentFirebaseUser,
              let email = firebaseUser.email,
              let context = modelContext else {
            return
        }
        
        isLoading = true
        
        // Try to find existing user
        let descriptor = FetchDescriptor<User>(
            predicate: #Predicate<User> { user in
                user.email == email
            }
        )
        
        do {
            let users = try context.fetch(descriptor)
            
            if let existingUser = users.first {
                currentUser = existingUser
            } else {
                // Create new user
                let newUser = User(
                    username: firebaseUser.displayName ?? email,
                    email: email
                )
                context.insert(newUser)
                try context.save()
                currentUser = newUser
            }
        } catch {
            print("Failed to load/create user: \(error)")
        }
        
        isLoading = false
    }
    
    func signOut() {
        currentUser = nil
        authManager?.signOut()
    }
}

/// Simplified main app view that handles the complete flow
struct AppRootView: View {
    @State private var authManager = AuthenticationManager()
    @State private var userManager = UserManager()
    @State private var onboardingManager = OnboardingManager()
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        Group {
            if authManager.isAuthenticated {
                if onboardingManager.hasCompletedOnboarding {
                    if let user = userManager.currentUser {
                        MainAppContentView(user: user)
                    } else if userManager.isLoading {
                        LoadingView(message: "Setting up your profile...")
                    } else {
                        ErrorView(message: "Failed to load user profile") {
                            Task { await userManager.loadUser() }
                        }
                    }
                } else {
                    SimpleOnboardingView()
                        .environment(onboardingManager)
                }
            } else {
                AuthenticationView()
                    .environment(authManager)
            }
        }
        .onAppear {
            setupManagers()
        }
        .onChange(of: authManager.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                Task { await userManager.loadUser() }
            } else {
                userManager.currentUser = nil
            }
        }
        .environment(authManager)
        .environment(userManager)
        .environment(onboardingManager)
    }
    
    private func setupManagers() {
        userManager.setup(context: modelContext, authManager: authManager)
        onboardingManager.setup(with: modelContext)
    }
}

/// Main app content after authentication and onboarding
struct MainAppContentView: View {
    let user: User
    @Environment(UserManager.self) private var userManager
    
    var body: some View {
        NavigationStack {
            VStack {
                if user.athletes.isEmpty {
                    // Show athlete creation
                    CreateFirstAthleteView(user: user)
                } else {
                    // Show main app (placeholder for your existing main app)
                    Text("Main App Content")
                        .font(.largeTitle)
                    
                    Text("Welcome, \(user.username)!")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    Text("You have \(user.athletes.count) athlete(s)")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("PlayerPath")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Sign Out") {
                        userManager.signOut()
                    }
                }
            }
        }
    }
}

/// Simple athlete creation view
struct CreateFirstAthleteView: View {
    let user: User
    @Environment(\.modelContext) private var modelContext
    @State private var athleteName = ""
    @State private var isCreating = false
    
    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 16) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                Text("Create Your First Athlete")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text("Start tracking baseball performance by adding an athlete profile.")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            VStack(spacing: 16) {
                TextField("Athlete Name", text: $athleteName)
                    .textFieldStyle(RoundedTextFieldStyle())
                    .padding(.horizontal)
                
                Button(action: createAthlete) {
                    HStack {
                        if isCreating {
                            ProgressView()
                                .scaleEffect(0.9)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                        Text(isCreating ? "Creating..." : "Create Athlete")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(athleteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                .padding(.horizontal)
            }
            
            Spacer()
        }
        .padding(.vertical, 32)
    }
    
    private func createAthlete() {
        let name = athleteName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        
        isCreating = true
        
        let athlete = Athlete(name: name)
        athlete.user = user
        athlete.statistics = Statistics()
        
        user.athletes.append(athlete)
        modelContext.insert(athlete)
        
        if let statistics = athlete.statistics {
            statistics.athlete = athlete
            modelContext.insert(statistics)
        }
        
        do {
            try modelContext.save()
        } catch {
            print("Failed to create athlete: \(error)")
        }
        
        isCreating = false
    }
}

// MARK: - Utility Views

private struct LoadingView: View {
    let message: String
    
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text(message)
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }
}

private struct ErrorView: View {
    let message: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text(message)
                .font(.headline)
                .multilineTextAlignment(.center)
            
            Button("Try Again", action: onRetry)
                .buttonStyle(PrimaryButtonStyle())
                .frame(width: 120)
        }
        .padding()
    }
}

#Preview {
    AppRootView()
        .modelContainer(for: [User.self, Athlete.self, OnboardingProgress.self])
}