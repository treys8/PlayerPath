//
//  MainAppView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import SwiftData

struct MainAppView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [User]
    @State private var currentUser: User?
    @State private var showingAuth = true
    @State private var selectedAthlete: Athlete?
    
    var body: some View {
        Group {
            if showingAuth || currentUser == nil {
                AuthenticationView(
                    currentUser: $currentUser,
                    showingAuth: $showingAuth
                )
            } else if let user = currentUser {
                if user.athletes.isEmpty {
                    AthleteSelectionView(
                        user: user,
                        selectedAthlete: $selectedAthlete
                    )
                } else {
                    MainTabView(
                        user: user,
                        selectedAthlete: $selectedAthlete
                    )
                }
            }
        }
        .onAppear {
            // Check if we have a user
            if let existingUser = users.first {
                currentUser = existingUser
                showingAuth = false
                selectedAthlete = existingUser.athletes.first
            }
        }
    }
}

// MARK: - Authentication View
struct AuthenticationView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var currentUser: User?
    @Binding var showingAuth: Bool
    
    @State private var isLogin = true
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                // App Logo
                VStack {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                    
                    Text("PlayerPath")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("Your Baseball Journey Starts Here")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 20)
                
                VStack(spacing: 20) {
                    if !isLogin {
                        TextField("Username", text: $username)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    TextField("Email", text: $email)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                    
                    SecureField("Password", text: $password)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    if !isLogin {
                        SecureField("Confirm Password", text: $confirmPassword)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                }
                
                VStack(spacing: 15) {
                    Button(action: authenticateUser) {
                        Text(isLogin ? "Sign In" : "Sign Up")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .disabled(email.isEmpty || password.isEmpty)
                    
                    Button(action: { isLogin.toggle() }) {
                        Text(isLogin ? "Don't have an account? Sign Up" : "Already have an account? Sign In")
                            .foregroundColor(.blue)
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationBarHidden(true)
        }
        .alert("Authentication", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func authenticateUser() {
        // Basic validation
        guard !email.isEmpty, !password.isEmpty else {
            showAlert("Please fill in all fields")
            return
        }
        
        if !isLogin {
            guard !username.isEmpty else {
                showAlert("Please enter a username")
                return
            }
            
            guard password == confirmPassword else {
                showAlert("Passwords don't match")
                return
            }
        }
        
        // For demo purposes, we'll create a user directly
        // In a real app, you'd integrate with Firebase Auth, etc.
        let user = User(username: isLogin ? email : username, email: email)
        modelContext.insert(user)
        
        do {
            try modelContext.save()
            currentUser = user
            showingAuth = false
        } catch {
            showAlert("Failed to create account: \(error.localizedDescription)")
        }
    }
    
    private func showAlert(_ message: String) {
        alertMessage = message
        showingAlert = true
    }
}

// MARK: - Athlete Selection View
struct AthleteSelectionView: View {
    @Environment(\.modelContext) private var modelContext
    let user: User
    @Binding var selectedAthlete: Athlete?
    @State private var showingAddAthlete = false
    
    var body: some View {
        NavigationStack {
            VStack {
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
                    }
                    .padding()
                } else {
                    List {
                        ForEach(user.athletes) { athlete in
                            AthleteRow(athlete: athlete) {
                                selectedAthlete = athlete
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Athlete")
            .toolbar {
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
            AddAthleteView(user: user, selectedAthlete: $selectedAthlete)
        }
    }
}

struct AthleteRow: View {
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

struct AddAthleteView: View {
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

// Helper extension for date formatting
extension DateFormatter {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter
    }()
}