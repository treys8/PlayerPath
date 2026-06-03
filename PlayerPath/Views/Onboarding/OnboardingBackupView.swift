//
//  OnboardingBackupView.swift
//  PlayerPath
//
//  Onboarding step for video backup preferences
//

import SwiftUI
import SwiftData
import OSLog

struct OnboardingBackupView: View {
    let athlete: Athlete
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authManager: ComprehensiveAuthManager

    @State private var selectedMode: AutoUploadMode = .wifiOnly
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingError = false

    /// Accent resolved from the athlete's pinned sport (golf → fairway green).
    private var accent: Color { Theme.accent(for: athlete.sport) }
    private var accentLight: Color { Theme.accentLight(for: athlete.sport) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    OnboardingStepIndicator(currentStep: 2, totalSteps: 3)
                        .padding(.top, 8)

                    // Header with icon
                    VStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [accent.opacity(0.3), .clear],
                                        center: .center,
                                        startRadius: 15,
                                        endRadius: 60
                                    )
                                )
                                .frame(width: 120, height: 120)
                                .blur(radius: 15)

                            Image(systemName: "icloud.and.arrow.up")
                                .font(.system(size: 60, weight: .medium))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [accent, accentLight],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .symbolRenderingMode(.hierarchical)
                                .shadow(color: accent.opacity(0.4), radius: 15, x: 0, y: 8)
                        }

                        VStack(spacing: 12) {
                            Text("Back Up Your Videos")
                                .font(.displayLarge)
                                .foregroundColor(Theme.textPrimary)
                                .multilineTextAlignment(.center)

                            Text("Keep your videos safe in the cloud and access them from anywhere")
                                .font(.bodyLarge)
                                .foregroundColor(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }

                    // Backup options
                    VStack(spacing: 16) {
                        ForEach(AutoUploadMode.allCases, id: \.self) { mode in
                            BackupOptionCard(
                                mode: mode,
                                isSelected: selectedMode == mode,
                                onSelect: {
                                    withAnimation(.spring(response: 0.3)) {
                                        selectedMode = mode
                                    }
                                    Haptics.light()
                                }
                            )
                        }
                    }
                    .padding(.horizontal)

                    // Continue button
                    Button(action: { Haptics.medium(); saveAndContinue() }) {
                        HStack(spacing: 12) {
                            if isSaving {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                            }
                            Text(isSaving ? "Saving..." : "Continue")
                                .font(.headingLarge)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(
                            LinearGradient(
                                colors: [accent, accent.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(16)
                        .shadow(color: accent.opacity(0.4), radius: 12, x: 0, y: 6)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                    .padding(.horizontal)

                    Text("You can change this anytime in Settings")
                        .font(.bodySmall)
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 20)
                }
                .padding(.horizontal)
                .padding(.top, 16)
            }
            .background(Theme.surface, ignoresSafeAreaEdges: .all)
            .ppAccent(for: athlete.sport)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .frame(height: 0)
                    .ignoresSafeArea(edges: .top)
            }
            .alert("Save Failed", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func saveAndContinue() {
        guard !isSaving else { return }
        isSaving = true

        // Get or create user preferences
        let prefs = UserPreferences.shared(in: modelContext)
        prefs.autoUploadMode = selectedMode

        let saved = ErrorHandlerService.shared.saveContext(modelContext, caller: "OnboardingBackup.save")
        guard saved else {
            isSaving = false
            errorMessage = "Could not save backup preference. Please try again."
            showingError = true
            return
        }

        onboardingLog.info("Backup preference saved: \(selectedMode.rawValue)")

        // Now reset the new user flag - onboarding is complete
        authManager.resetNewUserFlag()

        onboardingLog.info("Onboarding complete — new user flag reset")

        Haptics.success()
        isSaving = false
    }
}

// MARK: - Backup Option Card

private struct BackupOptionCard: View {
    let mode: AutoUploadMode
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.ppAccent) private var ppAccent

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(iconBackgroundColor)
                        .frame(width: 50, height: 50)

                    Image(systemName: mode.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(iconColor)
                }

                // Text content
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(mode.displayName)
                            .font(.headingMedium)
                            .foregroundColor(Theme.textPrimary)

                        if mode == .wifiOnly {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundColor(ppAccent)
                        }
                    }

                    Text(modeDescription)
                        .font(.bodyMedium)
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? ppAccent : Theme.pillBorder, lineWidth: 2)
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Circle()
                            .fill(ppAccent)
                            .frame(width: 16, height: 16)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? ppAccent.opacity(0.08) : Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? ppAccent : Theme.divider, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var iconBackgroundColor: Color {
        switch mode {
        case .off: return Theme.textTertiary.opacity(0.15)
        case .wifiOnly: return ppAccent.opacity(0.15)
        case .always: return ppAccent.opacity(0.15)
        }
    }

    private var iconColor: Color {
        switch mode {
        case .off: return Theme.textTertiary
        case .wifiOnly: return ppAccent
        case .always: return ppAccent
        }
    }

    private var modeDescription: String {
        switch mode {
        case .off:
            return "Upload manually when you choose"
        case .wifiOnly:
            return "Auto-backup over Wi-Fi"
        case .always:
            return "Backup over Wi-Fi or cellular"
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    guard let container = try? ModelContainer(for: User.self, Athlete.self, Season.self, UserPreferences.self, configurations: config) else {
        return Text("Failed to create preview container")
    }

    let user = User(username: "testuser", email: "test@example.com")
    let athlete = Athlete(name: "Test Athlete")
    athlete.user = user

    container.mainContext.insert(user)
    container.mainContext.insert(athlete)

    return OnboardingBackupView(athlete: athlete)
        .modelContainer(container)
        .environmentObject(ComprehensiveAuthManager())
}
