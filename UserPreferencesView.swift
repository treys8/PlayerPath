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
    @StateObject private var cloudKitManager = CloudKitManager.shared
    
    @State private var preferences: UserPreferences
    @State private var showingSyncAlert = false
    @State private var syncAlertMessage = ""
    @State private var hasUnsavedChanges = false
    
    init() {
        // Initialize with default preferences
        _preferences = State(initialValue: UserPreferences())
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // CloudKit Status Section
                Section {
                    HStack {
                        Image(systemName: cloudKitManager.isCloudKitAvailable ? "icloud" : "icloud.slash")
                            .foregroundColor(cloudKitManager.isCloudKitAvailable ? .green : .red)
                        
                        VStack(alignment: .leading) {
                            Text("iCloud Sync")
                                .font(.headline)
                            Text(cloudKitManager.isCloudKitAvailable ? "Available" : "Not Available")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if case .syncing = cloudKitManager.syncStatus {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                    
                    if !cloudKitManager.isCloudKitAvailable {
                        Text("Sign in to iCloud to sync your preferences across devices.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Cloud Sync")
                }
                
                // Video Recording Preferences
                Section {
                    Picker("Video Quality", selection: $preferences.defaultVideoQuality) {
                        ForEach(VideoQuality.allCases, id: \.self) { quality in
                            Text(quality.rawValue).tag(quality)
                        }
                    }
                    .onChange(of: preferences.defaultVideoQuality) { _, _ in
                        hasUnsavedChanges = true
                    }
                    
                    Toggle("Auto-upload to Cloud", isOn: $preferences.autoUploadToCloud)
                        .onChange(of: preferences.autoUploadToCloud) { _, _ in
                            hasUnsavedChanges = true
                        }
                    
                    Toggle("Save to Photos Library", isOn: $preferences.saveToPhotosLibrary)
                        .onChange(of: preferences.saveToPhotosLibrary) { _, _ in
                            hasUnsavedChanges = true
                        }
                    
                    Toggle("Haptic Feedback", isOn: $preferences.enableHapticFeedback)
                        .onChange(of: preferences.enableHapticFeedback) { _, _ in
                            hasUnsavedChanges = true
                        }
                } header: {
                    Text("Video Recording")
                }
                
                // UI Preferences
                Section {
                    Picker("App Theme", selection: $preferences.preferredTheme) {
                        ForEach(AppTheme.allCases, id: \.self) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                    .onChange(of: preferences.preferredTheme) { _, _ in
                        hasUnsavedChanges = true
                    }
                    
                    Toggle("Show Onboarding Tips", isOn: $preferences.showOnboardingTips)
                        .onChange(of: preferences.showOnboardingTips) { _, _ in
                            hasUnsavedChanges = true
                        }
                    
                    Toggle("Debug Mode", isOn: $preferences.enableDebugMode)
                        .onChange(of: preferences.enableDebugMode) { _, _ in
                            hasUnsavedChanges = true
                        }
                } header: {
                    Text("Interface")
                }
                
                // Cloud Sync Preferences
                Section {
                    Toggle("Sync Highlights Only", isOn: $preferences.syncHighlightsOnly)
                        .onChange(of: preferences.syncHighlightsOnly) { _, _ in
                            hasUnsavedChanges = true
                        }
                    
                    HStack {
                        Text("Max File Size")
                        Spacer()
                        Text("\(preferences.maxVideoFileSize) MB")
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(value: Binding(
                        get: { Double(preferences.maxVideoFileSize) },
                        set: { preferences.maxVideoFileSize = Int($0); hasUnsavedChanges = true }
                    ), in: 100...1000, step: 50)
                    
                    Toggle("Auto-delete After Upload", isOn: $preferences.autoDeleteAfterUpload)
                        .onChange(of: preferences.autoDeleteAfterUpload) { _, _ in
                            hasUnsavedChanges = true
                        }
                } header: {
                    Text("Cloud Storage")
                }
                
                // Privacy & Analytics
                Section {
                    Toggle("Enable Analytics", isOn: $preferences.enableAnalytics)
                        .onChange(of: preferences.enableAnalytics) { _, _ in
                            hasUnsavedChanges = true
                        }
                    
                    Toggle("Share Usage Data", isOn: $preferences.shareUsageData)
                        .onChange(of: preferences.shareUsageData) { _, _ in
                            hasUnsavedChanges = true
                        }
                } header: {
                    Text("Privacy & Analytics")
                } footer: {
                    Text("Help improve PlayerPath by sharing anonymous usage data.")
                }
                
                // Notifications
                Section {
                    Toggle("Upload Notifications", isOn: $preferences.enableUploadNotifications)
                        .onChange(of: preferences.enableUploadNotifications) { _, _ in
                            hasUnsavedChanges = true
                        }
                    
                    Toggle("Game Reminders", isOn: $preferences.enableGameReminders)
                        .onChange(of: preferences.enableGameReminders) { _, _ in
                            hasUnsavedChanges = true
                        }
                } header: {
                    Text("Notifications")
                }
                
                // Save & Sync Actions
                if hasUnsavedChanges {
                    Section {
                        Button(action: savePreferences) {
                            HStack {
                                Image(systemName: "checkmark.circle")
                                Text("Save Changes")
                            }
                        }
                        .foregroundColor(.green)
                        
                        if cloudKitManager.isCloudKitAvailable {
                            Button(action: saveAndSync) {
                                HStack {
                                    Image(systemName: "icloud.and.arrow.up")
                                    Text("Save & Sync to iCloud")
                                }
                            }
                            .foregroundColor(.blue)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadPreferences()
            }
            .alert("Sync Status", isPresented: $showingSyncAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(syncAlertMessage)
            }
        }
    }
    
    // MARK: - Data Management
    
    private func loadPreferences() {
        let descriptor = FetchDescriptor<UserPreferences>()
        do {
            let savedPreferences = try modelContext.fetch(descriptor)
            if let existingPreferences = savedPreferences.first {
                preferences = existingPreferences
            } else {
                // Create new preferences with defaults
                preferences = UserPreferences()
                modelContext.insert(preferences)
                try modelContext.save()
            }
        } catch {
            print("Error loading preferences: \(error)")
        }
    }
    
    private func savePreferences() {
        do {
            try modelContext.save()
            hasUnsavedChanges = false
            print("Preferences saved locally")
        } catch {
            print("Error saving preferences: \(error)")
            syncAlertMessage = "Failed to save preferences: \(error.localizedDescription)"
            showingSyncAlert = true
        }
    }
    
    private func saveAndSync() {
        // First save locally
        savePreferences()
        
        // Then sync to CloudKit
        Task {
            do {
                try await cloudKitManager.syncUserPreferences(preferences)
                await MainActor.run {
                    syncAlertMessage = "Preferences successfully synced to iCloud"
                    showingSyncAlert = true
                }
            } catch {
                await MainActor.run {
                    syncAlertMessage = "Failed to sync to iCloud: \(error.localizedDescription)"
                    showingSyncAlert = true
                }
            }
        }
    }
}