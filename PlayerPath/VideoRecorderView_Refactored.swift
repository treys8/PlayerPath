//
//  VideoRecorderView_Refactored.swift
//  PlayerPath
//
//  Created by Assistant on 10/27/25.
//

import SwiftUI
import SwiftData
import AVFoundation
import AVKit
import PhotosUI
import CoreMedia
import UIKit
import Combine
import Network

// MARK: - VideoRecorderView_Refactored

@MainActor
struct VideoRecorderView_Refactored: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let athlete: Athlete?
    let game: Game?
    let practice: Practice?
    
    // Refactored: Use dedicated service objects
    @StateObject private var permissionManager = VideoRecordingPermissionManager()
    @StateObject private var uploadService = VideoUploadService()
    @StateObject private var networkMonitor = NetworkMonitor()
    @State private var notificationService = PushNotificationService.shared
    
    // Simplified state management
    @State private var recordedVideoURL: URL?
    @State private var showingPlayResultOverlay = false
    @State private var showingPhotoPicker = false
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var showingNativeCamera = false
    @State private var selectedVideoQuality: UIImagePickerController.QualityType = .typeHigh
    @State private var showingDiscardConfirmation = false
    @State private var pendingDismissAction: (() -> Void)?
    @State private var showingLowStorageAlert = false
    @State private var showingQualityPicker = false
    @State private var saveTask: Task<Void, Never>?
    @State private var showingTrimmer = false
    @State private var trimmedVideoURL: URL?

    // System monitoring
    @State private var availableStorageGB: Double = 0
    @State private var batteryLevel: Float = 1.0
    @State private var batteryState: UIDevice.BatteryState = .unknown
    @State private var estimatedRecordingMinutes: Int = 0
    @State private var showingBatteryWarning = false

    // Smart features
    @State private var smartSuggestion: String?
    @State private var recordedClipsCount: Int = 0
    @State private var autoOpeningCamera = false

    // Video recording constraints
    private let maxRecordingDuration: TimeInterval = 600 // 10 minutes - matches validation
    private let maxFileSizeBytes: Int64 = 500 * 1024 * 1024 // 500MB - matches validation
    private let minRequiredStorageBytes: Int64 = 1024 * 1024 * 1024 // 1GB minimum
    
    // Quality settings with estimated file sizes (per minute of video)
    private let qualityEstimates: [UIImagePickerController.QualityType: (name: String, mbPerMinute: Double)] = [
        .typeHigh: ("High (1080p)", 60.0),
        .typeMedium: ("Medium (720p)", 25.0),
        .typeLow: ("Low (480p)", 10.0),
        .type640x480: ("SD (480p)", 8.0)
    ]
    
    init(athlete: Athlete?, game: Game? = nil, practice: Practice? = nil) {
        self.athlete = athlete
        self.game = game
        self.practice = practice
    }
    
    var body: some View {
        navigationView
            .fullScreenCover(isPresented: $showingNativeCamera) {
                nativeCameraView
            }
            .sheet(isPresented: $showingTrimmer) {
                videoTrimmerView
            }
            .sheet(isPresented: $showingPlayResultOverlay) {
                playResultOverlay
            }
            .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedVideoItem, matching: .videos)
            .sensoryFeedback(.start, trigger: showingNativeCamera)
            .onChange(of: selectedVideoItem) { _, newItem in
                handleSelectedVideo(newItem)
            }
            .alert("Permission Required", isPresented: $permissionManager.showingPermissionAlert) {
                permissionAlert
            } message: {
                Text(permissionManager.permissionAlertMessage)
            }
            .alert("Error", isPresented: errorAlertBinding) {
                errorAlert
            } message: {
                errorMessage
            }
            .confirmationDialog(
                "Discard Recording?",
                isPresented: $showingDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard Video", role: .destructive) {
                    pendingDismissAction?()
                    pendingDismissAction = nil
                }
                Button("Keep Recording", role: .cancel) {
                    pendingDismissAction = nil
                }
            } message: {
                Text("This video hasn't been saved yet. Are you sure you want to discard it?")
            }
            .alert("Low Storage", isPresented: $showingLowStorageAlert) {
                Button("OK", role: .cancel) {}
                Button("Settings", role: .none) {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsURL)
                    }
                }
            } message: {
                Text("You have less than \(String(format: "%.1f", availableStorageGB)) GB of storage available. Free up space before recording to avoid issues.")
            }
            .sheet(isPresented: $showingQualityPicker) {
                VideoQualityPickerView(selectedQuality: $selectedVideoQuality)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .task {
                // Start network monitoring
                networkMonitor.startMonitoring()

                // Enable battery monitoring
                UIDevice.current.isBatteryMonitoringEnabled = true
                updateBatteryStatus()

                // Load saved quality preference
                if let savedQuality = UserDefaults.standard.value(forKey: "selectedVideoQuality") as? Int {
                    selectedVideoQuality = UIImagePickerController.QualityType(rawValue: savedQuality) ?? .typeHigh
                }

                // Check storage and calculate estimates
                checkAvailableStorage()
                calculateRecordingTime()
                updateRecordedClipsCount()
                generateSmartSuggestion()

                // Battery warning if low
                if batteryLevel < 0.2 && batteryState != .charging {
                    showingBatteryWarning = true
                }

                // Quick record for live games - skip options and go straight to camera
                if game?.isLive == true {
                    autoOpeningCamera = true
                    try? await Task.sleep(for: .milliseconds(100)) // Minimal delay for view to appear
                    guard !Task.isCancelled, autoOpeningCamera else { return }
                    checkCameraPermission()
                    autoOpeningCamera = false
                }
            }
            .onDisappear {
                // Clean up resources when view disappears
                networkMonitor.stopMonitoring()
                // Don't cancel saveTask here — if the user tapped Save, the task must
                // complete even after the view disappears. cleanupAndDismiss() handles
                // the discard path separately.
                UIDevice.current.isBatteryMonitoringEnabled = false
            }
            .alert("Low Battery", isPresented: $showingBatteryWarning) {
                Button("Continue Anyway", role: .none) { }
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
            } message: {
                let suggestion = batteryLevel < 0.1 && VideoRecordingSettings.shared.quality == .ultra4K
                    ? "Your battery is low. Consider using 1080p instead of 4K to conserve power."
                    : "Your battery is at \(Int(batteryLevel * 100))%. Recording may drain it quickly."
                Text(suggestion)
            }
    }
    
    private var navigationView: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                mainContent
                loadingOverlays
                networkStatusBanner
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                toolbarContent
            }
        }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                handleCancelTapped()
            } label: {
                Label("Cancel", systemImage: "xmark")
            }
            .fontWeight(.semibold)
            .accessibilityLabel("Cancel recording")
        }

        ToolbarItem(placement: .principal) {
            // Show context instead of system indicators
            if let game = game {
                Text("vs \(game.opponent)")
                    .font(.headline)
                    .foregroundColor(.white)
            } else if practice != nil {
                Text("Practice Session")
                    .font(.headline)
                    .foregroundColor(.white)
            } else {
                Text("Record Video")
                    .font(.headline)
                    .foregroundColor(.white)
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            // Context-aware button
            if recordedVideoURL != nil {
                Button {
                    handleDoneTapped()
                } label: {
                    Label("Done", systemImage: "checkmark")
                }
                .accessibilityLabel("Save and close")
            } else {
                Menu {
                    Button {
                        showingQualityPicker = true
                    } label: {
                        Label("Video Quality", systemImage: "video.badge.waveform")
                    }

                    if let suggestion = smartSuggestion {
                        Divider()
                        Text(suggestion)
                            .font(.caption)
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .fontWeight(.semibold)
                }
                .accessibilityLabel("Settings and quality")
            }
        }
    }

    private var storageIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: storageIcon)
                .font(.caption)
            Text("\(Int(availableStorageGB)) GB")
                .font(.caption2)
                .fontWeight(.medium)
            if estimatedRecordingMinutes > 0 {
                Text("• \(estimatedRecordingMinutes)min")
                    .font(.caption2)
            }
        }
        .foregroundColor(storageColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(storageColor.opacity(0.2))
        )
        .accessibilityLabel("Storage: \(Int(availableStorageGB)) gigabytes available, approximately \(estimatedRecordingMinutes) minutes of recording time")
    }

    private var batteryIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: batteryIcon)
                .font(.caption)
            Text("\(Int(batteryLevel * 100))%")
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundColor(batteryColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(batteryColor.opacity(0.2))
        )
        .accessibilityLabel("Battery: \(Int(batteryLevel * 100)) percent")
    }

    private var storageColor: Color {
        if availableStorageGB < 2 {
            return .red
        } else if availableStorageGB < 5 {
            return .orange
        } else {
            return .green
        }
    }

    private var storageIcon: String {
        if availableStorageGB < 2 {
            return "externaldrive.fill.badge.exclamationmark"
        } else if availableStorageGB < 5 {
            return "externaldrive.fill.badge.minus"
        } else {
            return "externaldrive.fill"
        }
    }

    private var batteryColor: Color {
        if batteryLevel < 0.1 {
            return .red
        } else if batteryLevel < 0.2 {
            return .orange
        } else {
            return .green
        }
    }

    private var batteryIcon: String {
        if batteryState == .charging || batteryState == .full {
            return "battery.100.bolt"
        } else if batteryLevel < 0.1 {
            return "battery.0"
        } else if batteryLevel < 0.25 {
            return "battery.25"
        } else if batteryLevel < 0.5 {
            return "battery.50"
        } else if batteryLevel < 0.75 {
            return "battery.75"
        } else {
            return "battery.100"
        }
    }
    
    private func qualityName(for quality: UIImagePickerController.QualityType) -> String {
        switch quality {
        case .typeHigh: return "High"
        case .typeMedium: return "Medium"
        case .typeLow: return "Low"
        case .type640x480: return "SD"
        case .typeIFrame1280x720: return "720p"
        case .typeIFrame960x540: return "540p"
        @unknown default: return "Unknown"
        }
    }



    @ViewBuilder
    private var nativeCameraView: some View {
        ModernCameraView(
            settings: .shared,
            onVideoRecorded: { videoURL in
                recordedVideoURL = videoURL
                showingNativeCamera = false
                showingTrimmer = true
            },
            onCancel: {
                showingNativeCamera = false
            },
            onError: { error in
                ErrorHandlerService.shared.handle(
                    AppError.videoRecordingFailed(error.localizedDescription),
                    context: "Camera Recording"
                )
            }
        )
    }
    
    @ViewBuilder
    private var videoTrimmerView: some View {
        if let videoURL = recordedVideoURL {
            NavigationStack {
                PreUploadTrimmerView(
                    videoURL: videoURL,
                    onSave: { trimmedURL in
                        // Use trimmed video if available, otherwise original
                        trimmedVideoURL = trimmedURL
                        showingTrimmer = false
                        showingPlayResultOverlay = true
                    },
                    onSkip: {
                        // Skip trimming, use original video
                        trimmedVideoURL = nil
                        showingTrimmer = false
                        showingPlayResultOverlay = true
                    },
                    onCancel: {
                        // Discard recording
                        pendingDismissAction = {
                            VideoFileManager.cleanup(url: videoURL)
                            if let trimmed = trimmedVideoURL {
                                VideoFileManager.cleanup(url: trimmed)
                            }
                            self.recordedVideoURL = nil
                            self.trimmedVideoURL = nil
                            self.showingTrimmer = false
                        }
                        showingDiscardConfirmation = true
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var playResultOverlay: some View {
        if let videoURL = recordedVideoURL {
            // Use trimmed video if available, otherwise original
            let finalVideoURL = trimmedVideoURL ?? videoURL

            PlayResultOverlayView(
                videoURL: finalVideoURL,
                athlete: athlete,
                game: game,
                practice: practice,
                onSave: { result in
                    saveVideoWithResult(videoURL: finalVideoURL, playResult: result) { dismiss() }
                },
                onCancel: {
                    // Show confirmation before discarding from overlay
                    UIAccessibility.post(notification: .announcement, argument: "Confirm discard recording")
                    pendingDismissAction = {
                        VideoFileManager.cleanup(url: videoURL)
                        if let trimmed = trimmedVideoURL {
                            VideoFileManager.cleanup(url: trimmed)
                        }
                        self.recordedVideoURL = nil
                        self.trimmedVideoURL = nil
                        self.showingPlayResultOverlay = false
                        UIAccessibility.post(notification: .announcement, argument: "Recording discarded")
                    }
                    showingDiscardConfirmation = true
                }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    
    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { ErrorHandlerService.shared.showErrorAlert },
            set: { _ in ErrorHandlerService.shared.dismissError() }
        )
    }
    
    @ViewBuilder
    private var permissionAlert: some View {
        Button("Settings", role: .none) {
            permissionManager.openSettings()
        }
        Button("Cancel", role: .cancel) {
            dismiss()
        }
    }
    
    @ViewBuilder
    private var errorAlert: some View {
        if let error = ErrorHandlerService.shared.currentError {
            // Show retry for errors that make sense to retry
            if error.suggestedActions.contains(.retry) {
                Button("Retry", role: .none) {
                    retryLastAction()
                }
            }
            Button("Copy Details") {
                copyErrorToClipboard(error)
            }
        }
        Button("OK", role: .cancel) {
            ErrorHandlerService.shared.dismissError()
        }
    }
    
    @ViewBuilder
    private var errorMessage: some View {
        if let error = ErrorHandlerService.shared.currentError {
            VStack(spacing: 12) {
                Text(error.errorDescription ?? "An error occurred")
                    .font(.body)
                    .multilineTextAlignment(.center)
                
                if let recovery = error.recoverySuggestion {
                    Divider()
                    
                    HStack(spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                        Text(recovery)
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    .multilineTextAlignment(.center)
                }
            }
        }
    }
    
    private func copyErrorToClipboard(_ error: AppError) {
        var details = "PlayerPath Error Report\n"
        details += "Generated: \(Date().formatted())\n\n"
        details += "Error: \(error.errorDescription ?? "Unknown error")\n"
        if let recovery = error.recoverySuggestion {
            details += "Suggestion: \(recovery)\n"
        }
        details += "Severity: \(error.severity)\n"
        details += "Suggested Actions: \(error.suggestedActions.map { String(describing: $0) }.joined(separator: ", "))\n"

        UIPasteboard.general.string = details
        ErrorHandlerService.shared.dismissError()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    
    private func retryLastAction() {
        ErrorHandlerService.shared.dismissError()
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        // Retry the last selected video if there was one
        if let lastItem = selectedVideoItem {
            handleSelectedVideo(lastItem)
        }
    }
    
    // MARK: - View Components
    
    private var mainContent: some View {
        VStack(spacing: 25) {
            headerSection
            Spacer()

            // For live games, skip the options screen and show loading while camera opens
            if game?.isLive == true {
                liveGameLoadingView
            } else {
                // Use dedicated options view for non-live games
                VideoRecordingOptionsView(
                    onRecordVideo: {
                        print("VideoRecorder: Record Video button tapped")
                        checkCameraPermission()
                    },
                    onUploadVideo: {
                        print("VideoRecorder: Upload Video button tapped")
                        showingPhotoPicker = true
                    },
                    tipText: "Tip: Position camera to capture the full swing and follow-through",
                    hideUpload: false
                )

                // Recording guidelines
                recordingGuidelinesSection
            }

            Spacer()
        }
        .padding()
    }

    private var liveGameLoadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)

            Text("Opening Camera...")
                .font(.headline)
                .foregroundColor(.white)

            Text("Get ready to capture the play!")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    private var recordingGuidelinesSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.caption)
                .foregroundColor(.blue)

            Text("Up to \(Int(maxRecordingDuration / 60)) minutes • \(qualityName(for: selectedVideoQuality)) quality")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal)
        .accessibilityLabel("Recording limit: Maximum \(Int(maxRecordingDuration / 60)) minutes at \(qualityName(for: selectedVideoQuality)) quality")
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            if let game = game {
                // Live game header with rich context
                VStack(spacing: 8) {
                    HStack {
                        // Live badge
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 6, height: 6)

                            Text("LIVE GAME")
                                .font(.caption)
                                .fontWeight(.bold)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.red)
                        )
                        .foregroundColor(.white)

                        Spacer()

                        // Clips counter
                        if recordedClipsCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "video")
                                    .font(.caption2)
                                Text("\(recordedClipsCount)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.2))
                            )
                        }
                    }

                    // Opponent & Score
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("vs \(game.opponent)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)

                            // Game date
                            if let date = game.date {
                                Text(date, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }

                        Spacer()
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Live game versus \(game.opponent), \(recordedClipsCount) clips recorded")
            } else if let practice = practice {
                VStack(spacing: 4) {
                    Text("Practice Session")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.8)

                    if let date = practice.date {
                        Text(date, formatter: DateFormatter.shortDate)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    } else {
                        Text("Date TBA")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.1))
                )
            } else {
                Text("Video Recording")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.1))
                    )
                    .minimumScaleFactor(0.8)
            }
        }
    }

    @ViewBuilder
    private var loadingOverlays: some View {
        if uploadService.isProcessingVideo {
            LoadingOverlay(message: "Processing video...")
        }

        if permissionManager.isRequestingPermissions {
            LoadingOverlay(message: "Requesting permissions...")
        }

        // Auto-opening camera for live games
        if autoOpeningCamera {
            ZStack {
                Color.black.opacity(0.8)
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)

                    Text("Opening Camera...")
                        .font(.headline)
                        .foregroundColor(.white)

                    Button("Cancel") {
                        autoOpeningCamera = false
                        Haptics.light()
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
            }
            .transition(.opacity)
        }
    }
    
    @ViewBuilder
    private var networkStatusBanner: some View {
        VStack(spacing: 0) {
            // Network status
            if !networkMonitor.isConnected {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .font(.caption)
                    Text("No internet connection")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    Text("Videos will save locally")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.orange.opacity(0.9))
                )
                .padding(.horizontal)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("No internet connection. Videos will save locally.")
            }
            
            // Low storage warning (critical)
            if availableStorageGB > 0 && availableStorageGB < 1.0 {
                HStack(spacing: 8) {
                    Image(systemName: "externaldrive.fill.badge.exclamationmark")
                        .font(.caption)
                    Text("Low storage: \(String(format: "%.1f", availableStorageGB)) GB free")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    Button("Manage") {
                        showingLowStorageAlert = true
                    }
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(4)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.red.opacity(0.9))
                )
                .padding(.horizontal)
                .padding(.top, networkMonitor.isConnected ? 8 : 4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Low storage warning. \(String(format: "%.1f", availableStorageGB)) gigabytes free.")
            }
            // Storage suggestion (moderate)
            else if availableStorageGB > 0 && availableStorageGB < 3.0 && selectedVideoQuality == .typeHigh {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption)
                    Text("\(String(format: "%.1f", availableStorageGB)) GB free")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    Button("Use Medium Quality") {
                        selectedVideoQuality = .typeMedium
                        UserDefaults.standard.set(selectedVideoQuality.rawValue, forKey: "selectedVideoQuality")
                        Haptics.light()
                    }
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(4)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.yellow.opacity(0.9))
                )
                .padding(.horizontal)
                .padding(.top, networkMonitor.isConnected ? 8 : 4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Limited storage. Consider using medium quality.")
            }
            
            Spacer()
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: networkMonitor.isConnected)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: availableStorageGB)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedVideoQuality)
    }
    
    // MARK: - Business Logic
    
    private func handleCancelTapped() {
        if recordedVideoURL != nil && !showingPlayResultOverlay {
            // Video recorded but user is back at main screen - confirm discard
            UIAccessibility.post(notification: .announcement, argument: "Confirm discard recording")
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            pendingDismissAction = {
                UIAccessibility.post(notification: .announcement, argument: "Recording discarded")
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                self.cleanupAndDismiss()
            }
            showingDiscardConfirmation = true
        } else {
            // No video recorded, or user is in overlay (which has its own cancel)
            UIAccessibility.post(notification: .announcement, argument: "Recording cancelled")
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            cleanupAndDismiss()
        }
    }
    
    private func handleDoneTapped() {
        if recordedVideoURL != nil && !showingPlayResultOverlay {
            // Video recorded but not saved - confirm discard
            UIAccessibility.post(notification: .announcement, argument: "Confirm discard recording")
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            pendingDismissAction = {
                UIAccessibility.post(notification: .announcement, argument: "Recording discarded")
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                self.cleanupAndDismiss()
            }
            showingDiscardConfirmation = true
        } else {
            // No video recorded, safe to dismiss
            UIAccessibility.post(notification: .announcement, argument: "Closing recorder")
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            cleanupAndDismiss()
        }
    }
    
    private func handleSelectedVideo(_ item: PhotosPickerItem?) {
        Task {
            let result = await uploadService.processSelectedVideo(item)
            switch result {
            case .success(let videoURL):
                recordedVideoURL = videoURL
                showingPlayResultOverlay = true
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
            case .failure(let error):
                print("Failed to process video: \(error)")
                // Error is already handled by uploadService
            }
        }
    }
    
    private func checkCameraPermission() {
        // First check if we have enough storage
        let hasEnoughStorage = checkAvailableStorage()
        
        guard hasEnoughStorage else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            showingLowStorageAlert = true
            return
        }
        
        // Smart quality suggestion based on available storage
        if availableStorageGB < 3.0 && selectedVideoQuality == .typeHigh {
            // Suggest lower quality if storage is tight
            Task {
                await MainActor.run {
                    // Show a helpful tip
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.warning)
                }
            }
        }
        
        Task {
            let result = await permissionManager.checkPermissions()
            switch result {
            case .success:
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                // Add delay to ensure permission dialogs have fully dismissed
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second
                showingNativeCamera = true
            case .failure(let error):
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                print("Permission check failed: \(error)")
                // Error is already handled by permissionManager
            }
        }
    }
    
    @discardableResult
    private func checkAvailableStorage() -> Bool {
        do {
            let fileURL = URL(fileURLWithPath: NSHomeDirectory() as String)
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])

            if let capacity = values.volumeAvailableCapacityForImportantUsage {
                availableStorageGB = Double(capacity) / 1_000_000_000.0 // Convert to GB
                print("Storage check: \(String(format: "%.2f", availableStorageGB)) GB available")

                // Check if we have at least minimum required storage
                return capacity >= minRequiredStorageBytes
            }
        } catch {
            print("Error checking storage: \(error)")
        }

        // If we can't determine storage, allow recording (fail open)
        return true
    }

    private func updateBatteryStatus() {
        batteryLevel = UIDevice.current.batteryLevel
        batteryState = UIDevice.current.batteryState

        // If battery level is unknown, assume full
        if batteryLevel < 0 {
            batteryLevel = 1.0
        }

        print("Battery: \(Int(batteryLevel * 100))%, state: \(batteryState.rawValue)")
    }

    private func calculateRecordingTime() {
        guard availableStorageGB > 0 else { return }

        // Get current quality estimate (MB per minute)
        let mbPerMinute = VideoRecordingSettings.shared.estimatedFileSizePerMinute

        // Calculate how many minutes we can record
        let availableMB = availableStorageGB * 1000
        let minutes = Int(availableMB / mbPerMinute)

        estimatedRecordingMinutes = min(minutes, Int(maxRecordingDuration / 60))

        print("Can record ~\(estimatedRecordingMinutes) min at current quality")
    }

    private func updateRecordedClipsCount() {
        guard let athlete = athlete else {
            recordedClipsCount = 0
            return
        }

        // Capture IDs for use in predicates
        let athleteID = athlete.id

        // Count clips for this game/practice
        let predicate: Predicate<VideoClip>

        if let game = game {
            let gameID = game.id
            predicate = #Predicate<VideoClip> { clip in
                clip.athlete?.id == athleteID && clip.game?.id == gameID
            }
        } else if let practice = practice {
            let practiceID = practice.id
            predicate = #Predicate<VideoClip> { clip in
                clip.athlete?.id == athleteID && clip.practice?.id == practiceID
            }
        } else {
            // No specific context, count recent clips
            predicate = #Predicate<VideoClip> { clip in
                clip.athlete?.id == athleteID
            }
        }

        do {
            var descriptor = FetchDescriptor(predicate: predicate)
            descriptor.fetchLimit = 100

            let clips = try modelContext.fetch(descriptor)
            recordedClipsCount = clips.count

            print("Found \(recordedClipsCount) existing clips for this context")
        } catch {
            print("Error counting clips: \(error)")
            recordedClipsCount = 0
        }
    }

    private func generateSmartSuggestion() {
        let currentQuality = VideoRecordingSettings.shared.quality
        let currentFPS = VideoRecordingSettings.shared.frameRate
        let isPitching = game != nil // Simplification - could be more sophisticated

        // Battery-based suggestions
        if batteryLevel < 0.15 && batteryState != .charging {
            if currentQuality == .ultra4K {
                smartSuggestion = "Low battery - Switch to 1080p to conserve power"
                return
            } else {
                smartSuggestion = "Low battery - Consider reducing quality"
                return
            }
        }

        // Storage-based suggestions
        if availableStorageGB < 3 {
            if currentQuality == .ultra4K {
                smartSuggestion = "Low storage - 4K uses ~200MB/min. Consider 1080p"
                return
            } else if currentQuality == .high1080p {
                smartSuggestion = "Low storage - Consider 720p to save space"
                return
            }
        }

        // Context-based suggestions
        if isPitching && currentFPS.fps < 60 {
            smartSuggestion = "Tip: Enable 60fps or higher for better slow-motion"
            return
        }

        if availableStorageGB > 20 && currentQuality != .ultra4K {
            smartSuggestion = "Plenty of storage - Consider 4K for maximum quality"
            return
        }

        smartSuggestion = nil
    }
    
    private func saveVideoWithResult(videoURL: URL, playResult: PlayResultType?, onComplete: @escaping () -> Void) {
        guard let athlete = athlete else {
            print("ERROR: No athlete selected for video save")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        // Cancel any existing save task
        saveTask?.cancel()

        // Store the new save task for cancellation on cleanup
        saveTask = Task {
            guard !Task.isCancelled else {
                print("VideoRecorder: Save task cancelled before starting")
                return
            }

            do {
                _ = try await ClipPersistenceService().saveClip(
                    from: videoURL,
                    playResult: playResult,
                    context: modelContext,
                    athlete: athlete,
                    game: game,
                    practice: practice
                )

                // Success feedback
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    UIAccessibility.post(notification: .announcement, argument: "Video saved successfully")
                    onComplete()
                }
            } catch {
                guard !Task.isCancelled else {
                    print("VideoRecorder: Save task cancelled during error handling")
                    return
                }

                print("Failed to save video: \(error)")
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }
    
    private func cleanupAndDismiss() {
        print("VideoRecorder: cleanupAndDismiss called")

        // Cancel any pending save task
        saveTask?.cancel()
        saveTask = nil

        Task { @MainActor in
            if let videoURL = recordedVideoURL {
                VideoFileManager.cleanup(url: videoURL)
            }
            showingPlayResultOverlay = false
            recordedVideoURL = nil
            showingNativeCamera = false
            showingPhotoPicker = false
            selectedVideoItem = nil
            print("VideoRecorder: State reset, attempting dismiss")
            dismiss()
        }
    }
}

// MARK: - Supporting Views

struct GuidelineItem: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            Text(text)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.1))
        )
    }
}



// MARK: - Network Monitoring

class NetworkMonitor: ObservableObject {
    @Published var isConnected: Bool = true
    @Published var connectionType: NWInterface.InterfaceType?

    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "NetworkMonitor")

    func startMonitoring() {
        guard monitor == nil else { return }

        let pathMonitor = NWPathMonitor()
        monitor = pathMonitor

        pathMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async { [weak self] in
                self?.isConnected = path.status == .satisfied
                self?.connectionType = path.availableInterfaces.first?.type

                if path.status == .satisfied {
                    if let type = path.availableInterfaces.first?.type {
                        let typeString = self?.interfaceTypeName(type) ?? "unknown"
                        print("NetworkMonitor: Connected via \(typeString)")
                    }
                } else {
                    print("NetworkMonitor: Disconnected")
                }
            }
        }
        pathMonitor.start(queue: queue)
        print("NetworkMonitor: Started monitoring")
    }

    func stopMonitoring() {
        monitor?.cancel()
        monitor = nil
        print("NetworkMonitor: Stopped monitoring")
    }

    private func interfaceTypeName(_ type: NWInterface.InterfaceType) -> String {
        switch type {
        case .wifi: return "WiFi"
        case .cellular: return "Cellular"
        case .wiredEthernet: return "Ethernet"
        case .loopback: return "Loopback"
        case .other: return "Other"
        @unknown default: return "Unknown"
        }
    }

    var isOnWiFi: Bool {
        connectionType == .wifi
    }

    var isOnCellular: Bool {
        connectionType == .cellular
    }
}

#Preview("Recorder - Game") {
    // Minimal inline mock for preview purposes
    let mockGame = Game(date: Date(), opponent: "Rivals")
    VideoRecorderView_Refactored(athlete: nil, game: mockGame, practice: nil)
}

#Preview("Recorder - Practice") {
    // Minimal inline mock for preview purposes
    let mockPractice = Practice(date: Date())
    VideoRecorderView_Refactored(athlete: nil, game: nil, practice: mockPractice)
}

// MARK: - Pre-Upload Trimmer View

struct PreUploadTrimmerView: View {
    let videoURL: URL
    let onSave: (URL) -> Void
    let onSkip: () -> Void
    let onCancel: () -> Void

    @State private var player: AVPlayer?
    @State private var startTime: Double = 0
    @State private var endTime: Double = 0
    @State private var duration: Double = 0
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var currentTime: Double = 0
    @State private var isPlaying = false
    @State private var timeObserver: Any?

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Text("Trim Video")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Cut out unwanted footage before saving")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top)

            // Video Player
            if let player = player {
                ZStack(alignment: .bottom) {
                    VideoPlayer(player: player)
                        .frame(height: 300)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.blue.opacity(0.3), lineWidth: 2)
                        )

                    // Playback controls
                    HStack(spacing: 16) {
                        Button {
                            seekTo(time: startTime)
                        } label: {
                            Image(systemName: "backward.end.fill")
                                .font(.title3)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }

                        Button {
                            if isPlaying {
                                player.pause()
                            } else {
                                player.play()
                            }
                            isPlaying.toggle()
                            Haptics.light()
                        } label: {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(16)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }

                        Button {
                            seekTo(time: endTime)
                        } label: {
                            Image(systemName: "forward.end.fill")
                                .font(.title3)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                    }
                    .padding(.bottom, 12)
                }
            }

            // Trim controls
            if duration > 0 {
                VStack(spacing: 16) {
                    // Time indicator
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Start")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(formatTime(startTime))
                                .font(.headline)
                                .monospacedDigit()
                        }

                        Spacer()

                        VStack(spacing: 4) {
                            Text("Duration")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(formatTime(endTime - startTime))
                                .font(.headline)
                                .monospacedDigit()
                                .foregroundColor(.blue)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("End")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(formatTime(endTime))
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                    .padding(.horizontal)

                    // Start slider
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Trim Start")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Slider(value: $startTime, in: 0...max(0, endTime - 0.5), step: 0.1) {
                            Text("Start")
                        }
                        .tint(.green)
                        .onChange(of: startTime) { _, newValue in
                            seekTo(time: newValue)
                        }
                    }
                    .padding(.horizontal)

                    // End slider
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Trim End")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Slider(value: $endTime, in: min(duration, startTime + 0.5)...duration, step: 0.1) {
                            Text("End")
                        }
                        .tint(.red)
                        .onChange(of: endTime) { _, newValue in
                            seekTo(time: newValue)
                        }
                    }
                    .padding(.horizontal)
                }
            }

            if let error = exportError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            // Action buttons
            VStack(spacing: 12) {
                Button {
                    Haptics.success()
                    Task { await exportTrimmedVideo() }
                } label: {
                    if isExporting {
                        HStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            Text("Trimming...")
                        }
                    } else {
                        Label("Save Trimmed Video", systemImage: "scissors")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
                .disabled(isExporting || endTime - startTime < 0.5)

                HStack(spacing: 12) {
                    Button {
                        Haptics.light()
                        onSkip()
                    } label: {
                        Text("Use Full Video")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(uiColor: .systemGray5))
                            .foregroundColor(.primary)
                            .cornerRadius(10)
                    }
                    .disabled(isExporting)

                    Button {
                        Haptics.warning()
                        onCancel()
                    } label: {
                        Text("Discard")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .cornerRadius(10)
                    }
                    .disabled(isExporting)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            cleanup()
        }
    }

    private func setupPlayer() {
        let newPlayer = AVPlayer(url: videoURL)
        player = newPlayer

        // Add time observer for playback position
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [self] time in
            currentTime = time.seconds
        }

        Task {
            let asset = AVURLAsset(url: videoURL)
            do {
                let loadedDuration = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(loadedDuration)
                await MainActor.run {
                    self.duration = seconds
                    self.startTime = 0
                    self.endTime = seconds
                }
            } catch {
                await MainActor.run {
                    self.exportError = "Unable to load video: \(error.localizedDescription)"
                }
            }
        }
    }

    private func seekTo(time: Double) {
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
        player?.pause()
        isPlaying = false
    }

    private func cleanup() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        player?.pause()
        player = nil
    }

    private func exportTrimmedVideo() async {
        isExporting = true
        exportError = nil

        let asset = AVURLAsset(url: videoURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            exportError = "Export session could not be created."
            isExporting = false
            return
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("trimmed_\(UUID().uuidString).mp4")

        let start = CMTime(seconds: startTime, preferredTimescale: 600)
        let end = CMTime(seconds: endTime, preferredTimescale: 600)
        session.timeRange = CMTimeRangeFromTimeToTime(start: start, end: end)
        session.outputURL = outputURL
        session.outputFileType = .mp4

        if #available(iOS 18.0, *) {
            do {
                try await session.export(to: outputURL, as: .mp4)
                await MainActor.run {
                    isExporting = false
                    Haptics.success()
                    onSave(outputURL)
                }
            } catch {
                await MainActor.run {
                    try? FileManager.default.removeItem(at: outputURL)
                    isExporting = false
                    exportError = error.localizedDescription
                }
            }
        } else {
            await session.export()
            await MainActor.run {
                switch session.status {
                case .completed:
                    isExporting = false
                    Haptics.success()
                    onSave(outputURL)
                case .failed:
                    try? FileManager.default.removeItem(at: outputURL)
                    isExporting = false
                    exportError = session.error?.localizedDescription ?? "Export failed"
                case .cancelled:
                    try? FileManager.default.removeItem(at: outputURL)
                    isExporting = false
                    exportError = "Export was cancelled"
                default:
                    try? FileManager.default.removeItem(at: outputURL)
                    isExporting = false
                    exportError = "Export ended with unknown status"
                }
            }
        }
    }

    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%01d", minutes, seconds, milliseconds)
    }
}

