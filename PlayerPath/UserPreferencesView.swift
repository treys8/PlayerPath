//
//  UserPreferencesView.swift
//  PlayerPath
//
//  Settings view for user preferences
//

import SwiftUI
import SwiftData

struct UserPreferencesView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @State private var viewModel = UserPreferencesViewModel()

    // Haptics.swift and ThemeManager read these UserDefaults keys directly, so
    // the view writes to them directly too — no SwiftData mirroring.
    @AppStorage("hapticFeedbackEnabled") private var hapticFeedbackEnabled: Bool = true
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue

    private var isCoach: Bool { authManager.userRole == .coach }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.preferences != nil {
                    Form {
                        if !isCoach {
                            videoRecordingSection()
                        } else {
                            generalSection()
                        }
                        uiPreferencesSection()
                        if !isCoach {
                            cloudSyncSection()
                        }
                        privacyAnalyticsSection()
                    }
                } else {
                    ProgressView("Loading preferences...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                viewModel.attach(modelContext: modelContext)
                await viewModel.load()
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if viewModel.hasUnsavedChanges {
                        Button("Save") {
                            Task {
                                do {
                                    try await viewModel.save()
                                } catch {
                                    ErrorHandlerService.shared.handle(error, context: "UserPreferences.save", showAlert: true)
                                }
                            }
                        }
                    }
                }
            }
            .onDisappear {
                // Auto-save on navigating away to prevent losing changes
                if viewModel.hasUnsavedChanges {
                    Task {
                        do { try await viewModel.save() }
                        catch { ErrorHandlerService.shared.handle(error, context: "UserPreferences.autoSave", showAlert: false) }
                    }
                }
            }
        }
    }

    // MARK: - View Sections

    private func videoRecordingSection() -> some View {
        Section {
            Picker("Auto-Upload Videos", selection: Binding<AutoUploadMode>(
                get: { viewModel.preferences?.autoUploadMode ?? .off },
                set: { viewModel.update(\.autoUploadMode, to: $0) }
            )) {
                ForEach(AutoUploadMode.allCases, id: \.self) { mode in
                    Label(mode.displayName, systemImage: mode.icon).tag(mode)
                }
            }

            Toggle("Save to Photos Library", isOn: Binding(
                get: { viewModel.preferences?.saveToPhotosLibrary ?? false },
                set: { viewModel.update(\.saveToPhotosLibrary, to: $0) }
            ))

            Toggle("Haptic Feedback", isOn: $hapticFeedbackEnabled)
        } header: {
            Text("Video Recording")
        } footer: {
            if let mode = viewModel.preferences?.autoUploadMode {
                Text(mode.description)
            }
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
            Picker("App Theme", selection: Binding<AppTheme>(
                get: { AppTheme(rawValue: appThemeRaw) ?? .system },
                set: {
                    appThemeRaw = $0.rawValue
                    ThemeManager.shared.reload()
                }
            )) {
                ForEach(AppTheme.allCases, id: \.self) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }

            Toggle("Show Onboarding Tips", isOn: Binding(
                get: { viewModel.preferences?.showOnboardingTips ?? false },
                set: { viewModel.update(\.showOnboardingTips, to: $0) }
            ))
        } header: {
            Text("Interface")
        }
    }

    private func cloudSyncSection() -> some View {
        Section {
            Toggle("Sync Highlights Only", isOn: Binding(
                get: { viewModel.preferences?.syncHighlightsOnly ?? false },
                set: { viewModel.update(\.syncHighlightsOnly, to: $0) }
            ))

            HStack {
                Text("Max File Size")
                Spacer()
                Text("\(viewModel.preferences?.maxVideoFileSize ?? 500) MB")
                    .foregroundColor(.secondary)
            }

            Slider(
                value: Binding<Double>(
                    get: { Double(viewModel.preferences?.maxVideoFileSize ?? 500) },
                    set: { viewModel.update(\.maxVideoFileSize, to: Int($0)) }
                ),
                in: 50...2000,
                step: 50
            )

            Toggle("Auto-delete After Upload", isOn: Binding(
                get: { viewModel.preferences?.autoDeleteAfterUpload ?? false },
                set: { viewModel.update(\.autoDeleteAfterUpload, to: $0) }
            ))
        } header: {
            Text("Cloud Storage")
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
