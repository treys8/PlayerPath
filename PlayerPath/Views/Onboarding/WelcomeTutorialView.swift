//
//  WelcomeTutorialView.swift
//  PlayerPath
//

import SwiftUI

struct WelcomeTutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var onboardingManager = OnboardingManager.shared

    private let steps = Tutorial.welcome.steps
    @State private var currentIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentIndex) {
                ForEach(steps.indices, id: \.self) { index in
                    stepView(steps[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button(currentIndex < steps.count - 1 ? "Next" : "Get Started") {
                if currentIndex < steps.count - 1 {
                    withAnimation { currentIndex += 1 }
                } else {
                    onboardingManager.markMilestoneComplete(.welcomeTutorial)
                    dismiss()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .interactiveDismissDisabled(false)
        .onDisappear {
            // Ensure milestone is marked even if user swipes to dismiss
            // (the "Get Started" button also marks it, but this is the safety net)
            if !onboardingManager.hasSeenWelcomeTutorial {
                onboardingManager.markMilestoneComplete(.welcomeTutorial)
            }
        }
    }

    private func stepView(_ step: TutorialStep) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: step.imageName)
                .font(.system(size: 72))
                .foregroundStyle(.blue)
            Text(step.title)
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            Text(step.description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
    }
}
