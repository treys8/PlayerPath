//
//  AthleteOnboardingFlow.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI
import SwiftData

struct AthleteOnboardingFlow: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.ppAccent) private var ppAccent
    @Environment(\.ppAccentLight) private var ppAccentLight
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    let user: User
    @State private var isCompleting = false
    @State private var errorMessage: String?
    @State private var showingError = false
    /// Tracks whether onboarding finished successfully so onDisappear can
    /// distinguish completion from abandonment.
    @State private var didComplete = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [ppAccent.opacity(0.3), .clear],
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
                                    colors: [ppAccent, ppAccentLight],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .symbolRenderingMode(.hierarchical)
                            .shadow(color: ppAccent.opacity(0.4), radius: 15, x: 0, y: 8)
                    }

                    VStack(spacing: 16) {
                        Text("Welcome to PlayerPath!")
                            .font(.displayLarge)
                            .foregroundColor(Theme.textPrimary)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.8)
                            .accessibilityAddTraits(.isHeader)

                        Text("We'll get you set up in 3 quick steps")
                            .font(.bodyLarge)
                            .foregroundColor(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }

                // Setup steps preview
                VStack(alignment: .leading, spacing: 12) {
                    Text("Here's what's next:")
                        .font(.headingLarge)
                        .foregroundColor(Theme.textPrimary)
                        .padding(.bottom, 4)
                        .accessibilityAddTraits(.isHeader)

                    FeatureHighlight(
                        icon: "person.crop.circle.badge.plus",
                        title: "Create an Athlete Profile",
                        description: "Add your player's name to start tracking"
                    )

                    FeatureHighlight(
                        icon: "calendar.badge.plus",
                        title: "Set Up Your Season",
                        description: "Organize seasons and track stats over time"
                    )

                    FeatureHighlight(
                        icon: "icloud.and.arrow.up",
                        title: "Choose Backup Settings",
                        description: "Keep your videos safe in the cloud"
                    )
                }
                .padding(.horizontal)

                Spacer()

                VStack(spacing: 8) {
                    Button(action: { Haptics.medium(); completeOnboarding() }) {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.title3)
                                .fontWeight(.semibold)
                            Text("Let's Go")
                                .font(.headingLarge)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(
                            LinearGradient(
                                colors: [ppAccent, ppAccent.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(16)
                        .shadow(color: ppAccent.opacity(0.4), radius: 12, x: 0, y: 6)
                    }
                    .buttonStyle(.plain)
                    .disabled(isCompleting)
                    .accessibilityLabel("Start setup")
                    .accessibilityHint("Begin the 3-step setup process")
                    .accessibilitySortPriority(1)

                    Text("Takes less than 2 minutes")
                        .font(.bodySmall)
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding()
            .background(Theme.surface, ignoresSafeAreaEdges: .all)
            .toolbar(.hidden, for: .navigationBar)
            .alert("Setup Failed", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .onAppear {
            AnalyticsService.shared.trackOnboardingStarted(role: "athlete")
            AnalyticsService.shared.trackOnboardingStepView(role: "athlete", step: 0, stepName: "welcome")
        }
        .onDisappear {
            if !didComplete {
                AnalyticsService.shared.trackOnboardingAbandoned(role: "athlete", lastStep: 0)
            }
        }
    }

    private func completeOnboarding() {
        guard !isCompleting else { return }
        isCompleting = true

        Task {
            // Optimistically mark complete BEFORE awaiting authManager —
            // completeOnboarding flips hasCompletedOnboarding mid-await,
            // which causes AuthenticatedFlow to swap us out for UserMainFlow.
            // That swap fires .onDisappear, which would otherwise log a
            // spurious onboarding_abandoned. Rolled back on failure.
            didComplete = true
            do {
                try await authManager.completeOnboarding(in: modelContext, resetNewUserFlag: false)
                AnalyticsService.shared.trackOnboardingCompleted(role: "athlete")
                Haptics.medium()
            } catch {
                didComplete = false
                modelContext.rollback()
                ErrorHandlerService.shared.handle(error, context: "AthleteOnboarding.completeOnboarding", showAlert: false)
                errorMessage = "Could not complete setup. Please try again."
                showingError = true
                isCompleting = false
            }
        }
    }
}
