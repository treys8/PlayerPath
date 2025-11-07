//
//  AuthenticationTestView.swift
//  PlayerPath - Test file to verify authentication works
//
//  Created by Assistant on 11/1/25.
//

import SwiftUI
import SwiftData

/// Test view to verify authentication manager works correctly
struct AuthenticationTestView: View {
    @StateObject private var authManager = AppAuthManager()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Authentication Test")
                .font(.largeTitle)
            
            Text("Authenticated: \(authManager.isAuthenticated ? "✅" : "❌")")
            Text("Loading: \(authManager.isLoading ? "⏳" : "✅")")
            
            if let errorMessage = authManager.errorMessage {
                Text("Error: \(errorMessage)")
                    .foregroundColor(.red)
            }
            
            if let user = authManager.currentUser {
                Text("User: \(user.username)")
                    .foregroundColor(.green)
            }
            
            Button("Test Sign In") {
                Task {
                    await authManager.signIn(email: "test@test.com", password: "test123")
                }
            }
            
            Button("Test Sign Out") {
                authManager.signOut()
            }
            
            // Test both authentication views work
            VStack {
                Text("Authentication Views:")
                
                NavigationLink("Test AuthenticationView") {
                    AuthenticationView()
                        .environmentObject(authManager)
                }
                
                NavigationLink("Test SimpleAuthenticationView") {
                    SimpleAuthenticationView()
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
    .modelContainer(for: [User.self, Athlete.self, Statistics.self])
}