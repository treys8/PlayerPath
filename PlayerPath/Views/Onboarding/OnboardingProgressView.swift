//
//  OnboardingProgressView.swift
//  PlayerPath
//
//  Shows users their onboarding progress and suggests next actions
//

import SwiftUI

struct OnboardingProgressView: View {
    @StateObject private var onboardingManager = OnboardingManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Overall progress
                    progressCard

                    // Milestones
                    VStack(spacing: 12) {
                        ForEach(OnboardingMilestone.allCases, id: \.self) { milestone in
                            MilestoneRow(milestone: milestone)
                        }
                    }

                    // Next steps suggestion
                    if let nextAction = onboardingManager.nextSuggestedAction {
                        nextStepsCard(for: nextAction)
                    }

                    // Reset button (for testing)
                    #if DEBUG
                    Button("Reset Onboarding (Debug)") {
                        onboardingManager.resetAllOnboarding()
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top)
                    #endif
                }
                .padding()
            }
            .navigationTitle("Getting Started")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var progressCard: some View {
        VStack(spacing: 16) {
            // Progress circle
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 12)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: onboardingManager.onboardingProgress)
                    .stroke(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: onboardingManager.onboardingProgress)

                VStack(spacing: 4) {
                    Text("\(Int(onboardingManager.onboardingProgress * 100))%")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Complete")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 8) {
                Text("Your Progress")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("\(onboardingManager.completedMilestonesCount) of \(OnboardingMilestone.allCases.count) milestones completed")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
    }

    private func nextStepsCard(for milestone: OnboardingMilestone) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                Text("Next Steps")
                    .font(.headline)
            }

            HStack(spacing: 12) {
                Image(systemName: milestone.icon)
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 40, height: 40)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(milestone.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(milestone.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .padding(16)
        .background(Color.yellow.opacity(0.1))
        .cornerRadius(12)
    }
}

struct MilestoneRow: View {
    let milestone: OnboardingMilestone
    @StateObject private var onboardingManager = OnboardingManager.shared

    private var isCompleted: Bool {
        onboardingManager.hasMilestoneCompleted(milestone)
    }

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(isCompleted ? Color.green : Color.gray.opacity(0.2))
                    .frame(width: 44, height: 44)

                Image(systemName: isCompleted ? "checkmark" : milestone.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isCompleted ? .white : .gray)
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(milestone.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(isCompleted ? .primary : .secondary)

                Text(milestone.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(isCompleted ? Color.green.opacity(0.05) : Color.clear)
        .cornerRadius(12)
        .opacity(isCompleted ? 1.0 : 0.7)
    }
}

#Preview {
    OnboardingProgressView()
}
