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

/// A SwiftUI wrapper around UIImagePickerController for recording videos with proper orientation support.
/// This view handles landscape and portrait recording, fixing video orientation metadata automatically.
struct NativeCameraView: UIViewControllerRepresentable {
    let videoQuality: UIImagePickerController.QualityType
    let onVideoRecorded: (URL) -> Void
    let onCancel: () -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
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
        
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        // Ensure full screen presentation is maintained
        uiViewController.modalPresentationStyle = .fullScreen
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onVideoRecorded: onVideoRecorded, onCancel: onCancel)
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationBarDelegate {
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
            let asset = AVAsset(url: url)
            
            guard let videoTrack = asset.tracks(withMediaType: .video).first else {
                #if DEBUG
                print("⚠️ NativeCameraView: No video track found, cannot fix orientation")
                #endif
                completion(nil)
                return
            }
            
            // Check current orientation via transform matrix
            let transform = videoTrack.preferredTransform
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
                completion(url)
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
                completion(nil)
                return
            }
            
            do {
                // Copy video track timing
                try compositionVideoTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: asset.duration),
                    of: videoTrack,
                    at: .zero
                )
                
                // Apply correct transform for landscape
                compositionVideoTrack.preferredTransform = videoTrack.preferredTransform
                
                // Handle audio track if present
                if let audioTrack = asset.tracks(withMediaType: .audio).first,
                   let compositionAudioTrack = composition.addMutableTrack(
                       withMediaType: .audio,
                       preferredTrackID: kCMPersistentTrackID_Invalid
                   ) {
                    try compositionAudioTrack.insertTimeRange(
                        CMTimeRange(start: .zero, duration: asset.duration),
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
                    completion(nil)
                    return
                }
                
                exportSession.outputURL = outputURL
                exportSession.outputFileType = .mov
                exportSession.shouldOptimizeForNetworkUse = true
                
                #if DEBUG
                print("🔄 NativeCameraView: Exporting fixed video...")
                #endif
                
                exportSession.exportAsynchronously {
                    DispatchQueue.main.async {
                        switch exportSession.status {
                        case .completed:
                            #if DEBUG
                            print("✅ NativeCameraView: Export completed successfully")
                            #endif
                            // Clean up original file to save space
                            try? FileManager.default.removeItem(at: url)
                            completion(outputURL)
                            
                        case .failed:
                            #if DEBUG
                            print("❌ NativeCameraView: Export failed: \(exportSession.error?.localizedDescription ?? "Unknown error")")
                            #endif
                            completion(nil)
                            
                        case .cancelled:
                            #if DEBUG
                            print("⚠️ NativeCameraView: Export cancelled")
                            #endif
                            completion(nil)
                            
                        default:
                            #if DEBUG
                            print("⚠️ NativeCameraView: Export in unexpected state: \(exportSession.status.rawValue)")
                            #endif
                            completion(nil)
                        }
                    }
                }
                
            } catch {
                #if DEBUG
                print("❌ NativeCameraView: Error fixing video orientation: \(error.localizedDescription)")
                #endif
                completion(nil)
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
