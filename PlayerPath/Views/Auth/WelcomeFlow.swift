//
//  WelcomeFlow.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI

struct WelcomeFlow: View {
    private enum AuthSheet: Identifiable {
        case signIn
        case signUp
        var id: String { self == .signIn ? "signIn" : "signUp" }
    }

    @State private var activeSheet: AuthSheet? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                Spacer()

                // App Logo and Branding
                VStack(spacing: 24) {
                    ZStack {
                        // Glow effect behind icon
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [.red.opacity(0.3), .clear],
                                    center: .center,
                                    startRadius: 20,
                                    endRadius: 80
                                )
                            )
                            .frame(width: 160, height: 160)
                            .blur(radius: 20)

                        Image(systemName: "baseball.fill")
                            .font(.system(size: 100, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.red, .red.opacity(0.7), .white],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .symbolRenderingMode(.hierarchical)
                            .shadow(color: .red.opacity(0.4), radius: 15, x: 0, y: 8)
                    }

                    VStack(spacing: 12) {
                        Text("PlayerPath")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .accessibilityAddTraits(.isHeader)

                        Text("Your Baseball Journey Starts Here")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }

                // Feature highlights
                VStack(alignment: .leading, spacing: 12) {
                    Text("Track Your Performance")
                        .font(.headline)
                        .fontWeight(.bold)
                        .padding(.bottom, 4)
                        .accessibilityAddTraits(.isHeader)

                    FeatureHighlight(
                        icon: "video.circle.fill",
                        title: "Record & Analyze",
                        description: "Capture practice sessions and games with smart analysis",
                        color: .red
                    )

                    FeatureHighlight(
                        icon: "chart.line.uptrend.xyaxis.circle.fill",
                        title: "Track Statistics",
                        description: "Monitor batting averages and performance metrics",
                        color: .blue
                    )

                    FeatureHighlight(
                        icon: "arrow.triangle.2.circlepath.circle.fill",
                        title: "Sync Everywhere",
                        description: "Your data syncs securely across all devices",
                        color: .green
                    )
                }
                .padding(.horizontal)

                Spacer()

                // Action buttons
                VStack(spacing: 16) {
                    Button(action: { Haptics.medium(); activeSheet = .signUp }) {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.badge.plus")
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
                    .accessibilityLabel("Sign up to get started")
                    .accessibilityHint("Creates a new account and begins onboarding")
                    .accessibilityIdentifier("welcome_get_started")
                    .accessibilitySortPriority(1)

                    Button(action: { Haptics.light(); activeSheet = .signIn }) {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.title3)
                            Text("Sign In")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(.ultraThinMaterial)
                        .foregroundColor(.blue)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(
                                    LinearGradient(
                                        colors: [.blue, .blue.opacity(0.6)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2.5
                                )
                        )
                        .cornerRadius(16)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Sign in to existing account")
                    .accessibilityHint("Sign in with your existing credentials")
                    .accessibilityIdentifier("welcome_sign_in")
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding()
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .signIn:
                ComprehensiveSignInView(isSignUpMode: false)
            case .signUp:
                ComprehensiveSignInView(isSignUpMode: true)
            }
        }
    }
}
