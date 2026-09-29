//
//  UserPreferencesView.swift
//  PlayerPath
//
//  Settings view for user preferences
//

import SwiftUI
import SwiftData
import TipKit

struct UserPreferencesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.ppAccent) private var ppAccent
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @State private var viewModel = UserPreferencesViewModel()
    @State private var showingResetTipsConfirm = false

    // Haptics.swift reads this UserDefaults key directly, so the view writes to
    // it directly too — no SwiftData mirroring.
    @AppStorage("hapticFeedbackEnabled") private var hapticFeedbackEnabled: Bool = true

    private var isCoach: Bool { authManager.userRole == .coach }

    var body: some View {
        Group {
            if viewModel.preferences != nil {
                Form {
                    if !isCoach {
                        videoRecordingSection()
                        uploadSettingsLinkSection()
                    } else {
                        generalSection()
                    }
                    uiPreferencesSection()
                    privacyAnalyticsSection()
                }
            } else {
                ProgressView("Loading preferences...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.surface)
        .tint(ppAccent)
        .navigationTitle("App Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.attach(modelContext: modelContext)
            await viewModel.load()
        }
    }

    // MARK: - View Sections

    private func videoRecordingSection() -> some View {
        Section {
            Toggle("Save to Photos Library", isOn: Binding(
                get: { viewModel.preferences?.saveToPhotosLibrary ?? false },
                set: { viewModel.update(\.saveToPhotosLibrary, to: $0) }
            ))

            Toggle("Haptic Feedback", isOn: $hapticFeedbackEnabled)
        } header: {
            Text("General")
        }
    }

    /// Upload settings (auto-upload, cellular, highlights-only, file-size cap,
    /// auto-delete) live only in VideoRecordingSettingsView — one home, one
    /// save model. This row points there.
    private func uploadSettingsLinkSection() -> some View {
        Section {
            NavigationLink {
                VideoRecordingSettingsView()
            } label: {
                Label("Upload & Recording", systemImage: "icloud.and.arrow.up")
            }
        } footer: {
            Text("Auto-upload, cellular, and file-size settings live in Video Recording.")
        }
    }

    private func generalSection() -> some View {
        Section {
            Toggle("Haptic Feedback", isOn: $hapticFeedbackEnabled)
        } header: {
            Text("General")
        }
    }

    private func uiPreferencesSection() -> some View {
        Section {
            Toggle("Show Onboarding Tips", isOn: Binding(
                get: { viewModel.preferences?.showOnboardingTips ?? false },
                set: { viewModel.update(\.showOnboardingTips, to: $0) }
            ))

            Button("Reset Onboarding Tips") {
                showingResetTipsConfirm = true
            }
        } header: {
            Text("Interface")
        }
        .confirmationDialog(
            "Reset onboarding tips?",
            isPresented: $showingResetTipsConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                do {
                    try Tips.resetDatastore()
                } catch {
                    ErrorHandlerService.shared.handle(error, context: "Tips.resetDatastore", showAlert: false)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Hints you've already dismissed will show again the next time you visit each tab.")
        }
    }

    private func privacyAnalyticsSection() -> some View {
        Section {
            Toggle("Enable Analytics", isOn: Binding(
                get: { viewModel.preferences?.enableAnalytics ?? false },
                set: {
                    viewModel.update(\.enableAnalytics, to: $0)
                    AnalyticsService.shared.setCollection(enabled: $0)
                }
            ))
        } header: {
            Text("Privacy & Analytics")
        } footer: {
            Text("Help improve PlayerPath by sharing anonymous usage data.")
        }
    }

}
