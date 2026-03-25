//
//  UserPreferencesView.swift
//  PlayerPath
//
//  Settings view for user preferences
//

import SwiftUI
import SwiftData
import UIKit

struct UserPreferencesView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = UserPreferencesViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if let prefs = viewModel.preferences {
                    Form {
                        videoRecordingSection(preferences: prefs)
                        uiPreferencesSection(preferences: prefs)
                        cloudSyncSection(preferences: prefs)
                        privacyAnalyticsSection(preferences: prefs)
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

    private func videoRecordingSection(preferences: UserPreferences) -> some View {
        Section {
            Picker("Video Quality", selection: Binding<VideoQuality>(
                get: { viewModel.preferences?.defaultVideoQuality ?? VideoQuality.medium },
                set: { newQuality in
                    viewModel.update(\.defaultVideoQuality, to: newQuality)
                    // Sync to the actual recording settings singleton so the camera uses it
                    let recordingQuality: RecordingQuality
                    switch newQuality {
                    case .low:    recordingQuality = .medium720p
                    case .medium: recordingQuality = .high1080p
                    case .high:   recordingQuality = .ultra4K
                    }
                    VideoRecordingSettings.shared.quality = recordingQuality
                }
            )) {
                ForEach(VideoQuality.allCases, id: \.self) { quality in
                    Text(quality.displayName).tag(quality)
                }
            }

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

            Toggle("Haptic Feedback", isOn: Binding(
                get: { viewModel.preferences?.enableHapticFeedback ?? true },
                set: {
                    viewModel.update(\.enableHapticFeedback, to: $0)
                    UserDefaults.standard.set($0, forKey: "hapticFeedbackEnabled")
                }
            ))
        } header: {
            Text("Video Recording")
        } footer: {
            if let mode = viewModel.preferences?.autoUploadMode {
                Text(mode.description)
            }
        }
    }

    private func uiPreferencesSection(preferences: UserPreferences) -> some View {
        Section {
            Picker("App Theme", selection: Binding<AppTheme>(
                get: { viewModel.preferences?.preferredTheme ?? AppTheme.system },
                set: {
                    viewModel.update(\.preferredTheme, to: $0)
                    UserDefaults.standard.set($0.rawValue, forKey: "appTheme")
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

    private func cloudSyncSection(preferences: UserPreferences) -> some View {
        Section {
            Toggle("Sync Highlights Only", isOn: Binding(
                get: { viewModel.preferences?.syncHighlightsOnly ?? false },
                set: { viewModel.update(\.syncHighlightsOnly, to: $0) }
            ))

            HStack {
                Text("Max File Size")
                Spacer()
                Text("\(preferences.maxVideoFileSize) MB")
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

    private func privacyAnalyticsSection(preferences: UserPreferences) -> some View {
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
