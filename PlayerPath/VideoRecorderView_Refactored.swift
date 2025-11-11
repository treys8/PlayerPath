//
//  VideoRecorderView_Refactored.swift
//  PlayerPath
//
//  Created by Assistant on 10/27/25.
//

import SwiftUI
import SwiftData
import AVFoundation
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
    @State private var availableStorageGB: Double = 0
    @State private var showingQualityPicker = false
    
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
                    if let settingsURL = URL(string: "App-Prefs:root=General&path=STORAGE_MGMT") {
                        UIApplication.shared.open(settingsURL)
                    }
                }
            } message: {
                Text("You have less than \(String(format: "%.1f", availableStorageGB)) GB of storage available. Free up space before recording to avoid issues.")
            }
            .confirmationDialog(
                "Video Quality",
                isPresented: $showingQualityPicker,
                titleVisibility: .visible
            ) {
                ForEach([UIImagePickerController.QualityType.typeHigh, .typeMedium, .typeLow, .type640x480], id: \.self) { quality in
                    Button {
                        selectedVideoQuality = quality
                        UserDefaults.standard.set(quality.rawValue, forKey: "selectedVideoQuality")
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        if let estimate = qualityEstimates[quality] {
                            let maxSize = estimate.mbPerMinute * (maxRecordingDuration / 60.0)
                            Text("\(estimate.name) • ~\(Int(estimate.mbPerMinute))MB/min • Max \(Int(maxSize))MB")
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Higher quality produces larger files. Choose based on your storage and network conditions.")
            }
            .task {
                // Load saved quality preference
                if let savedQuality = UserDefaults.standard.value(forKey: "selectedVideoQuality") as? Int {
                    selectedVideoQuality = UIImagePickerController.QualityType(rawValue: savedQuality) ?? .typeHigh
                }
                
                // Check storage on appear
                checkAvailableStorage()
                
                // Auto-open camera when launched for a live game to streamline recording
                if game?.isLive == true {
                    try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
                    checkCameraPermission()
                }
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
            Button {
                showingQualityPicker = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "video.badge.waveform")
                        .font(.caption)
                    if let estimate = qualityEstimates[selectedVideoQuality] {
                        Text(qualityName(for: selectedVideoQuality))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                )
            }
            .accessibilityLabel("Video quality: \(qualityName(for: selectedVideoQuality)). Tap to change.")
        }
        
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                handleDoneTapped()
            } label: {
                Label("Done", systemImage: "checkmark")
            }
            .accessibilityLabel("Close recorder")
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


    
    private var nativeCameraView: some View {
        // Note: NativeCameraView should be updated to:
        // 1. Accept maxRecordingDuration parameter
        // 2. Set UIImagePickerController.videoMaximumDuration = maxRecordingDuration
        // 3. Display a recording timer to the user
        // 4. Show a warning when approaching the limit (e.g., at 9 minutes for 10 min max)
        //
        // Current signature only supports videoQuality - maxDuration support pending
        NativeCameraView(videoQuality: selectedVideoQuality, onVideoRecorded: { videoURL in
            print("VideoRecorder: onVideoRecorded called with URL: \(videoURL)")
            recordedVideoURL = videoURL
            showingNativeCamera = false
            showingPlayResultOverlay = true
        }, onCancel: {
            print("VideoRecorder: onCancel called from NativeCameraView")
            showingNativeCamera = false
        })
        .accessibilityLabel("Native camera view")
    }
    
    @ViewBuilder
    private var playResultOverlay: some View {
        if let videoURL = recordedVideoURL {
            PlayResultOverlayView(
                videoURL: videoURL,
                athlete: athlete,
                game: game,
                practice: practice,
                onSave: { result in
                    saveVideoWithResult(videoURL: videoURL, playResult: result)
                    dismiss()
                },
                onCancel: {
                    // Show confirmation before discarding from overlay
                    UIAccessibility.post(notification: .announcement, argument: "Confirm discard recording")
                    pendingDismissAction = {
                        VideoFileManager.cleanup(url: videoURL)
                        self.recordedVideoURL = nil
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
            get: { uploadService.errorHandler.isShowingError },
            set: { _ in uploadService.errorHandler.dismissError() }
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
        if let error = uploadService.errorHandler.currentError as? PlayerPathError {
            if error.isRetryable {
                Button("Retry", role: .none) {
                    retryLastAction()
                }
            }
            Button("Copy Details") {
                copyErrorToClipboard(error)
            }
        }
        Button("OK", role: .cancel) { 
            uploadService.errorHandler.dismissError()
        }
    }
    
    @ViewBuilder
    private var errorMessage: some View {
        if let error = uploadService.errorHandler.currentError as? PlayerPathError {
            VStack(spacing: 12) {
                Text(error.localizedDescription)
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
        } else if let error = uploadService.errorHandler.currentError {
            Text(error.localizedDescription)
                .multilineTextAlignment(.center)
        }
    }
    
    private func copyErrorToClipboard(_ error: PlayerPathError) {
        var details = "Error: \(error.localizedDescription)\n"
        if let recovery = error.recoverySuggestion {
            details += "Suggestion: \(recovery)\n"
        }
        details += "Error ID: \(error.id)\n"
        details += "Retryable: \(error.isRetryable ? "Yes" : "No")"
        
        UIPasteboard.general.string = details
        uploadService.errorHandler.dismissError()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    
    private func retryLastAction() {
        uploadService.errorHandler.dismissError()
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
            
            // Use dedicated options view
            VideoRecordingOptionsView(
                onRecordVideo: {
                    print("VideoRecorder: Record Video button tapped")
                    checkCameraPermission()
                },
                onUploadVideo: {
                    print("VideoRecorder: Upload Video button tapped")
                    showingPhotoPicker = true
                }
            )
            
            // Recording guidelines
            recordingGuidelinesSection
            
            Spacer()
        }
        .padding()
    }
    
    private var recordingGuidelinesSection: some View {
        VStack(spacing: 8) {
            Text("Recording Guidelines")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.8))
                .accessibilityAddTraits(.isHeader)
            
            HStack(spacing: 16) {
                GuidelineItem(
                    icon: "clock.fill",
                    text: "Max \(Int(maxRecordingDuration / 60)) min",
                    color: .blue
                )
                
                if let estimate = qualityEstimates[selectedVideoQuality] {
                    let estimatedMaxSize = estimate.mbPerMinute * (maxRecordingDuration / 60.0)
                    GuidelineItem(
                        icon: "arrow.down.circle.fill",
                        text: "~\(Int(estimatedMaxSize))MB max",
                        color: .green
                    )
                }
            }
            
            // Show quality-specific tip
            if let estimate = qualityEstimates[selectedVideoQuality] {
                Text("At \(estimate.name) quality: ~\(Int(estimate.mbPerMinute))MB per minute")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recording limits: Maximum \(Int(maxRecordingDuration / 60)) minutes at \(qualityName(for: selectedVideoQuality)) quality")
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            if let game = game {
                HStack {
                    Text("LIVE GAME")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.red)
                                .glassEffect(.regular.tint(.red), in: .capsule)
                        )
                        .foregroundColor(.white)
                        .accessibilityLabel("Live game")
                    
                    Spacer()
                }
                
                Text("vs \(game.opponent)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.8)
                    .accessibilityLabel("Versus \(game.opponent)")
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
                .glassEffect(.regular, in: .rect(cornerRadius: 12))
            } else {
                Text("Video Recording")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .rect(cornerRadius: 12))
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
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
    
    private func saveVideoWithResult(videoURL: URL, playResult: PlayResultType?) {
        guard let athlete = athlete else {
            print("ERROR: No athlete selected for video save")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        Task {
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
                }
            } catch {
                print("Failed to save video: \(error)")
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }
    
    private func cleanupAndDismiss() {
        print("VideoRecorder: cleanupAndDismiss called")
        DispatchQueue.main.async {
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

struct LoadingOverlay: View {
    let message: String
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .accessibilityAddTraits(.isModal)
            
            VStack(spacing: 16) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
                
                Text(message)
                    .font(.headline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
        }
    }
}

// MARK: - Network Monitoring

class NetworkMonitor: ObservableObject {
    @Published var isConnected: Bool = true
    @Published var connectionType: NWInterface.InterfaceType?
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    init() {
        startMonitoring()
    }
    
    deinit {
        monitor.cancel()
    }
    
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
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
        monitor.start(queue: queue)
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

