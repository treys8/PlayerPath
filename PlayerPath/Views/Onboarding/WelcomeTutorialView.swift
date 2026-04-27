//
//  WelcomeTutorialView.swift
//  PlayerPath
//
//  Connected walkthrough that teaches new users (parents/grandparents)
//  the core Game Day workflow: Create Game -> Record -> Tag -> Stats.
//

import SwiftUI

struct WelcomeTutorialView: View {
    let athleteName: String
    let userEmail: String

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var onboardingManager = OnboardingManager.shared

    @State private var currentPage = 0
    private let totalPages = 6

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemGroupedBackground).ignoresSafeArea()

            TabView(selection: $currentPage) {
                ManagerPage(
                    athleteName: athleteName,
                    userEmail: userEmail,
                    onNext: { advancePage() }
                )
                .tag(0)

                PlayerReadyPage(
                    athleteName: athleteName,
                    onNext: { advancePage() }
                )
                .tag(1)

                GameDayPage(onNext: { advancePage() })
                    .tag(2)

                RecordAtBatPage(onNext: { advancePage() })
                    .tag(3)

                TagResultPage(onNext: { advancePage() })
                    .tag(4)

                BetweenGamesPage(onComplete: completeWalkthrough)
                    .tag(5)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Custom page indicator
            HStack(spacing: 8) {
                ForEach(0..<totalPages, id: \.self) { index in
                    Capsule()
                        .fill(index == currentPage ? Color.brandNavy : Color.brandNavy.opacity(0.2))
                        .frame(width: index == currentPage ? 24 : 8, height: 8)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                }
            }
            .padding(.bottom, 36)
        }
        .interactiveDismissDisabled(true)
        .onDisappear {
            if !onboardingManager.hasSeenWelcomeTutorial {
                onboardingManager.markWelcomeTutorialSeen()
            }
        }
    }

    private func advancePage() {
        Haptics.light()
        withAnimation { currentPage += 1 }
    }

    private func completeWalkthrough() {
        Haptics.medium()
        onboardingManager.markWelcomeTutorialSeen()
        dismiss()
    }
}

// MARK: - Shared Components

private struct WalkthroughCTA: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.headingLarge)
                Image(systemName: icon)
                    .font(.headingLarge)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                LinearGradient(
                    colors: [.brandNavy, .brandNavy.opacity(0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .brandNavy.opacity(0.3), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.bottom, 80)
    }
}

private struct WalkthroughIcon: View {
    let systemName: String
    let accentColor: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(accentColor.opacity(0.1))
                .frame(width: 160, height: 160)
                .blur(radius: 25)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accentColor.opacity(0.15), accentColor.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                    .overlay(
                        Circle()
                            .stroke(accentColor.opacity(0.25), lineWidth: 1)
                    )

                Image(systemName: systemName)
                    .font(.system(size: 52))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [accentColor, accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolRenderingMode(.hierarchical)
            }
        }
    }
}

// MARK: - Page 1: You're the Manager

private struct ManagerPage: View {
    let athleteName: String
    let userEmail: String
    let onNext: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            WalkthroughIcon(systemName: "person.fill.checkmark", accentColor: .brandNavy)
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1), value: appeared)

            Spacer().frame(height: 36)

            VStack(spacing: 10) {
                Text("You're the Manager")
                    .font(.custom("Fraunces72pt-Bold", size: 36, relativeTo: .largeTitle))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)

                Text("You hold this account. \(Text(athleteName).font(.custom("Inter18pt-SemiBold", size: 17))) is your player — you'll manage their games, videos, and stats.")
                    .font(.bodyLarge)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .offset(y: appeared ? 0 : 20)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: appeared)
            .padding(.horizontal, 32)

            Spacer().frame(height: 48)

            // Account card
            HStack(spacing: 14) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.headingLarge)
                    .foregroundColor(.brandNavy)
                    .frame(width: 40, height: 40)
                    .background(Color.brandNavy.opacity(0.1))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Your Account")
                        .font(.headingSmall)
                        .foregroundColor(.primary)
                    Text(userEmail)
                        .font(.bodySmall)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer()
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 24)
            .offset(y: appeared ? 0 : 20)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: appeared)

            Spacer()

            WalkthroughCTA(title: "Next", icon: "arrow.right", action: onNext)
                .offset(y: appeared ? 0 : 20)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.4), value: appeared)
        }
        .onAppear { appeared = true }
    }
}

// MARK: - Page 2: Your Player Is Ready

private struct PlayerReadyPage: View {
    let athleteName: String
    let onNext: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            WalkthroughIcon(systemName: "figure.baseball", accentColor: .orange)
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1), value: appeared)

            Spacer().frame(height: 24)

            VStack(spacing: 8) {
                Text("Your Player Is Ready")
                    .font(.custom("Fraunces72pt-Bold", size: 36, relativeTo: .largeTitle))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)

                Text("\(Text(athleteName).font(.custom("Inter18pt-SemiBold", size: 17)))'s profile is set up and ready to go.")
                    .font(.bodyLarge)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .offset(y: appeared ? 0 : 20)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: appeared)
            .padding(.horizontal, 32)

            Spacer().frame(height: 28)

            // Athlete card
            HStack(spacing: 14) {
                Image(systemName: "figure.baseball")
                    .font(.headingLarge)
                    .foregroundColor(.orange)
                    .frame(width: 40, height: 40)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(athleteName)
                        .font(.headingSmall)
                        .foregroundColor(.primary)
                    Text("Athlete Profile")
                        .font(.bodySmall)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 24)
            .offset(y: appeared ? 0 : 20)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: appeared)

            Spacer().frame(height: 14)

            // Hint
            HStack(spacing: 12) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.orange)
                    .font(.subheadline)
                Text("Have more than one kid? You can add more athletes anytime from Settings.")
                    .font(.bodySmall)
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
            }
            .padding(14)
            .background(Color.orange.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.orange.opacity(0.15), lineWidth: 1)
            )
            .padding(.horizontal, 24)
            .offset(y: appeared ? 0 : 16)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.4), value: appeared)

            Spacer()

            WalkthroughCTA(title: "Next", icon: "arrow.right", action: onNext)
                .offset(y: appeared ? 0 : 20)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.5), value: appeared)
        }
        .onAppear { appeared = true }
    }
}

// MARK: - Page 3: On Game Day

private struct GameDayPage: View {
    let onNext: () -> Void

    @State private var appeared = false

    private let steps: [(icon: String, color: Color, title: String, detail: String)] = [
        ("baseball.diamond.bases", .brandNavy, "Open the Games Tab", "This is home base for all your games."),
        ("plus.circle.fill",       .green,     "Create a Game",      "Add the opponent and date — takes 10 seconds."),
        ("play.circle.fill",       .orange,    "Tap Start Game",     "When the game begins, tap Start Game to begin tracking."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 40)

            WalkthroughIcon(systemName: "baseball.diamond.bases", accentColor: .brandNavy)
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1), value: appeared)

            Spacer().frame(height: 24)

            VStack(spacing: 10) {
                Text("On Game Day")
                    .font(.custom("Fraunces72pt-Bold", size: 36, relativeTo: .largeTitle))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)

                Text("Three steps to start tracking.")
                    .font(.bodyLarge)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .offset(y: appeared ? 0 : 20)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: appeared)
            .padding(.horizontal, 32)

            Spacer().frame(height: 32)

            // Timeline steps
            VStack(spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 0) {
                            ZStack {
                                Circle()
                                    .fill(step.color.opacity(0.12))
                                    .frame(width: 44, height: 44)
                                Image(systemName: step.icon)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(step.color)
                            }
                            if index < steps.count - 1 {
                                Rectangle()
                                    .fill(Color(.separator))
                                    .frame(width: 1.5, height: 28)
                            }
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.title)
                                .font(.headingSmall)
                                .foregroundColor(.primary)
                            Text(step.detail)
                                .font(.bodySmall)
                                .foregroundColor(.secondary)
                                .lineSpacing(2)
                            if index < steps.count - 1 {
                                Spacer().frame(height: 20)
                            }
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 28)
                    .offset(y: appeared ? 0 : 20)
                    .opacity(appeared ? 1 : 0)
                    .animation(
                        .spring(response: 0.5, dampingFraction: 0.8)
                        .delay(0.3 + Double(index) * 0.08),
                        value: appeared
                    )
                }
            }

            Spacer()

            WalkthroughCTA(title: "Next", icon: "arrow.right", action: onNext)
                .offset(y: appeared ? 0 : 16)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.55), value: appeared)
        }
        .onAppear { appeared = true }
    }
}

// MARK: - Page 4: Record Every At-Bat

private struct RecordAtBatPage: View {
    let onNext: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            WalkthroughIcon(systemName: "video.badge.plus", accentColor: .red)
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1), value: appeared)

            Spacer().frame(height: 36)

            VStack(spacing: 10) {
                Text("Record Every At-Bat")
                    .font(.custom("Fraunces72pt-Bold", size: 36, relativeTo: .largeTitle))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)

                Text("Tap \(Text("Record").font(.custom("Inter18pt-SemiBold", size: 17))) when your kid steps up to the plate. Hit \(Text("Stop").font(.custom("Inter18pt-SemiBold", size: 17))) when the play is over.")
                    .font(.bodyLarge)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .offset(y: appeared ? 0 : 20)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: appeared)
            .padding(.horizontal, 32)

            Spacer().frame(height: 48)

            // Key point
            HStack(spacing: 14) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title2)
                    .foregroundColor(.red)

                Text("Every clip you record becomes a play in their stats.")
                    .font(.labelLarge)
                    .foregroundColor(.primary)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 24)
            .offset(y: appeared ? 0 : 20)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: appeared)

            Spacer()

            WalkthroughCTA(title: "Next", icon: "arrow.right", action: onNext)
                .offset(y: appeared ? 0 : 20)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.4), value: appeared)
        }
        .onAppear { appeared = true }
    }
}

// MARK: - Page 5: Tag What Happened

private struct TagResultPage: View {
    let onNext: () -> Void

    @State private var appeared = false

    private let exampleTags: [(label: String, color: Color)] = [
        ("Single",     .green),
        ("Strikeout",  .red),
        ("Walk",       .blue),
        ("Double",     .orange),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            WalkthroughIcon(systemName: "tag.fill", accentColor: .green)
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1), value: appeared)

            Spacer().frame(height: 24)

            VStack(spacing: 8) {
                Text("Tag What Happened")
                    .font(.custom("Fraunces72pt-Bold", size: 36, relativeTo: .largeTitle))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)

                Text("After each clip, tap what happened. One tap — that's how the app tracks stats for you.")
                    .font(.bodyLarge)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .offset(y: appeared ? 0 : 20)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: appeared)
            .padding(.horizontal, 32)

            Spacer().frame(height: 28)

            // Example tags — 2x2 grid to fit all screen sizes
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    ForEach(Array(exampleTags.prefix(2).enumerated()), id: \.offset) { index, tag in
                        tagPill(tag, index: index)
                    }
                }
                HStack(spacing: 10) {
                    ForEach(Array(exampleTags.suffix(2).enumerated()), id: \.offset) { index, tag in
                        tagPill(tag, index: index + 2)
                    }
                }
            }
            .padding(.horizontal, 24)

            Spacer().frame(height: 20)

            // No scorebook callout
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.subheadline)
                Text("No scorebook needed — your tags build the stats automatically.")
                    .font(.bodySmall)
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
            }
            .padding(14)
            .background(Color.green.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.green.opacity(0.15), lineWidth: 1)
            )
            .padding(.horizontal, 24)
            .offset(y: appeared ? 0 : 16)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.5), value: appeared)

            Spacer()

            WalkthroughCTA(title: "Next", icon: "arrow.right", action: onNext)
                .offset(y: appeared ? 0 : 20)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.55), value: appeared)
        }
        .onAppear { appeared = true }
    }

    private func tagPill(_ tag: (label: String, color: Color), index: Int) -> some View {
        Text(tag.label)
            .font(.headingSmall)
            .foregroundColor(tag.color)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(tag.color.opacity(0.1))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(tag.color.opacity(0.2), lineWidth: 1)
            )
            .scaleEffect(appeared ? 1 : 0.8)
            .opacity(appeared ? 1 : 0)
            .animation(
                .spring(response: 0.5, dampingFraction: 0.7)
                .delay(0.3 + Double(index) * 0.06),
                value: appeared
            )
    }
}

// MARK: - Page 6: Between Games

private struct BetweenGamesPage: View {
    let onComplete: () -> Void

    @State private var appeared = false

    private let features: [(icon: String, color: Color, title: String, detail: String)] = [
        ("chart.bar.fill",    .brandNavy, "Check Their Stats",      "Batting average and more — all calculated from your tags."),
        ("video.fill",        .purple,    "Review Their Videos",    "Watch at-bats back and see their progress."),
        ("person.2.fill",     .orange,    "Share with Their Coach", "Send clips to a hitting or pitching instructor."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            WalkthroughIcon(systemName: "chart.bar.fill", accentColor: .brandNavy)
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1), value: appeared)

            Spacer().frame(height: 36)

            VStack(spacing: 10) {
                Text("Between Games")
                    .font(.custom("Fraunces72pt-Bold", size: 36, relativeTo: .largeTitle))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)

                Text("Here's what you can do when there's no game on.")
                    .font(.bodyLarge)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .offset(y: appeared ? 0 : 20)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: appeared)
            .padding(.horizontal, 32)

            Spacer().frame(height: 40)

            // Feature rows
            VStack(spacing: 16) {
                ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                    HStack(spacing: 14) {
                        Image(systemName: feature.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(feature.color)
                            .frame(width: 40, height: 40)
                            .background(feature.color.opacity(0.1))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.title)
                                .font(.headingSmall)
                                .foregroundColor(.primary)
                            Text(feature.detail)
                                .font(.bodySmall)
                                .foregroundColor(.secondary)
                                .lineSpacing(2)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 28)
                    .offset(y: appeared ? 0 : 20)
                    .opacity(appeared ? 1 : 0)
                    .animation(
                        .spring(response: 0.5, dampingFraction: 0.8)
                        .delay(0.3 + Double(index) * 0.08),
                        value: appeared
                    )
                }
            }

            Spacer()

            WalkthroughCTA(title: "Let's Go!", icon: "baseball.diamond.bases", action: onComplete)
                .offset(y: appeared ? 0 : 20)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.55), value: appeared)
        }
        .onAppear { appeared = true }
    }
}
