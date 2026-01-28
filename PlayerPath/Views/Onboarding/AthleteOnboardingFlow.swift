//
//  AthleteOnboardingFlow.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI
import SwiftData

struct AthleteOnboardingFlow: View {
    let modelContext: ModelContext
    @ObservedObject var authManager: ComprehensiveAuthManager
    let user: User

    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                Spacer()

                // ATHLETE BADGE - Makes it obvious this is the athlete flow
                HStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "figure.baseball")
                            .font(.caption)
                        Text("ATHLETE ACCOUNT")
                            .font(.caption)
                            .fontWeight(.bold)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.blue.opacity(0.2))
                    )
                    .foregroundColor(.blue)
                    Spacer()
                }

                VStack(spacing: 24) {
                    ZStack {
                        // Glow effect
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [.orange.opacity(0.3), .clear],
                                    center: .center,
                                    startRadius: 20,
                                    endRadius: 80
                                )
                            )
                            .frame(width: 160, height: 160)
                            .blur(radius: 20)

                        Image(systemName: "hand.wave.fill")
                            .font(.system(size: 100, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.orange, .yellow],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .symbolRenderingMode(.hierarchical)
                            .shadow(color: .orange.opacity(0.4), radius: 15, x: 0, y: 8)
                    }

                    VStack(spacing: 16) {
                        Text("Welcome to PlayerPath!")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.8)
                            .accessibilityAddTraits(.isHeader)

                        Text("Let's get you set up to begin tracking")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }

                // Onboarding benefits
                VStack(alignment: .leading, spacing: 16) {
                    Text("What You Can Do:")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .padding(.bottom, 8)
                        .accessibilityAddTraits(.isHeader)

                    FeatureHighlight(
                        icon: "person.crop.circle.badge.plus",
                        title: "Create Athlete Profiles",
                        description: "Track multiple players and their progress"
                    )

                    FeatureHighlight(
                        icon: "video.circle.fill",
                        title: "Record & Analyze",
                        description: "Capture sessions and games"
                    )

                    FeatureHighlight(
                        icon: "chart.line.uptrend.xyaxis.circle.fill",
                        title: "Track Statistics",
                        description: "Monitor batting averages and performance"
                    )

                    FeatureHighlight(
                        icon: "arrow.triangle.2.circlepath.circle.fill",
                        title: "Sync Everywhere",
                        description: "Access your data on all your devices"
                    )
                }
                .padding(.horizontal)

                Spacer()

                Button(action: { Haptics.medium(); completeOnboarding() }) {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("Get Started")
                            .font(.title3)
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(16)
                    .shadow(color: .blue.opacity(0.4), radius: 12, x: 0, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .accessibilityLabel("Complete onboarding and get started")
                .accessibilityHint("Completes the setup process and takes you to create your first athlete")
                .accessibilitySortPriority(1)

                Spacer()
            }
            .padding()
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func completeOnboarding() {
        print("🟡 Completing athlete onboarding welcome screens...")

        Task {
            do {
                // Create onboarding progress record
                let progress = OnboardingProgress()
                progress.markCompleted()
                modelContext.insert(progress)

                try modelContext.save()
                print("🟢 Successfully saved onboarding progress")

                // Mark onboarding complete but DON'T reset new user flag yet
                // The new user flag will be reset when first athlete is created
                await MainActor.run {
                    authManager.markOnboardingComplete()
                    print("🟢 Onboarding completed, user still flagged as new until athlete created")

                    // Provide haptic feedback
                    Haptics.medium()
                }
            } catch {
                print("🔴 Failed to save onboarding progress: \(error)")
            }
        }
    }
}
