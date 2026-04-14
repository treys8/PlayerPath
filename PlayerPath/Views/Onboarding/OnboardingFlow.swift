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
    }
}
