//
//  CoachOnboardingFlow.swift
//  PlayerPath
//
//  Coach-specific onboarding — three-page paged flow explaining the
//  invitation-based workflow that is unique to coaches.
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct CoachOnboardingFlow: View {
    let modelContext: ModelContext
    @ObservedObject var authManager: ComprehensiveAuthManager
    let user: User

    @State private var currentPage = 0
    @State private var isCompleting = false
    @State private var errorMessage: String?
    @State private var showingError = false
    private let totalPages = 3

    var body: some View {
        ZStack(alignment: .bottom) {
            // Page content
            TabView(selection: $currentPage) {
                CoachWelcomePage(
                    coachEmail: authManager.userEmail ?? user.email,
                    onNext: { withAnimation { currentPage = 1 } }
                )
                .tag(0)

                CoachHowItWorksPage(
                    onNext: { withAnimation { currentPage = 2 } }
                )
                .tag(1)

                CoachReadyPage(
                    onComplete: completeCoachOnboarding
                )
                .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            // Custom page indicator
            HStack(spacing: 8) {
                ForEach(0..<totalPages, id: \.self) { index in
                    Capsule()
                        .fill(index == currentPage ? Color.brandNavy : Color.brandNavy.opacity(0.3))
                        .frame(width: index == currentPage ? 24 : 8, height: 8)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                }
            }
            .padding(.bottom, 36)
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert("Setup Failed", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func completeCoachOnboarding() {
        guard !isCompleting else { return }
        isCompleting = true

        Task {
            let progress = OnboardingProgress(firebaseAuthUid: authManager.currentFirebaseUser?.uid ?? "")
            progress.markCompleted()
            modelContext.insert(progress)
            do {
                try await withRetry(delay: .seconds(1)) {
                    try modelContext.save()
                }
                authManager.resetNewUserFlag()
                authManager.markOnboardingComplete()
                Haptics.medium()
            } catch {
                modelContext.rollback()
                ErrorHandlerService.shared.handle(error, context: "CoachOnboarding.saveProgress", showAlert: false)
                errorMessage = "Could not complete setup. Please try again."
                showingError = true
                isCompleting = false
            }
        }
    }
}

// MARK: - Page 1: Welcome

private struct CoachWelcomePage: View {
    let coachEmail: String
    let onNext: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
                Spacer()

                // Icon
                ZStack {
                    Circle()
                        .fill(Color.brandNavy.opacity(0.15))
                        .frame(width: 180, height: 180)
                        .blur(radius: 30)

                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.brandNavy.opacity(0.25), Color.brandNavy.opacity(0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 130, height: 130)
                            .overlay(
                                Circle()
                                    .stroke(Color.brandNavy.opacity(0.4), lineWidth: 1)
                            )

                        Image(systemName: "megaphone.fill")
                            .font(.system(size: 58))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.brandNavy, .brandNavy.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1), value: appeared)

                Spacer().frame(height: 36)

                // Title group
                VStack(spacing: 10) {
                    Text("Welcome, Coach")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)

                    Text("PlayerPath gives you everything you need\nto guide your athletes forward.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .offset(y: appeared ? 0 : 20)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: appeared)
                .padding(.horizontal, 32)

                Spacer().frame(height: 48)

                // Role card
                HStack(spacing: 14) {
                    Image(systemName: "person.fill.checkmark")
                        .font(.title3)
                        .foregroundColor(.brandNavy)
                        .frame(width: 40, height: 40)
                        .background(Color.brandNavy.opacity(0.15))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signed in as Coach")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        Text(coachEmail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer()
                }
                .padding(16)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(.separator), lineWidth: 1)
                )
                .padding(.horizontal, 24)
                .offset(y: appeared ? 0 : 20)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: appeared)

                Spacer()

                // CTA
                Button(action: onNext) {
                    HStack(spacing: 10) {
                        Text("Get Started")
                            .font(.headline)
                            .fontWeight(.bold)
                        Image(systemName: "arrow.right")
                            .font(.headline)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            colors: [.brandNavy, Color(red: 0.2, green: 0.85, blue: 0.55)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .brandNavy.opacity(0.5), radius: 16, x: 0, y: 8)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 80)
                .offset(y: appeared ? 0 : 20)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.4), value: appeared)
        }
        .onAppear { appeared = true }
    }
}

// MARK: - Page 2: How It Works

private struct CoachHowItWorksPage: View {
    let onNext: () -> Void

    @State private var appeared = false

    private let steps: [(icon: String, color: Color, title: String, detail: String)] = [
        ("envelope.fill",         .brandNavy,   "Athlete Sends an Invite",   "An athlete adds your email address to share their folder with you."),
        ("checkmark.seal.fill",   .brandNavy,  "You Accept the Invitation", "Open your Dashboard and tap the invitation to accept. You're in."),
        ("video.fill",            .purple, "Review Their Videos",        "Browse game and practice clips organized by the athlete."),
        ("bubble.left.fill",      .orange, "Leave Coaching Feedback",    "Annotate videos with timestamps and written notes athletes can act on."),
    ]

    var body: some View {
        VStack(spacing: 0) {
                Spacer().frame(height: 60)

                // Header
                VStack(spacing: 8) {
                    Text("How It Works")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.primary)

                    Text("Athletes invite you — you coach.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .offset(y: appeared ? 0 : 16)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.05), value: appeared)

                Spacer().frame(height: 36)

                // Steps
                VStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 16) {
                            // Icon + connector line
                            VStack(spacing: 0) {
                                ZStack {
                                    Circle()
                                        .fill(step.color.opacity(0.18))
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
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                Text(step.detail)
                                    .font(.caption)
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
                            .delay(0.15 + Double(index) * 0.08),
                            value: appeared
                        )
                    }
                }

                Spacer()

                // Info callout
                HStack(spacing: 12) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)
                        .font(.subheadline)
                    Text("Athletes can invite you, or you can invite athletes directly from your Dashboard. All invitations appear under My Athletes.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineSpacing(2)
                }
                .padding(14)
                .background(Color.yellow.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.yellow.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal, 24)
                .offset(y: appeared ? 0 : 16)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.5), value: appeared)

                Spacer().frame(height: 20)

                // CTA
                Button(action: onNext) {
                    HStack(spacing: 10) {
                        Text("Continue")
                            .font(.headline)
                            .fontWeight(.bold)
                        Image(systemName: "arrow.right")
                            .font(.headline)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            colors: [.brandNavy, Color(red: 0.2, green: 0.85, blue: 0.55)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .brandNavy.opacity(0.5), radius: 16, x: 0, y: 8)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 80)
                .offset(y: appeared ? 0 : 16)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.55), value: appeared)
        }
        .onAppear { appeared = true }
    }
}

// MARK: - Page 3: Ready

private struct CoachReadyPage: View {
    let onComplete: () -> Void

    @State private var appeared = false

    private let checklist: [(icon: String, text: String)] = [
        ("tray.and.arrow.down.fill", "Check your Dashboard for athlete invitations"),
        ("video.badge.checkmark",    "Watch and annotate shared video clips"),
        ("bubble.left.and.text.bubble.right.fill", "Leave timestamped notes athletes can act on"),
        ("bell.badge.fill",          "Get notified when athletes upload new footage"),
    ]

    var body: some View {
        VStack(spacing: 0) {
                Spacer()

                // Badge + Title
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(Color.brandNavy.opacity(0.15))
                            .frame(width: 120, height: 120)
                            .blur(radius: 20)

                        ZStack {
                            Circle()
                                .fill(Color.brandNavy.opacity(0.2))
                                .frame(width: 90, height: 90)
                                .overlay(
                                    Circle()
                                        .stroke(Color.brandNavy.opacity(0.4), lineWidth: 1)
                                )

                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.brandNavy, .brandNavy.opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                    .scaleEffect(appeared ? 1 : 0.5)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.65).delay(0.05), value: appeared)

                    VStack(spacing: 8) {
                        Text("You're All Set")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.primary)

                        Text("Here's what to do when you\nopen your Dashboard:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }
                    .offset(y: appeared ? 0 : 16)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.15), value: appeared)
                }

                Spacer().frame(height: 36)

                // Checklist
                VStack(spacing: 12) {
                    ForEach(Array(checklist.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 14) {
                            Image(systemName: item.icon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.brandNavy)
                                .frame(width: 32, height: 32)
                                .background(Color.brandNavy.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            Text(item.text)
                                .font(.subheadline)
                                .foregroundColor(.primary)

                            Spacer()
                        }
                        .padding(14)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.separator), lineWidth: 1)
                        )
                        .offset(y: appeared ? 0 : 20)
                        .opacity(appeared ? 1 : 0)
                        .animation(
                            .spring(response: 0.5, dampingFraction: 0.8)
                            .delay(0.25 + Double(index) * 0.07),
                            value: appeared
                        )
                    }
                }
                .padding(.horizontal, 24)

                Spacer()

                // CTA
                Button(action: onComplete) {
                    HStack(spacing: 10) {
                        Image(systemName: "baseball.diamond.bases")
                            .font(.headline)
                        Text("Go to Dashboard")
                            .font(.headline)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            colors: [.brandNavy, Color(red: 0.2, green: 0.85, blue: 0.55)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .brandNavy.opacity(0.5), radius: 16, x: 0, y: 8)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 80)
                .offset(y: appeared ? 0 : 16)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.55), value: appeared)
        }
        .onAppear { appeared = true }
    }
}
