//
//  AuthenticationView.swift
//  PlayerPath
//
//  Created by Assistant on 11/1/25.
//

import SwiftUI
import FirebaseAuth

// This view provides a simplified authentication interface
// that delegates to SignInView for the actual implementation
struct AuthenticationView: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    
    var body: some View {
        SignInView()
            .environmentObject(authManager)
    }
}

// Keep the old name as an alias for compatibility
typealias SimpleAuthenticationView = AuthenticationView

#Preview {
    AuthenticationView()
        .environmentObject(ComprehensiveAuthManager())
}
