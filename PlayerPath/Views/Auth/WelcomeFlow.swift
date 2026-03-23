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
    @State private var showingTerms = false
    @State private var showingPrivacyPolicy = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // App Logo and Branding
                    VStack(spacing: 14) {
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
                                .frame(width: 110, height: 110)
                                .blur(radius: 20)

                            Image(systemName: "baseball.fill")
                                .font(.system(size: 70, weight: .medium))
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

                        VStack(spacing: 8) {
                            Text("PlayerPath")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .fontDesign(.rounded)
                                .foregroundColor(.primary)
                                .accessibilityAddTraits(.isHeader)

                            Text("Your game film. Your stats.\nAutomatically.")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .fontDesign(.rounded)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    // Feature highlights
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Tag each play as it happens. Stats build themselves.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        FeatureHighlight(
                            icon: "video.circle.fill",
                            title: "Record every at-bat",
                            description: "Clip by clip, game by game",
                            color: .red
                        )

                        FeatureHighlight(
                            icon: "chart.line.uptrend.xyaxis.circle.fill",
                            title: "Auto-generated stats",
                            description: "AVG, OBP, SLG and more",
                            color: .brandNavy
                        )

                        FeatureHighlight(
                            icon: "person.2.circle.fill",
                            title: "Share with coaches",
                            description: "Real-time window into your season",
                            color: .brandNavy
                        )
                    }
                    .padding(.horizontal)

                    // Action buttons
                    VStack(spacing: 12) {
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
                                    colors: [Color.brandNavy, Color.brandNavy.opacity(0.85)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(16)
                            .shadow(color: Color.brandNavy.opacity(0.4), radius: 12, x: 0, y: 6)
                        }
                        .buttonStyle(ScaleButtonStyle())
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
                            .foregroundColor(.brandNavy)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.brandNavy, Color.brandNavy.opacity(0.6)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 2.5
                                    )
                            )
                            .cornerRadius(16)
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .accessibilityLabel("Sign in to existing account")
                        .accessibilityHint("Sign in with your existing credentials")
                        .accessibilityIdentifier("welcome_sign_in")
                    }
                    .padding(.horizontal)

                    HStack(spacing: 16) {
                        Button("Terms of Service") { showingTerms = true }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Privacy Policy") { showingPrivacyPolicy = true }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 8)
                }
                .padding(.top, 10)
            }
            .padding()
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showingTerms) {
            TermsOfServiceView()
        }
        .sheet(isPresented: $showingPrivacyPolicy) {
            PrivacyPolicyView()
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .signIn:
                ComprehensiveSignInView(isSignUpMode: false)
            case .signUp:
                ComprehensiveSignInView(isSignUpMode: true) {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(400))
                        activeSheet = .signIn
                    }
                }
            }
        }
    }
}
