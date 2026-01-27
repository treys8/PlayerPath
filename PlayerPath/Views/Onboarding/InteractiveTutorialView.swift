//
//  InteractiveTutorialView.swift
//  PlayerPath
//
//  Interactive tutorial that guides new users through the app
//

import SwiftUI

struct InteractiveTutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var onboardingManager = OnboardingManager.shared

    let tutorial: Tutorial
    @State private var currentStepIndex = 0
    @State private var progress: Double = 0

    private var currentStep: TutorialStep {
        tutorial.steps[currentStepIndex]
    }

    private var isLastStep: Bool {
        currentStepIndex == tutorial.steps.count - 1
    }

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress bar
                ProgressView(value: progress, total: 1.0)
                    .tint(.blue)
                    .padding(.horizontal)
                    .padding(.top, 8)

                ScrollView {
                    VStack(spacing: 32) {
                        Spacer()
                            .frame(height: 40)

                        // Step icon
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .frame(width: 120, height: 120)

                            Image(systemName: currentStep.imageName)
                                .font(.system(size: 50))
                                .foregroundStyle(.white)
                        }
                        .shadow(color: .blue.opacity(0.3), radius: 20)

                        // Step content
                        VStack(spacing: 16) {
                            Text(currentStep.title)
                                .font(.title)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)

                            Text(currentStep.description)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }

                        // Step indicator dots
                        HStack(spacing: 8) {
                            ForEach(0..<tutorial.steps.count, id: \.self) { index in
                                Circle()
                                    .fill(index == currentStepIndex ? Color.blue : Color.gray.opacity(0.3))
                                    .frame(width: 8, height: 8)
                                    .scaleEffect(index == currentStepIndex ? 1.2 : 1.0)
                                    .animation(.spring(response: 0.3), value: currentStepIndex)
                            }
                        }
                        .padding(.top, 16)

                        Spacer()
                            .frame(height: 40)
                    }
                    .padding()
                }

                // Navigation buttons
                VStack(spacing: 12) {
                    if isLastStep {
                        Button {
                            completeTutorial()
                        } label: {
                            Text("Get Started")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .foregroundStyle(.white)
                                .cornerRadius(12)
                        }
                        .accessibleButton(label: "Get started with PlayerPath")
                    } else {
                        Button {
                            nextStep()
                        } label: {
                            HStack {
                                Text("Next")
                                    .font(.headline)
                                Image(systemName: "arrow.right")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                        }
                        .accessibleButton(label: "Next step", hint: "Move to the next tutorial step")
                    }

                    Button {
                        skipTutorial()
                    } label: {
                        Text("Skip Tutorial")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
            }
        }
        .onAppear {
            updateProgress()
        }
    }

    private func nextStep() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentStepIndex += 1
            updateProgress()
        }
        Haptics.light()
    }

    private func updateProgress() {
        progress = Double(currentStepIndex + 1) / Double(tutorial.steps.count)
    }

    private func skipTutorial() {
        onboardingManager.skipTutorial()
        dismiss()
        Haptics.light()
    }

    private func completeTutorial() {
        onboardingManager.completeTutorial()
        dismiss()
        Haptics.success()

        // Show completion announcement
        AccessibilityAnnouncer.announce("Tutorial completed! You're ready to start tracking your baseball journey.")
    }
}

// MARK: - Welcome Tutorial (First Time User Experience)

struct WelcomeTutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var onboardingManager = OnboardingManager.shared

    var body: some View {
        InteractiveTutorialView(tutorial: .welcome)
    }
}

#Preview("Welcome Tutorial") {
    WelcomeTutorialView()
}

#Preview("Video Recording Tutorial") {
    InteractiveTutorialView(tutorial: .videoRecording)
}
