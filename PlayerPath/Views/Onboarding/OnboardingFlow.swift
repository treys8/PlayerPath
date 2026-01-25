//
//  OnboardingFlow.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI
import SwiftData

struct OnboardingFlow: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    let user: User
    @State private var selectedAthlete: Athlete?

    var body: some View {
        // Show different onboarding based on user role
        Group {
            if authManager.userRole == .coach {
                CoachOnboardingFlow(
                    modelContext: modelContext,
                    authManager: authManager,
                    user: user
                )
            } else {
                AthleteOnboardingFlow(
                    modelContext: modelContext,
                    authManager: authManager,
                    user: user
                )
            }
        }
        .onAppear {
            print("🎯 OnboardingFlow - User role: \(authManager.userRole.rawValue)")
            print("🎯 OnboardingFlow - User email: \(user.email)")
            print("🎯 OnboardingFlow - Showing \(authManager.userRole == .coach ? "COACH" : "ATHLETE") onboarding")
            print("🎯 OnboardingFlow - isNewUser: \(authManager.isNewUser)")
            print("🎯 OnboardingFlow - isSignedIn: \(authManager.isSignedIn)")

            // Extra debugging
            if let profile = authManager.userProfile {
                print("🎯 OnboardingFlow - Profile role: \(profile.userRole.rawValue)")
                print("🎯 OnboardingFlow - Profile email: \(profile.email)")
            } else {
                print("⚠️ OnboardingFlow - NO PROFILE LOADED (this is expected for new users)")
                print("⚠️ OnboardingFlow - Using local userRole value: \(authManager.userRole.rawValue)")
            }
        }
    }
}
