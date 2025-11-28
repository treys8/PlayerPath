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

/// Errors that can occur during camera recording
enum NativeCameraError: LocalizedError {
    case noVideoURL
    case orientationFixFailed
    case exportFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .noVideoURL:
            return "No video URL found in recording"
        case .orientationFixFailed:
            return "Failed to fix video orientation"
        case .exportFailed(let error):
            return "Export failed: \(error.localizedDescription)"
        }
    }
}

/// A SwiftUI wrapper around UIImagePickerController for recording videos with proper orientation support.
/// This view handles landscape and portrait recording, fixing video orientation metadata automatically.
struct NativeCameraView: UIViewControllerRepresentable {
    // MARK: - Constants

    private enum Constants {
        static let defaultMaxDuration: TimeInterval = 600 // 10 minutes
        static let orientationAngleTolerance: Double = 1.0 // Degrees
    }

    let videoQuality: UIImagePickerController.QualityType
    let maxDuration: TimeInterval
    let enableFlash: Bool
    let cameraDevice: UIImagePickerController.CameraDevice
    let onVideoRecorded: (URL) -> Void
    let onCancel: () -> Void
    let onError: ((Error) -> Void)?

    init(
        videoQuality: UIImagePickerController.QualityType = .typeHigh,
        maxDuration: TimeInterval = Constants.defaultMaxDuration,
        enableFlash: Bool = false,
        cameraDevice: UIImagePickerController.CameraDevice = .rear,
        onVideoRecorded: @escaping (URL) -> Void,
        onCancel: @escaping () -> Void,
        onError: ((Error) -> Void)? = nil
    ) {
        self.videoQuality = videoQuality
        self.maxDuration = maxDuration
        self.enableFlash = enableFlash
        self.cameraDevice = cameraDevice
        self.onVideoRecorded = onVideoRecorded
        self.onCancel = onCancel
        self.onError = onError
    }
    
    func makeUIViewController(context: Context) -> CameraHostController {
        let hostController = CameraHostController()
        
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.mediaTypes = ["public.movie"]
        picker.videoQuality = videoQuality
        picker.videoMaximumDuration = maxDuration
        
        // KEY FIX #1: Allow all orientations for camera
        picker.modalPresentationStyle = .fullScreen
        
        // KEY FIX #2: Set camera capture mode to video
        picker.cameraCaptureMode = .video
        
        // KEY FIX #3: Disable editing to prevent orientation locks
        picker.allowsEditing = false
        
        // Set camera device (front/rear)
        if UIImagePickerController.isCameraDeviceAvailable(cameraDevice) {
            picker.cameraDevice = cameraDevice
        }
        
        // Enable flash if requested and available
        if enableFlash && UIImagePickerController.isFlashAvailable(for: cameraDevice) {
            picker.cameraFlashMode = .on
        } else {
            picker.cameraFlashMode = .off
        }
        
        #if DEBUG
        print("🎥 NativeCameraView: Initialized")
        print("   Quality: \(videoQuality.rawValue)")
        print("   Max Duration: \(maxDuration)s")
        print("   Camera: \(cameraDevice == .rear ? "Rear" : "Front")")
        print("   Flash: \(enableFlash ? "On" : "Off")")
        #endif
        
        // Store picker in host controller
        hostController.picker = picker
        
        return hostController
    }
    
    func updateUIViewController(_ uiViewController: CameraHostController, context: Context) {
        // Update handled by host controller
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(
            onVideoRecorded: onVideoRecorded,
            onCancel: onCancel,
            onError: onError
        )
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onVideoRecorded: (URL) -> Void
        let onCancel: () -> Void
        let onError: ((Error) -> Void)?
        
        init(
            onVideoRecorded: @escaping (URL) -> Void,
            onCancel: @escaping () -> Void,
            onError: ((Error) -> Void)? = nil
        ) {
            self.onVideoRecorded = onVideoRecorded
            self.onCancel = onCancel
            self.onError = onError
            super.init()
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            #if DEBUG
            print("🎥 NativeCameraView: Video recording finished")
            #endif
            
            guard let videoURL = info[.mediaURL] as? URL else {
                #if DEBUG
                print("❌ NativeCameraView: No video URL found in picker info")
                #endif
                onError?(NativeCameraError.noVideoURL)
                onCancel()
                return
            }
            
            #if DEBUG
            print("🎥 NativeCameraView: Original video URL: \(videoURL.path)")
            #endif
            
            // KEY FIX #4: Fix orientation metadata before passing to app
            fixVideoOrientation(at: videoURL) { [weak self] fixedURL in
                guard let self = self else { return }
                
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
            // Capture error handler to avoid retain cycle
            let errorHandler = self.onError

            Task {
                do {
                    let asset = AVURLAsset(url: url)

                    // Load tracks asynchronously (modern API)
                    let videoTracks = try await asset.loadTracks(withMediaType: .video)
                    guard let videoTrack = videoTracks.first else {
                        #if DEBUG
                        print("⚠️ NativeCameraView: No video track found, cannot fix orientation")
                        #endif
                        await MainActor.run {
                            errorHandler?(NativeCameraError.orientationFixFailed)
                            completion(nil)
                        }
                        return
                    }
                    
                    // Load transform and duration (modern API)
                    let transform = try await videoTrack.load(.preferredTransform)
                    let duration = try await asset.load(.duration)
                    let naturalSize = try await videoTrack.load(.naturalSize)
                    
                    // Check current orientation via transform matrix
                    let videoAngle = atan2(transform.b, transform.a) * 180 / .pi
                    
                    #if DEBUG
                    print("🎥 NativeCameraView: Video metadata:")
                    print("   Angle: \(videoAngle)°")
                    print("   Transform: \(transform)")
                    print("   Size: \(naturalSize)")
                    print("   Duration: \(duration.seconds)s")
                    #endif
                    
                    // If video is already in portrait orientation (0° or 180°), no fix needed
                    if abs(videoAngle) < Constants.orientationAngleTolerance || abs(videoAngle - 180) < Constants.orientationAngleTolerance {
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
                        await MainActor.run {
                            errorHandler?(NativeCameraError.orientationFixFailed)
                            completion(nil)
                        }
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
                        await MainActor.run {
                            errorHandler?(NativeCameraError.orientationFixFailed)
                            completion(nil)
                        }
                        return
                    }
                    
                    exportSession.outputURL = outputURL
                    exportSession.outputFileType = .mov
                    exportSession.shouldOptimizeForNetworkUse = true
                    
                    #if DEBUG
                    print("🔄 NativeCameraView: Exporting fixed video...")
                    #endif
                    
                    // Use fallback export API for all iOS versions (iOS 18 API verification needed)
                    await exportSession.export()

                    await MainActor.run {
                        switch exportSession.status {
                        case .completed:
                            #if DEBUG
                            print("✅ NativeCameraView: Export completed successfully")
                            #endif
                            // IMPORTANT: Don't delete original file here - let caller handle cleanup
                            // after they've successfully saved the video to prevent data loss
                            completion(outputURL)

                        case .failed:
                            #if DEBUG
                            print("❌ NativeCameraView: Export failed: \(exportSession.error?.localizedDescription ?? "Unknown error")")
                            #endif
                            // Clean up failed export file
                            try? FileManager.default.removeItem(at: outputURL)

                            if let error = exportSession.error {
                                errorHandler?(NativeCameraError.exportFailed(error))
                            }
                            completion(nil)

                        case .cancelled:
                            #if DEBUG
                            print("⚠️ NativeCameraView: Export cancelled")
                            #endif
                            // Clean up cancelled export file
                            try? FileManager.default.removeItem(at: outputURL)
                            completion(nil)

                        default:
                            #if DEBUG
                            print("⚠️ NativeCameraView: Export ended with unknown status")
                            #endif
                            // Clean up on unknown status
                            try? FileManager.default.removeItem(at: outputURL)
                            completion(nil)
                        }
                    }
                    
                } catch {
                    #if DEBUG
                    print("❌ NativeCameraView: Error fixing video orientation: \(error.localizedDescription)")
                    #endif
                    await MainActor.run {
                        errorHandler?(NativeCameraError.exportFailed(error))
                        completion(nil)
                    }
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
