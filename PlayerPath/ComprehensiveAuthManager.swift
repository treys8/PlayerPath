import SwiftUI
import SwiftUI
import Combine
import FirebaseAuth
import SwiftData

@MainActor
final class ComprehensiveAuthManager: ObservableObject {
    @Published private(set) var currentFirebaseUser: FirebaseAuth.User?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isNewUser: Bool = false // Track if this was a signup vs signin
    
    @Published var localUser: User?
    @Published var hasCompletedOnboarding: Bool = false
    
    // Make isSignedIn a @Published property for better UI reactivity
    @Published private(set) var isSignedIn: Bool = false
    
    // Computed properties to access Firebase user information
    var userEmail: String? {
        currentFirebaseUser?.email
    }
    
    var userDisplayName: String? {
        currentFirebaseUser?.displayName
    }
    
    var userID: String? {
        currentFirebaseUser?.uid
    }
    
    // Premium features
    @Published var isPremiumUser: Bool = false
    @Published var trialDaysRemaining: Int = 30
    
    private var authStateDidChangeListenerHandle: AuthStateDidChangeListenerHandle?
    private var modelContext: ModelContext?
    
    init() {
        currentFirebaseUser = Auth.auth().currentUser
        isSignedIn = currentFirebaseUser != nil
        authStateDidChangeListenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentFirebaseUser = user
                self?.isSignedIn = user != nil
                // Reset new user flag when auth state changes (unless it's a signup)
                if user == nil {
                    self?.isNewUser = false
                }
            }
            if user != nil {
                Task {
                    await self?.ensureLocalUser()
                }
            }
        }
    }
    
    deinit {
        if let handle = authStateDidChangeListenerHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
    
    func attachModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    func ensureLocalUser() async {
        guard let context = modelContext,
              let firebaseUser = Auth.auth().currentUser,
              let email = firebaseUser.email else {
            return
        }
        
        let fetchDescriptor = FetchDescriptor<User>(predicate: #Predicate<User> { $0.email == email })
        
        do {
            let users = try context.fetch(fetchDescriptor)
            if let existingUser = users.first {
                await MainActor.run {
                    self.localUser = existingUser
                }
            } else {
                let newUser = User(username: firebaseUser.displayName ?? email, email: email)
                context.insert(newUser)
                try context.save()
                await MainActor.run {
                    self.localUser = newUser
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load user profile"
            }
        }
    }
    
    func markOnboardingComplete() {
        hasCompletedOnboarding = true
    }
    
    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        isNewUser = false // This is a sign-in, not a new user
        
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            currentFirebaseUser = result.user
            isSignedIn = true
            isLoading = false
            print("🟢 Sign in successful for: \(result.user.email ?? "unknown")")
        } catch {
            errorMessage = friendlyErrorMessage(from: error)
            isLoading = false
            print("🔴 Sign in error: \(error.localizedDescription)")
        }
    }
    
    func signUp(email: String, password: String, displayName: String?) async {
        isLoading = true
        errorMessage = nil
        isNewUser = true // This is a signup, mark as new user
        
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            if let displayName = displayName, !displayName.isEmpty {
                let changeRequest = result.user.createProfileChangeRequest()
                changeRequest.displayName = displayName
                try await changeRequest.commitChanges()
            }
            currentFirebaseUser = result.user
            isSignedIn = true
            isLoading = false
            // Keep isNewUser = true so the app knows this was a signup
            print("🟢 Sign up successful for: \(result.user.email ?? "unknown")")
        } catch {
            errorMessage = friendlyErrorMessage(from: error)
            isLoading = false
            isNewUser = false
            print("🔴 Sign up error: \(error.localizedDescription)")
        }
    }
    
    func signOut() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try Auth.auth().signOut()
            currentFirebaseUser = nil
            isSignedIn = false
            isLoading = false
            isNewUser = false
            errorMessage = nil
            print("🟢 Sign out successful")
        } catch {
            errorMessage = "Failed to sign out: \(error.localizedDescription)"
            isLoading = false
            print("🔴 Sign out error: \(error.localizedDescription)")
        }
    }
    
    func resetPassword(email: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
            isLoading = false
            print("🟢 Password reset sent to: \(email)")
        } catch {
            errorMessage = friendlyErrorMessage(from: error)
            isLoading = false
            print("🔴 Password reset error: \(error.localizedDescription)")
        }
    }
    
    func resetNewUserFlag() {
        isNewUser = false
    }
    
    // Method to allow external sign-in managers (like Apple Sign In) to update the user
    func updateCurrentUser(_ user: FirebaseAuth.User, isNewUser: Bool = false) {
        currentFirebaseUser = user
        isSignedIn = true
        self.isNewUser = isNewUser
    }
    
    private func friendlyErrorMessage(from error: Error) -> String {
        let authError = error as NSError
        
        switch authError.code {
        case AuthErrorCode.emailAlreadyInUse.rawValue:
            return "An account with this email already exists. Try signing in instead."
        case AuthErrorCode.weakPassword.rawValue:
            return "Password is too weak. Please use at least 8 characters with a mix of letters, numbers, and symbols."
        case AuthErrorCode.invalidEmail.rawValue:
            return "Please enter a valid email address."
        case AuthErrorCode.userNotFound.rawValue:
            return "No account found with this email. Please check your email or sign up for a new account."
        case AuthErrorCode.wrongPassword.rawValue:
            return "Incorrect password. Please try again or reset your password."
        case AuthErrorCode.networkError.rawValue:
            return "Network error. Please check your internet connection and try again."
        case AuthErrorCode.tooManyRequests.rawValue:
            return "Too many attempts. Please try again later."
        case AuthErrorCode.userDisabled.rawValue:
            return "This account has been disabled. Please contact support."
        default:
            return error.localizedDescription
        }
    }
}
