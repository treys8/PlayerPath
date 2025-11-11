//
//  AuthenticationTestView.swift
//  PlayerPath - Test file to verify authentication works
//
//  Created by Assistant on 11/1/25.
//

import SwiftUI
import SwiftData
import FirebaseAuth

/// Test view to verify authentication manager works correctly
struct AuthenticationTestView: View {
    @StateObject private var authManager = ComprehensiveAuthManager()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Authentication Test")
                .font(.largeTitle)
            
            Text("Authenticated: \(authManager.isSignedIn ? "✅" : "❌")")
            Text("Loading: \(authManager.isLoading ? "⏳" : "✅")")
            
            if let errorMessage = authManager.errorMessage {
                Text("Error: \(errorMessage)")
                    .foregroundColor(.red)
            }
            
            if let user = authManager.currentFirebaseUser {
                Text("User: \(user.email ?? "Unknown")")
                    .foregroundColor(.green)
            }
            
            Button("Test Sign In") {
                Task {
                    await authManager.signIn(email: "test@test.com", password: "test123")
                }
            }
            
            Button("Test Sign Out") {
                Task {
                    await authManager.signOut()
                }
            }
            
            // Test both authentication views work
            VStack {
                Text("Authentication Views:")
                
                NavigationLink("Test AuthenticationView") {
                    AuthenticationView()
                        .environmentObject(authManager)
                }
            }
        }
        .padding()
    }
}

#Preview {
    NavigationStack {
        AuthenticationTestView()
    }
    .modelContainer(for: [
        User.self,
        Athlete.self,
        AthleteStatistics.self,
        Game.self,
        GameStatistics.self,
        Tournament.self,
        Practice.self,
        PracticeNote.self,
        VideoClip.self,
        PlayResult.self,
        OnboardingProgress.self
    ])
}
