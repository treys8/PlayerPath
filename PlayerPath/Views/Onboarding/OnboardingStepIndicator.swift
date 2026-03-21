//
//  OnboardingStepIndicator.swift
//  PlayerPath
//
//  Step progress indicator for the onboarding flow
//

import SwiftUI

struct OnboardingStepIndicator: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule()
                    .fill(index <= currentStep ? Color.brandNavy : Color.brandNavy.opacity(0.2))
                    .frame(width: index == currentStep ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentStep)
            }
        }
        .accessibilityLabel("Step \(currentStep + 1) of \(totalSteps)")
    }
}
