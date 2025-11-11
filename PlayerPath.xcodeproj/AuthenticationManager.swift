//
//  AuthenticationManager.swift
//  PlayerPath
//
//  Firebase Authentication Manager for cross-platform user accounts
//

import Foundation
import FirebaseAuth
// import GoogleSignIn // Temporarily commented out
import SwiftUI

@MainActor
class AuthenticationManager: ObservableObject {
    @Published var user: FirebaseAuth.User?
    @Published var isSignedIn = false
    @Published var isLoading = false
    @Published var errorMessage = ""
    
    init() {
        // Listen for authentication state changes
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.user = user
                self?.isSignedIn = user != nil
            }
        }
    }
    
    // MARK: - Google Sign In (Temporarily disabled - need to add GoogleSignIn package)
    /*
    func signInWithGoogle() async {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            errorMessage = "Could not find root view controller"
            return
        }
        
        isLoading = true
        errorMessage = ""
        
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
            
            guard let idToken = result.user.idToken?.tokenString else {
                errorMessage = "Failed to get ID token from Google"
                isLoading = false
                return
            }
            
            let accessToken = result.user.accessToken.tokenString
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
            
            let authResult = try await Auth.auth().signIn(with: credential)
            
            print("Successfully signed in user: \(authResult.user.displayName ?? "Unknown")")
            
        } catch {
            errorMessage = "Sign in failed: \(error.localizedDescription)"
            print("Google Sign In Error: \(error)")
        }
        
        isLoading = false
    }
    */
    
    // MARK: - Email/Password Sign In
    func signInWithEmail(_ email: String, password: String) async {
        isLoading = true
        errorMessage = ""
        
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            print("Successfully signed in user: \(result.user.email ?? "Unknown")")
        } catch {
            errorMessage = "Sign in failed: \(error.localizedDescription)"
            print("Email Sign In Error: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Create Account
    func createAccount(email: String, password: String, displayName: String) async {
        isLoading = true
        errorMessage = ""
        
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            
            // Update the user's display name
            let changeRequest = result.user.createProfileChangeRequest()
            changeRequest.displayName = displayName
            try await changeRequest.commitChanges()
            
            print("Successfully created account for: \(displayName)")
            
        } catch {
            errorMessage = "Account creation failed: \(error.localizedDescription)"
            print("Account Creation Error: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Sign Out
    func signOut() {
        do {
            try Auth.auth().signOut()
            // GIDSignIn.sharedInstance.signOut() // Commented out until GoogleSignIn is added
            print("Successfully signed out")
        } catch {
            errorMessage = "Sign out failed: \(error.localizedDescription)"
            print("Sign Out Error: \(error)")
        }
    }
    
    // MARK: - Anonymous Sign In (for trying the app without account)
    func signInAnonymously() async {
        isLoading = true
        errorMessage = ""
        
        do {
            let result = try await Auth.auth().signInAnonymously()
            print("Signed in anonymously: \(result.user.uid)")
        } catch {
            errorMessage = "Anonymous sign in failed: \(error.localizedDescription)"
            print("Anonymous Sign In Error: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Helper Methods
    var userDisplayName: String {
        return user?.displayName ?? user?.email ?? "User"
    }
    
    var userEmail: String {
        return user?.email ?? ""
    }
    
    var userId: String {
        return user?.uid ?? ""
    }
    
    var isAnonymous: Bool {
        return user?.isAnonymous ?? false
    }
}