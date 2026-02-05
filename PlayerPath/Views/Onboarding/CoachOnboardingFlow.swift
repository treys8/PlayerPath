//
//  CoachOnboardingFlow.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI
import SwiftData

struct CoachOnboardingFlow: View {
    let modelContext: ModelContext
    @ObservedObject var authManager: ComprehensiveAuthManager
    let user: User

    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                Spacer()

                // COACH BADGE - Makes it obvious this is the coach flow
                HStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "person.fill.checkmark")
                            .font(.caption)
                        Text("COACH ACCOUNT")
                            .font(.caption)
                            .fontWeight(.bold)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.green.opacity(0.2))
                    )
                    .foregroundColor(.green)
                    Spacer()
                }

                VStack(spacing: 24) {
                    ZStack {
                        // Glow effect
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [.blue.opacity(0.3), .purple.opacity(0.2), .clear],
                                    center: .center,
                                    startRadius: 20,
                                    endRadius: 80
                                )
                            )
                            .frame(width: 160, height: 160)
                            .blur(radius: 20)

                        Image(systemName: "person.2.wave.2.fill")
                            .font(.system(size: 100, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .symbolRenderingMode(.hierarchical)
                            .shadow(color: .blue.opacity(0.4), radius: 15, x: 0, y: 8)
                    }

                    VStack(spacing: 16) {
                        Text("Welcome, Coach!")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)

                        Text("Your coaching dashboard is ready")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }

                // Coach-specific onboarding benefits
                VStack(alignment: .leading, spacing: 12) {
                    Text("As a Coach, You Can:")
                        .font(.headline)
                        .fontWeight(.bold)
                        .padding(.bottom, 4)
                        .accessibilityAddTraits(.isHeader)

                    FeatureHighlight(
                        icon: "folder.badge.person.crop",
                        title: "Access Shared Folders",
                        description: "View folders shared with you by your athletes",
                        color: .blue
                    )

                    FeatureHighlight(
                        icon: "video.badge.plus",
                        title: "Upload & Review Videos",
                        description: "Add videos and provide feedback",
                        color: .red
                    )

                    FeatureHighlight(
                        icon: "bubble.left.and.bubble.right.fill",
                        title: "Annotate & Comment",
                        description: "Add coaching insights and notes",
                        color: .purple
                    )

                    FeatureHighlight(
                        icon: "person.3.fill",
                        title: "Manage Multiple Athletes",
                        description: "Support all your athletes in one place",
                        color: .green
                    )
                }
                .padding(.horizontal)

                // Info message
                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.blue.opacity(0.15), .blue.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)

                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.blue)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("How It Works")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Athletes share folders via email. They'll appear in your dashboard.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(.systemGray5), lineWidth: 1)
                )
                .padding(.horizontal)

                Spacer()

                Button(action: { Haptics.medium(); completeCoachOnboarding() }) {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("Go to Dashboard")
                            .font(.title3)
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(16)
                    .shadow(
                        color: Color.blue.opacity(0.4),
                        radius: 12,
                        x: 0,
                        y: 6
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .accessibilityLabel("Complete coach onboarding")
                .accessibilityHint("Takes you to your coaching dashboard")
                .accessibilitySortPriority(1)

                Spacer()
            }
            .padding()
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func completeCoachOnboarding() {
        print("🟡 Completing coach onboarding for new user...")

        Task {
            do {
                // Create onboarding progress record
                let progress = OnboardingProgress()
                progress.markCompleted()
                modelContext.insert(progress)

                try modelContext.save()
                print("🟢 Successfully saved coach onboarding progress")

                // Reset the new user flag after successful onboarding
                await MainActor.run {
                    authManager.resetNewUserFlag()
                    authManager.markOnboardingComplete()
                    print("🟢 Reset new user flag, coach onboarding completed")

                    // Provide haptic feedback
                    Haptics.medium()
                }
            } catch {
                print("🔴 Failed to save coach onboarding progress: \(error)")
            }
        }
    }
}
