// 
// AppRootView.swift - DEPRECATED
// This file is no longer used - replaced by MainAppView.swift
// Keeping for reference only - all functionality moved to PlayerPathMainView
//

/*
 DEPRECATED: This entire file is commented out to resolve build conflicts.
 The main app now uses PlayerPathMainView in MainAppView.swift
*/

/*

/// Simplified authentication and user management
@MainActor
final class AppAuthManager: ObservableObject {
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var modelContext: ModelContext?
    private var authStateListener: AuthStateDidChangeListenerHandle?
    
    init() {
        startAuthStateListener()
    }
    
    deinit {
        if let listener = authStateListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }
    
    func setup(context: ModelContext) {
        self.modelContext = context
        
        // Load user if already authenticated
        if isAuthenticated {
            Task { 
                await loadUser() 
            }
        }
    }
    
    private func startAuthStateListener() {
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isAuthenticated = user != nil
                self.errorMessage = nil
                
                if user != nil {
                    await self.loadUser()
                } else {
                    self.currentUser = nil
                }
            }
        }
    }
    
    func loadUser() async {
        guard let firebaseUser = Auth.auth().currentUser,
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
            errorMessage = "Failed to load user profile"
        }
        
        isLoading = false
    }
    
    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            _ = try await Auth.auth().signIn(withEmail: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func signUp(email: String, password: String, displayName: String? = nil) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            
            // Set display name if provided
            if let displayName = displayName, !displayName.isEmpty {
                let changeRequest = result.user.createProfileChangeRequest()
                changeRequest.displayName = displayName
                try await changeRequest.commitChanges()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func signOut() {
        do {
            try Auth.auth().signOut()
            currentUser = nil
        } catch {
            errorMessage = "Failed to sign out: \(error.localizedDescription)"
        }
    }
    
    func sendPasswordReset(email: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
        } catch {
            errorMessage = "Failed to send password reset: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}

/// Simplified main app view that handles the complete flow
struct AppRootView: View {
    @StateObject private var authManager = AppAuthManager()
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        Group {
            if authManager.isAuthenticated {
                if let user = authManager.currentUser {
                    MainAppContentView(user: user)
                } else if authManager.isLoading {
                    LoadingView(title: "Setting up your profile...")
                } else {
                    AppErrorView(message: authManager.errorMessage ?? "Failed to load user profile", onRetry: {
                        Task { 
                            await authManager.loadUser() 
                        }
                    })
                }
            } else {
                SimpleAuthenticationView()
                    .environmentObject(authManager)
            }
        }
        .onAppear {
            setupManagers()
        }
        .environmentObject(authManager)
    }
    
    private func setupManagers() {
        authManager.setup(context: modelContext)
    }
}

/// Main app content after authentication and onboarding
struct MainAppContentView: View {
    let user: User
    @EnvironmentObject private var authManager: AppAuthManager
    
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
                        authManager.signOut()
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

// MARK: - Simple Authentication View

struct SimpleAuthenticationView: View {
    @EnvironmentObject private var authManager: AppAuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isSignUp = false
    @State private var showingForgotPassword = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                // Logo section
                VStack(spacing: 16) {
                    Image(systemName: "baseball.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                    
                    Text("PlayerPath")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Track your baseball journey")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                
                // Form section
                VStack(spacing: 16) {
                    if isSignUp {
                        TextField("Display Name", text: $displayName)
                            .textFieldStyle(RoundedTextFieldStyle())
                    }
                    
                    TextField("Email", text: $email)
                        .textFieldStyle(RoundedTextFieldStyle())
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                    
                    SecureField("Password", text: $password)
                        .textFieldStyle(RoundedTextFieldStyle())
                    
                    Button(action: authenticate) {
                        HStack {
                            if authManager.isLoading {
                                ProgressView()
                                    .scaleEffect(0.9)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text(isSignUp ? "Create Account" : "Sign In")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(email.isEmpty || password.isEmpty || authManager.isLoading)
                }
                .padding(.horizontal)
                
                // Error message
                if let errorMessage = authManager.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Toggle sign up/in
                Button(action: {
                    isSignUp.toggle()
                    authManager.errorMessage = nil
                }) {
                    Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
                
                // Forgot password
                if !isSignUp {
                    Button("Forgot Password?") {
                        showingForgotPassword = true
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.vertical, 32)
            .navigationTitle("")
            .navigationBarHidden(true)
            .alert("Reset Password", isPresented: $showingForgotPassword) {
                TextField("Email", text: $email)
                Button("Send Reset Link") {
                    Task {
                        await authManager.sendPasswordReset(email: email)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Enter your email address to receive a password reset link.")
            }
        }
    }
    
    private func authenticate() {
        Task {
            if isSignUp {
                await authManager.signUp(email: email, password: password, displayName: displayName.isEmpty ? nil : displayName)
            } else {
                await authManager.signIn(email: email, password: password)
            }
        }
    }
}

// MARK: - Custom Styles

private struct RoundedTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .frame(height: 56)
            .frame(maxWidth: .infinity)
            .background(Color.blue)
            .cornerRadius(16)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Utility Views

private struct AppErrorView: View {
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
    PlayerPathMainView()
        .modelContainer(for: [User.self, Athlete.self, Statistics.self])
}
*/
