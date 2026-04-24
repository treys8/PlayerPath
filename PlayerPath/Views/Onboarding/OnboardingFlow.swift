//
//  OnboardingFlow.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI
import SwiftData

struct OnboardingFlow: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    let user: User

    var body: some View {
        // Show different onboarding based on user role
        Group {
            if authManager.userRole == .coach {
                CoachOnboardingFlow(user: user)
            } else {
                AthleteOnboardingFlow(user: user)
            }
        }
    }
}
