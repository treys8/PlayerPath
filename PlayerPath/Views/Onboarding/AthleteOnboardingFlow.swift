//
//  AthleteOnboardingFlow.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct AthleteOnboardingFlow: View {
    let modelContext: ModelContext
    @ObservedObject var authManager: ComprehensiveAuthManager
    let user: User
    @State private var isCompleting = false

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
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.8)
                            .accessibilityAddTraits(.isHeader)

                        Text("We'll get you set up in 3 quick steps")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }

                // Setup steps preview
                VStack(alignment: .leading, spacing: 12) {
                    Text("Here's what's next:")
                        .font(.headline)
                        .fontWeight(.bold)
                        .padding(.bottom, 4)
                        .accessibilityAddTraits(.isHeader)

                    FeatureHighlight(
                        icon: "person.crop.circle.badge.plus",
                        title: "Create an Athlete Profile",
                        description: "Add your player's name to start tracking",
                        color: .blue
                    )

                    FeatureHighlight(
                        icon: "calendar.badge.plus",
                        title: "Set Up Your Season",
                        description: "Organize games and track stats over time",
                        color: .green
                    )

                    FeatureHighlight(
                        icon: "icloud.and.arrow.up",
                        title: "Choose Backup Settings",
                        description: "Keep your videos safe in the cloud",
                        color: .purple
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
                    .disabled(isCompleting)
                    .accessibilityLabel("Start setup")
                    .accessibilityHint("Begin the 3-step setup process")
                    .accessibilitySortPriority(1)

                    Text("Takes less than 2 minutes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding()
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func completeOnboarding() {
        guard !isCompleting else { return }
        isCompleting = true

        // Mark onboarding complete immediately so the transition fires without delay
        authManager.markOnboardingComplete()
        Haptics.medium()

        // Persist to SwiftData in the background so the save doesn't block the transition
        Task.detached { @MainActor in
            let progress = OnboardingProgress(firebaseAuthUid: authManager.currentFirebaseUser?.uid ?? "")
            progress.markCompleted()
            modelContext.insert(progress)
            for attempt in 1...3 {
                do {
                    try modelContext.save()
                    return
                } catch {
                    if attempt < 3 {
                        try? await Task.sleep(for: .seconds(1))
                    }
                }
            }
        }
    }
}
