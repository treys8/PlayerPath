//
//  NativeCameraView.swift
//  PlayerPath
//
//  Created by Assistant on 11/11/25.
//

import SwiftUI
import UIKit
import AVFoundation
import CoreMedia

// MARK: - Camera Host Controller

/// A custom UIViewController that hosts UIImagePickerController and allows all orientations
class CameraHostController: UIViewController {
    var picker: UIImagePickerController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        guard let picker = picker else { return }
        
        // Present picker after view loads
        DispatchQueue.main.async {
            self.present(picker, animated: false)
        }
    }
    
    // KEY: Allow all orientations for camera recording
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .allButUpsideDown
    }
    
    override var shouldAutorotate: Bool {
        return true
    }
}

// MARK: - Native Camera View

/// A SwiftUI wrapper around UIImagePickerController for recording videos with proper orientation support.
/// This view handles landscape and portrait recording, fixing video orientation metadata automatically.
struct NativeCameraView: UIViewControllerRepresentable {
    let videoQuality: UIImagePickerController.QualityType
    let onVideoRecorded: (URL) -> Void
    let onCancel: () -> Void
    
    func makeUIViewController(context: Context) -> CameraHostController {
        let hostController = CameraHostController()
        
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.mediaTypes = ["public.movie"]
        picker.videoQuality = videoQuality
        picker.videoMaximumDuration = 600 // 10 minutes max
        
        // KEY FIX #1: Allow all orientations for camera
        picker.modalPresentationStyle = .fullScreen
        
        // KEY FIX #2: Set camera capture mode to video
        picker.cameraCaptureMode = .video
        
        // KEY FIX #3: Disable editing to prevent orientation locks
        picker.allowsEditing = false
        
        #if DEBUG
        print("🎥 NativeCameraView: Initialized with quality: \(videoQuality.rawValue)")
        #endif
        
        // Store picker in host controller
        hostController.picker = picker
        
        return hostController
    }
    
    func updateUIViewController(_ uiViewController: CameraHostController, context: Context) {
        // Update handled by host controller
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onVideoRecorded: onVideoRecorded, onCancel: onCancel)
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onVideoRecorded: (URL) -> Void
        let onCancel: () -> Void
        
        init(onVideoRecorded: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onVideoRecorded = onVideoRecorded
            self.onCancel = onCancel
            super.init()
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            #if DEBUG
            print("🎥 NativeCameraView: Video recording finished")
            #endif
            
            guard let videoURL = info[.mediaURL] as? URL else {
                print("❌ NativeCameraView: No video URL found in picker info")
                onCancel()
                return
            }
            
            #if DEBUG
            print("🎥 NativeCameraView: Original video URL: \(videoURL.path)")
            #endif
            
            // KEY FIX #4: Fix orientation metadata before passing to app
            fixVideoOrientation(at: videoURL) { fixedURL in
                if let fixed = fixedURL {
                    #if DEBUG
                    print("✅ NativeCameraView: Video orientation fixed: \(fixed.path)")
                    #endif
                    self.onVideoRecorded(fixed)
                } else {
                    #if DEBUG
                    print("⚠️ NativeCameraView: Using original video (orientation fix failed or not needed)")
                    #endif
                    // Fallback to original if fix fails
                    self.onVideoRecorded(videoURL)
                }
            }
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            #if DEBUG
            print("🎥 NativeCameraView: Recording cancelled by user")
            #endif
            onCancel()
        }
        
        // MARK: - Orientation Fix
        
        /// KEY FIX #5: Fix video orientation metadata for landscape recordings
        /// This ensures videos recorded in landscape display correctly when played back
        private func fixVideoOrientation(at url: URL, completion: @escaping (URL?) -> Void) {
            Task {
                do {
                    let asset = AVURLAsset(url: url)
                    
                    // Load tracks asynchronously (modern API)
                    let videoTracks = try await asset.loadTracks(withMediaType: .video)
                    guard let videoTrack = videoTracks.first else {
                        #if DEBUG
                        print("⚠️ NativeCameraView: No video track found, cannot fix orientation")
                        #endif
                        await MainActor.run { completion(nil) }
                        return
                    }
                    
                    // Load transform and duration (modern API)
                    let transform = try await videoTrack.load(.preferredTransform)
                    let duration = try await asset.load(.duration)
                    
                    // Check current orientation via transform matrix
                    let videoAngle = atan2(transform.b, transform.a) * 180 / .pi
                    
                    #if DEBUG
                    print("🎥 NativeCameraView: Video angle: \(videoAngle)°")
                    print("🎥 NativeCameraView: Transform: \(transform)")
                    #endif
                    
                    // If video is already in portrait orientation (0° or 180°), no fix needed
                    if abs(videoAngle) < 1.0 || abs(videoAngle - 180) < 1.0 {
                        #if DEBUG
                        print("✅ NativeCameraView: Video is portrait, no orientation fix needed")
                        #endif
                        await MainActor.run { completion(url) }
                        return
                    }
                    
                    #if DEBUG
                    print("🔄 NativeCameraView: Fixing landscape video orientation...")
                    #endif
                    
                    // Create composition with corrected orientation
                    let composition = AVMutableComposition()
                    
                    guard let compositionVideoTrack = composition.addMutableTrack(
                        withMediaType: .video,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    ) else {
                        #if DEBUG
                        print("❌ NativeCameraView: Failed to create composition video track")
                        #endif
                        await MainActor.run { completion(nil) }
                        return
                    }
                    
                    // Copy video track timing
                    try compositionVideoTrack.insertTimeRange(
                        CMTimeRange(start: .zero, duration: duration),
                        of: videoTrack,
                        at: .zero
                    )
                    
                    // Apply correct transform for landscape
                    compositionVideoTrack.preferredTransform = transform
                    
                    // Handle audio track if present
                    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
                    if let audioTrack = audioTracks.first,
                       let compositionAudioTrack = composition.addMutableTrack(
                           withMediaType: .audio,
                           preferredTrackID: kCMPersistentTrackID_Invalid
                       ) {
                        try compositionAudioTrack.insertTimeRange(
                            CMTimeRange(start: .zero, duration: duration),
                            of: audioTrack,
                            at: .zero
                        )
                        #if DEBUG
                        print("✅ NativeCameraView: Audio track copied")
                        #endif
                    }
                    
                    // Export with corrected orientation
                    let outputURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("fixed_\(UUID().uuidString).mov")
                    
                    guard let exportSession = AVAssetExportSession(
                        asset: composition,
                        presetName: AVAssetExportPresetHighestQuality
                    ) else {
                        #if DEBUG
                        print("❌ NativeCameraView: Failed to create export session")
                        #endif
                        await MainActor.run { completion(nil) }
                        return
                    }
                    
                    exportSession.shouldOptimizeForNetworkUse = true
                    
                    #if DEBUG
                    print("🔄 NativeCameraView: Exporting fixed video...")
                    #endif
                    
                    // Use modern async export API (iOS 18+)
                    do {
                        try await exportSession.export(to: outputURL, as: .mov)
                        
                        await MainActor.run {
                            #if DEBUG
                            print("✅ NativeCameraView: Export completed successfully")
                            #endif
                            // Clean up original file to save space
                            try? FileManager.default.removeItem(at: url)
                            completion(outputURL)
                        }
                    } catch {
                        await MainActor.run {
                            #if DEBUG
                            print("❌ NativeCameraView: Export failed: \(error.localizedDescription)")
                            #endif
                            completion(nil)
                        }
                    }
                    
                } catch {
                    #if DEBUG
                    print("❌ NativeCameraView: Error fixing video orientation: \(error.localizedDescription)")
                    #endif
                    await MainActor.run { completion(nil) }
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct NativeCameraView_Previews: PreviewProvider {
    static var previews: some View {
        NativeCameraView(
            videoQuality: .typeHigh,
            onVideoRecorded: { url in
                print("Preview: Video recorded at \(url)")
            },
            onCancel: {
                print("Preview: Recording cancelled")
            }
        )
    }
}
#endif
