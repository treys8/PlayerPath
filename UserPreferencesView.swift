//
//  UserPreferencesView.swift
//  PlayerPath
//
//  Settings view for user preferences with CloudKit sync
//

import SwiftUI
import SwiftData

struct UserPreferencesView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = UserPreferencesViewModel()
    
    var body: some View {
        NavigationStack {
            Group {
                if let prefs = viewModel.preferences {
                    Form {
                        cloudKitStatusSection
                        videoRecordingSection(preferences: prefs)
                        uiPreferencesSection(preferences: prefs)
                        cloudSyncSection(preferences: prefs)
                        privacyAnalyticsSection(preferences: prefs)
                        notificationsSection(preferences: prefs)
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
                viewModel.startObservingRemoteChanges()
            }
            .alert(item: $viewModel.alert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: alert.recoverySuggestion != nil
                        ? Text("\(alert.message)\n\n\(alert.recoverySuggestion!)")
                        : Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if viewModel.hasUnsavedChanges {
                        Button("Save") {
                            Task { try? await viewModel.save() }
                        }
                    }
                    if viewModel.showsSyncButton {
                        Button {
                            Task { await viewModel.saveAndSync() }
                        } label: {
                            Image(systemName: "icloud.and.arrow.up")
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - View Sections
    
    private var cloudKitStatusSection: some View {
        Section {
            HStack {
                Image(systemName: viewModel.canSync ? "icloud" : "icloud.slash")
                    .foregroundColor(viewModel.canSync ? .green : .red)
                
                VStack(alignment: .leading) {
                    Text("iCloud Sync").font(.headline)
                    Text(viewModel.canSync ? "Available" : "Not Available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                switch viewModel.syncStatus {
                case .idle:
                    EmptyView()
                case .syncing:
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Syncing...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                case .success:
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Synced")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                case .failed(let error):
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Sync Failed")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .onTapGesture {
                        viewModel.alert = UserPreferencesViewModel.SyncAlert(
                            title: "Sync Error",
                            message: error.localizedDescription,
                            recoverySuggestion: error.recoverySuggestion
                        )
                    }
                }
            }
            
            if !viewModel.canSync {
                Text("Sign in to iCloud to sync your preferences across devices.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("Cloud Sync")
        }
    }
    
    private func videoRecordingSection(preferences: UserPreferences) -> some View {
        Section {
            Picker("Video Quality", selection: Binding<VideoQuality>(
                get: { viewModel.preferences?.defaultVideoQuality ?? VideoQuality.medium },
                set: { viewModel.update(\.defaultVideoQuality, to: $0) }
            )) {
                ForEach(VideoQuality.allCases, id: \.self) { quality in
                    Text(quality.rawValue).tag(quality)
                }
            }
            
            Toggle("Auto-upload to Cloud", isOn: Binding(
                get: { viewModel.preferences?.autoUploadToCloud ?? false },
                set: { viewModel.update(\.autoUploadToCloud, to: $0) }
            ))
            
            Toggle("Save to Photos Library", isOn: Binding(
                get: { viewModel.preferences?.saveToPhotosLibrary ?? false },
                set: { viewModel.update(\.saveToPhotosLibrary, to: $0) }
            ))
            
            Toggle("Haptic Feedback", isOn: Binding(
                get: { viewModel.preferences?.enableHapticFeedback ?? false },
                set: { viewModel.update(\.enableHapticFeedback, to: $0) }
            ))
        } header: {
            Text("Video Recording")
        }
    }
    
    private func uiPreferencesSection(preferences: UserPreferences) -> some View {
        Section {
            Picker("App Theme", selection: Binding<AppTheme>(
                get: { viewModel.preferences?.preferredTheme ?? AppTheme.system },
                set: { viewModel.update(\.preferredTheme, to: $0) }
            )) {
                ForEach(AppTheme.allCases, id: \.self) { theme in
                    Text(theme.rawValue).tag(theme)
                }
            }
            
            Toggle("Show Onboarding Tips", isOn: Binding(
                get: { viewModel.preferences?.showOnboardingTips ?? false },
                set: { viewModel.update(\.showOnboardingTips, to: $0) }
            ))
            
            Toggle("Debug Mode", isOn: Binding(
                get: { viewModel.preferences?.enableDebugMode ?? false },
                set: { viewModel.update(\.enableDebugMode, to: $0) }
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
                    get: { Double(viewModel.preferences?.maxVideoFileSize ?? 100) },
                    set: { viewModel.update(\.maxVideoFileSize, to: Int($0)) }
                ),
                in: 100...1000,
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
                set: { viewModel.update(\.enableAnalytics, to: $0) }
            ))
            
            Toggle("Share Usage Data", isOn: Binding(
                get: { viewModel.preferences?.shareUsageData ?? false },
                set: { viewModel.update(\.shareUsageData, to: $0) }
            ))
        } header: {
            Text("Privacy & Analytics")
        } footer: {
            Text("Help improve PlayerPath by sharing anonymous usage data.")
        }
    }
    
    private func notificationsSection(preferences: UserPreferences) -> some View {
        Section {
            Toggle("Upload Notifications", isOn: Binding(
                get: { viewModel.preferences?.enableUploadNotifications ?? false },
                set: { viewModel.update(\.enableUploadNotifications, to: $0) }
            ))
            
            Toggle("Game Reminders", isOn: Binding(
                get: { viewModel.preferences?.enableGameReminders ?? false },
                set: { viewModel.update(\.enableGameReminders, to: $0) }
            ))
        } header: {
            Text("Notifications")
        }
    }
}
