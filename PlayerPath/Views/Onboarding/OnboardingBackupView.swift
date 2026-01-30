//
//  OnboardingBackupView.swift
//  PlayerPath
//
//  Onboarding step for video backup preferences
//

import SwiftUI
import SwiftData

struct OnboardingBackupView: View {
    let athlete: Athlete
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authManager: ComprehensiveAuthManager

    @State private var selectedMode: AutoUploadMode = .wifiOnly
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 40) {
                    Spacer()
                        .frame(height: 20)

                    // Header with icon
                    VStack(spacing: 24) {
                        ZStack {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [.blue.opacity(0.3), .clear],
                                        center: .center,
                                        startRadius: 20,
                                        endRadius: 80
                                    )
                                )
                                .frame(width: 160, height: 160)
                                .blur(radius: 20)

                            Image(systemName: "icloud.and.arrow.up")
                                .font(.system(size: 80, weight: .medium))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .cyan],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .symbolRenderingMode(.hierarchical)
                                .shadow(color: .blue.opacity(0.4), radius: 15, x: 0, y: 8)
                        }

                        VStack(spacing: 16) {
                            Text("Back Up Your Videos")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)

                            Text("Keep your videos safe in the cloud and access them from anywhere")
                                .font(.title3)
                                .foregroundColor(.secondary)
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
                            }
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .fontWeight(.semibold)
                            Text("Continue")
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
                    .disabled(isSaving)
                    .padding(.horizontal)

                    Text("You can change this anytime in Settings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 40)
                }
                .padding()
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func saveAndContinue() {
        isSaving = true

        // Get or create user preferences
        let prefs = UserPreferences.shared(in: modelContext)
        prefs.autoUploadMode = selectedMode

        do {
            try modelContext.save()

            #if DEBUG
            print("🟢 Onboarding backup preference saved: \(selectedMode.rawValue)")
            #endif

            // Now reset the new user flag - onboarding is complete
            authManager.resetNewUserFlag()

            #if DEBUG
            print("🟢 Onboarding complete - new user flag reset")
            #endif

            Haptics.success()
            isSaving = false
        } catch {
            isSaving = false
            print("🔴 Failed to save backup preference: \(error)")
            // Still complete onboarding even if save fails
            authManager.resetNewUserFlag()
        }
    }
}

// MARK: - Backup Option Card

private struct BackupOptionCard: View {
    let mode: AutoUploadMode
    let isSelected: Bool
    let onSelect: () -> Void

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
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)

                        if mode == .wifiOnly {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.green)
                        }
                    }

                    Text(modeDescription)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 16, height: 16)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.blue.opacity(0.08) : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var iconBackgroundColor: Color {
        switch mode {
        case .off: return .gray.opacity(0.15)
        case .wifiOnly: return .blue.opacity(0.15)
        case .always: return .green.opacity(0.15)
        }
    }

    private var iconColor: Color {
        switch mode {
        case .off: return .gray
        case .wifiOnly: return .blue
        case .always: return .green
        }
    }

    private var modeDescription: String {
        switch mode {
        case .off:
            return "Upload videos manually when you choose"
        case .wifiOnly:
            return "Automatically back up videos when connected to Wi-Fi"
        case .always:
            return "Back up immediately using Wi-Fi or cellular data"
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
