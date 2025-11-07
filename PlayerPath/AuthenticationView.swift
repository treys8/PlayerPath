//
//  AuthenticationView.swift
//  PlayerPath
//
//  Created by Assistant on 11/1/25.
//

import SwiftUI
import FirebaseAuth

struct AuthenticationView: View {
    @Environment(AuthenticationManager.self) private var authManager
    
    var body: some View {
        SignInView()
            .environmentObject(authManager)
    }
}

// MARK: - Loading View
struct LoadingView: View {
    let title: String
    
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
                .progressViewStyle(CircularProgressViewStyle())
            
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview {
    AuthenticationView()
        .environment(AuthenticationManager())
}