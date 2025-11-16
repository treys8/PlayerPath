//
//  VideoRecordingIntegrationExample.swift
//  PlayerPath
//
//  Created by Assistant on 11/13/25.
//
//  This file shows how to integrate the new video recording options
//  into your existing VideoRecorderView_Refactored.swift

import SwiftUI

// MARK: - Integration Example

/*
 
 Step 1: Add settings state to VideoRecorderView_Refactored
 ============================================================
 
 Add this near the top of your view:
 
 @State private var recordingSettings = VideoRecordingSettings.shared
 @State private var showingRecordingSettings = false
 
 
 Step 2: Add settings button to toolbar
 =======================================
 
 In your .toolbar modifier, add:
 
 ToolbarItem(placement: .topBarTrailing) {
     Button {
         showingRecordingSettings = true
     } label: {
         Image(systemName: "gearshape")
     }
 }
 
 
 Step 3: Add settings sheet
 ===========================
 
 Add this modifier to your view:
 
 .sheet(isPresented: $showingRecordingSettings) {
     VideoRecordingSettingsView()
 }
 
 
 Step 4: Replace NativeCameraView with AdvancedCameraView
 =========================================================
 
 Find where you use NativeCameraView and replace with:
 
 AdvancedCameraView(
     settings: recordingSettings,
     onVideoRecorded: { url in
         self.recordedVideoURL = url
         self.showingPlayResultOverlay = true
     },
     onCancel: {
         self.showingNativeCamera = false
     }
 )
 
 OR keep both options and let user choose:
 
 if useAdvancedRecording {
     AdvancedCameraView(...)
 } else {
     NativeCameraView(...)
 }
 
 
 Step 5: Show current settings in UI
 ====================================
 
 Add a settings indicator above or below your record button:
 
 HStack(spacing: 8) {
     Image(systemName: "video.fill")
         .foregroundStyle(.secondary)
     Text(recordingSettings.settingsDescription)
         .font(.caption)
         .foregroundStyle(.secondary)
     
     Button {
         showingRecordingSettings = true
     } label: {
         Image(systemName: "gearshape")
             .foregroundStyle(.blue)
     }
 }
 .padding(.horizontal)
 .padding(.vertical, 8)
 .background(.thinMaterial)
 .cornerRadius(20)
 
 
 Step 6: Display file size estimate
 ===================================
 
 Show estimated file size to help users:
 
 Text("Est. \(String(format: "%.0f", recordingSettings.estimatedFileSizePerMinute)) MB/min")
     .font(.caption2)
     .foregroundStyle(.secondary)
 
*/

// MARK: - Complete Integration Example

/// Example showing full integration with VideoRecorderView_Refactored
struct VideoRecorderView_WithSettings: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let athlete: Athlete?
    let game: Game?
    let practice: Practice?
    
    // Recording settings
    @State private var recordingSettings = VideoRecordingSettings.shared
    @State private var showingRecordingSettings = false
    @State private var showingNativeCamera = false
    @State private var recordedVideoURL: URL?
    @State private var showingPlayResultOverlay = false
    
    // Camera mode selection
    @State private var useAdvancedCamera = true
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header with context
                if let game = game {
                    VStack(spacing: 8) {
                        Text("Recording for Game")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("vs \(game.opponent)")
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    .padding()
                }
                
                Spacer()
                
                // Current settings display
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: recordingSettings.quality.systemIcon)
                            .font(.title2)
                            .foregroundStyle(.blue)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Recording Settings")
                                .font(.headline)
                            Text(recordingSettings.settingsDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button {
                            showingRecordingSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.title3)
                        }
                    }
                    .padding()
                    .background(.thinMaterial)
                    .cornerRadius(12)
                    
                    // File size estimate
                    HStack(spacing: 4) {
                        Image(systemName: "doc.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Estimated: \(String(format: "%.0f", recordingSettings.estimatedFileSizePerMinute)) MB per minute")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Main action buttons
                VStack(spacing: 16) {
                    Button {
                        showingNativeCamera = true
                    } label: {
                        Label("Start Recording", systemImage: "record.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    
                    // Camera mode toggle
                    Toggle("Advanced Camera Mode", isOn: $useAdvancedCamera)
                        .font(.subheadline)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Record Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingRecordingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingNativeCamera) {
            if useAdvancedCamera {
                // NEW: Advanced camera with full control
                AdvancedCameraView(
                    settings: recordingSettings,
                    onVideoRecorded: { url in
                        recordedVideoURL = url
                        showingNativeCamera = false
                        showingPlayResultOverlay = true
                    },
                    onCancel: {
                        showingNativeCamera = false
                    }
                )
            } else {
                // EXISTING: Simple native camera
                NativeCameraView(
                    videoQuality: .typeHigh,
                    onVideoRecorded: { url in
                        recordedVideoURL = url
                        showingNativeCamera = false
                        showingPlayResultOverlay = true
                    },
                    onCancel: {
                        showingNativeCamera = false
                    }
                )
            }
        }
        .sheet(isPresented: $showingRecordingSettings) {
            VideoRecordingSettingsView()
        }
        .sheet(isPresented: $showingPlayResultOverlay) {
            if let url = recordedVideoURL {
                // Your existing play result overlay
                PlayResultOverlayView(
                    videoURL: url,
                    athlete: athlete,
                    game: game,
                    practice: practice,
                    onSave: { playResult in
                        showingPlayResultOverlay = false
                        dismiss()
                    },
                    onCancel: {
                        showingPlayResultOverlay = false
                    }
                )
            }
        }
    }
}

// MARK: - Minimal Integration Example

/// Minimal example showing just the camera replacement
struct MinimalIntegrationExample: View {
    @State private var showingCamera = false
    @State private var recordedURL: URL?
    
    var body: some View {
        Button("Record") {
            showingCamera = true
        }
        .fullScreenCover(isPresented: $showingCamera) {
            AdvancedCameraView(
                settings: VideoRecordingSettings.shared,
                onVideoRecorded: { url in
                    recordedURL = url
                    showingCamera = false
                },
                onCancel: {
                    showingCamera = false
                }
            )
        }
    }
}

// MARK: - Settings Access Example

/// Example of accessing and using settings programmatically
struct SettingsAccessExample {
    
    func demonstrateSettingsAccess() {
        let settings = VideoRecordingSettings.shared
        
        // Read current values
        print("Quality: \(settings.quality.displayName)")
        print("Format: \(settings.format.displayName)")
        print("Frame Rate: \(settings.frameRate.displayName)")
        print("Slow-Motion: \(settings.slowMotionEnabled)")
        
        // Check capabilities
        if settings.isQualitySupported(.ultra4K) {
            print("✅ Device supports 4K")
        } else {
            print("❌ 4K not supported on this device")
        }
        
        // Get compatible frame rates
        let compatibleRates = settings.compatibleFrameRates(for: .high1080p)
        print("Compatible rates at 1080p: \(compatibleRates.map { $0.displayName })")
        
        // File size estimation
        let estimatedMB = settings.estimatedFileSizePerMinute
        print("Estimated file size: \(estimatedMB) MB/min")
        
        // Check slow-motion support
        if settings.supportsSlowMotion {
            print("✅ Slow-motion available at current frame rate")
        } else {
            print("❌ Need 120+ fps for slow-motion")
        }
        
        // Modify settings (automatically saves)
        settings.quality = .high1080p
        settings.frameRate = .fps60
        settings.format = .hevc
        
        // Reset to defaults
        settings.resetToDefaults()
    }
}

// MARK: - Integration Checklist

/*
 
 ✅ INTEGRATION CHECKLIST
 ========================
 
 [ ] 1. Add VideoRecordingSettings.swift to project
 [ ] 2. Add VideoRecordingSettingsView.swift to project
 [ ] 3. Add AdvancedCameraView.swift to project
 [ ] 4. Update ProfileView.swift with settings link (DONE ✅)
 [ ] 5. Add @State var recordingSettings to VideoRecorderView
 [ ] 6. Add @State var showingRecordingSettings to VideoRecorderView
 [ ] 7. Add settings button to toolbar
 [ ] 8. Add .sheet for VideoRecordingSettingsView
 [ ] 9. Replace or wrap NativeCameraView with AdvancedCameraView
 [ ] 10. Test recording at different qualities
 [ ] 11. Test slow-motion at 120+ fps
 [ ] 12. Verify settings persist across app restarts
 [ ] 13. Check file sizes match estimates
 [ ] 14. Test on physical device (camera features)
 
*/

// MARK: - Preview

#Preview("Full Integration") {
    VideoRecorderView_WithSettings(
        athlete: nil,
        game: nil,
        practice: nil
    )
}

#Preview("Minimal Integration") {
    MinimalIntegrationExample()
}
