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
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    let user: User
    @State private var isCompleting = false
    @State private var errorMessage: String?
    @State private var showingError = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 24) {
                    ZStack {
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
                            .font(.displayLarge)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.8)
                            .accessibilityAddTraits(.isHeader)

                        Text("We'll get you set up in 3 quick steps")
                            .font(.bodyLarge)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }

                // Setup steps preview
                VStack(alignment: .leading, spacing: 12) {
                    Text("Here's what's next:")
                        .font(.headingLarge)
                        .padding(.bottom, 4)
                        .accessibilityAddTraits(.isHeader)

                    FeatureHighlight(
                        icon: "person.crop.circle.badge.plus",
                        title: "Create an Athlete Profile",
                        description: "Add your player's name to start tracking",
                        color: .brandNavy
                    )

                    FeatureHighlight(
                        icon: "calendar.badge.plus",
                        title: "Set Up Your Season",
                        description: "Organize games and track stats over time",
                        color: .brandNavy
                    )

                    FeatureHighlight(
                        icon: "icloud.and.arrow.up",
                        title: "Choose Backup Settings",
                        description: "Keep your videos safe in the cloud",
                        color: .brandNavy
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
                                colors: [Color.brandNavy, Color.brandNavy.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(16)
                        .shadow(color: Color.brandNavy.opacity(0.4), radius: 12, x: 0, y: 6)
                    }
                    .buttonStyle(.plain)
                    .disabled(isCompleting)
                    .accessibilityLabel("Start setup")
                    .accessibilityHint("Begin the 3-step setup process")
                    .accessibilitySortPriority(1)

                    Text("Takes less than 2 minutes")
                        .font(.bodySmall)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding()
            .toolbar(.hidden, for: .navigationBar)
            .alert("Setup Failed", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func completeOnboarding() {
        guard !isCompleting else { return }
        isCompleting = true

        Task {
            do {
                try await authManager.completeOnboarding(in: modelContext, resetNewUserFlag: false)
                Haptics.medium()
            } catch {
                modelContext.rollback()
                ErrorHandlerService.shared.handle(error, context: "AthleteOnboarding.completeOnboarding", showAlert: false)
                errorMessage = "Could not complete setup. Please try again."
                showingError = true
                isCompleting = false
            }
        }
    }
}
