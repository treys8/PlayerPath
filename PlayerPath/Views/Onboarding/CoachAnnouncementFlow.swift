//
//  CoachAnnouncementFlow.swift
//  PlayerPath
//
//  Full-screen walkthrough introducing coach features to existing athletes.
//  Shown once on first launch after coach features are enabled.
//

import SwiftUI

struct CoachAnnouncementFlow: View {
    let athlete: Athlete
    let onDismiss: () -> Void

    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @State private var currentPage = 0
    @State private var showingInviteSheet = false
    private let totalPages = 3

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $currentPage) {
                AnnouncementIntroPage(
                    onNext: { withAnimation { currentPage = 1 } }
                )
                .tag(0)

                AnnouncementFeaturesPage(
                    onNext: { withAnimation { currentPage = 2 } }
                )
                .tag(1)

                AnnouncementInvitePage(
                    onInvite: handleInviteTap,
                    onSkip: dismissFlow
                )
                .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            // Page indicator
            HStack(spacing: 8) {
                ForEach(0..<totalPages, id: \.self) { index in
                    Capsule()
                        .fill(index == currentPage ? Color.white : Color.white.opacity(0.3))
                        .frame(width: index == currentPage ? 24 : 8, height: 8)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                }
            }
            .padding(.bottom, 36)
        }
        .sheet(isPresented: $showingInviteSheet, onDismiss: dismissFlow) {
            InviteCoachSheet(athlete: athlete)
        }
    }

    private func handleInviteTap() {
        Haptics.medium()
        if authManager.hasCoachingAccess {
            showingInviteSheet = true
        } else {
            // Dismiss announcement, then show subscription paywall from MainTabView
            OnboardingManager.shared.markCoachAnnouncementSeen()
            onDismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NotificationCenter.default.post(name: .showSubscriptionPaywall, object: nil)
            }
        }
    }

    private func dismissFlow() {
        OnboardingManager.shared.markCoachAnnouncementSeen()
        Haptics.light()
        onDismiss()
    }
}

// MARK: - Page 1: Intro

private struct AnnouncementIntroPage: View {
    let onNext: () -> Void
    @State private var appeared = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.08, blue: 0.20),
                    Color(red: 0.06, green: 0.06, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

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

                        Image(systemName: "person.2.fill")
                            .font(.system(size: 54))
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

                // Title
                VStack(spacing: 12) {
                    Text("Coaches Are Now\non PlayerPath")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text("Your hitting or pitching instructor can now\nbe part of your development — right here\nin the app you already use.")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .offset(y: appeared ? 0 : 20)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: appeared)
                .padding(.horizontal, 32)

                Spacer()

                // CTA
                Button(action: onNext) {
                    HStack(spacing: 10) {
                        Text("See What Your Coach Can Do")
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
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: appeared)
            }
        }
        .onAppear { appeared = true }
    }
}

// MARK: - Page 2: Features

private struct AnnouncementFeaturesPage: View {
    let onNext: () -> Void
    @State private var appeared = false

    private let features: [(icon: String, color: Color, title: String, detail: String)] = [
        ("video.badge.checkmark", .brandNavy, "Review Your Game Film", "Your coach watches your at-bats and practice clips right in the app."),
        ("video.fill",            .purple,    "Capture Lesson Video",  "Your coach records clips during lessons that link back to your profile."),
        ("chart.line.uptrend.xyaxis", .orange, "Track Your Progress", "See how what you work on in lessons carries over to your games."),
        ("folder.fill.badge.person.crop", .brandNavy, "Shared Folders", "Keep everything organized — game film and lesson clips in one place."),
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.06, blue: 0.18),
                    Color(red: 0.06, green: 0.08, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 60)

                // Header
                VStack(spacing: 8) {
                    Text("What Your Coach Can Do")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)

                    Text("Everything happens inside PlayerPath.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.55))
                }
                .offset(y: appeared ? 0 : 16)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.05), value: appeared)

                Spacer().frame(height: 36)

                // Feature list
                VStack(spacing: 0) {
                    ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                        HStack(alignment: .top, spacing: 16) {
                            VStack(spacing: 0) {
                                ZStack {
                                    Circle()
                                        .fill(feature.color.opacity(0.18))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: feature.icon)
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(feature.color)
                                }
                                if index < features.count - 1 {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.12))
                                        .frame(width: 1.5, height: 28)
                                }
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(feature.title)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                Text(feature.detail)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.55))
                                    .lineSpacing(2)
                                if index < features.count - 1 {
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

                // CTA
                Button(action: onNext) {
                    HStack(spacing: 10) {
                        Text("How It Works")
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
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.5), value: appeared)
            }
        }
        .onAppear { appeared = true }
    }
}

// MARK: - Page 3: Invite

private struct AnnouncementInvitePage: View {
    let onInvite: () -> Void
    let onSkip: () -> Void
    @State private var appeared = false

    private let steps: [(number: String, text: String)] = [
        ("1", "You send an invite with their email"),
        ("2", "They download PlayerPath and sign up as a coach"),
        ("3", "Your videos appear in their dashboard"),
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.12, blue: 0.08),
                    Color(red: 0.04, green: 0.07, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Icon
                ZStack {
                    Circle()
                        .fill(Color.brandNavy.opacity(0.15))
                        .frame(width: 140, height: 140)
                        .blur(radius: 25)

                    ZStack {
                        Circle()
                            .fill(Color.brandNavy.opacity(0.2))
                            .frame(width: 100, height: 100)
                            .overlay(
                                Circle()
                                    .stroke(Color.brandNavy.opacity(0.4), lineWidth: 1)
                            )

                        Image(systemName: "paperplane.fill")
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

                Spacer().frame(height: 28)

                // Title
                VStack(spacing: 10) {
                    Text("Invite Your Coach\nto PlayerPath")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text("It only takes a minute to get connected.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.55))
                }
                .offset(y: appeared ? 0 : 16)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.15), value: appeared)

                Spacer().frame(height: 32)

                // Steps
                VStack(spacing: 12) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(spacing: 14) {
                            Text(step.number)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.brandNavy)
                                .frame(width: 32, height: 32)
                                .background(Color.brandNavy.opacity(0.15))
                                .clipShape(Circle())

                            Text(step.text)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.85))

                            Spacer()
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
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

                Spacer().frame(height: 20)

                // Info callout
                HStack(spacing: 12) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)
                        .font(.subheadline)
                    Text("Coach sharing requires a Pro subscription. You can upgrade anytime from Settings.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.65))
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

                Spacer()

                // Primary CTA
                Button(action: onInvite) {
                    HStack(spacing: 10) {
                        Image(systemName: "paperplane.fill")
                            .font(.headline)
                        Text("Invite My Coach")
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
                .offset(y: appeared ? 0 : 16)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.55), value: appeared)

                // Secondary dismiss
                Button(action: onSkip) {
                    Text("I'll Do This Later")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
                .padding(.bottom, 80)
                .offset(y: appeared ? 0 : 16)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.6), value: appeared)
            }
        }
        .onAppear { appeared = true }
    }
}
