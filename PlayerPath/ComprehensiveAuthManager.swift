import SwiftUI
import Combine
import FirebaseAuth

final class ComprehensiveAuthManager: ObservableObject {
    @Published private(set) var currentUser: User?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    var isSignedIn: Bool {
        currentUser != nil
    }
    
    // Stubs for premium features
    var isPremiumUser: Bool {
        false
    }
    var trialDaysRemaining: Int {
        0
    }
    
    private var authStateDidChangeListenerHandle: AuthStateDidChangeListenerHandle?
    
    init() {
        currentUser = Auth.auth().currentUser
        authStateDidChangeListenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUser = user
            }
        }
    }
    
    deinit {
        if let handle = authStateDidChangeListenerHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
    
    func signIn(email: String, password: String) async {
        await MainActor.run { 
            self.isLoading = true
            self.errorMessage = nil
        }
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            await MainActor.run {
                self.currentUser = result.user
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    func signUp(email: String, password: String, displayName: String?) async {
        await MainActor.run { 
            self.isLoading = true
            self.errorMessage = nil
        }
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            if let displayName = displayName, !displayName.isEmpty {
                let changeRequest = result.user.createProfileChangeRequest()
                changeRequest.displayName = displayName
                try await changeRequest.commitChanges()
            }
            await MainActor.run {
                self.currentUser = result.user
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    func signOut() async {
        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
        }
        do {
            try Auth.auth().signOut()
            await MainActor.run {
                self.currentUser = nil
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    func resetPassword(email: String) async {
        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
        }
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
            await MainActor.run {
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}
