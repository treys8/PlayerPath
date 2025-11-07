import Foundation
import AVFoundation

@MainActor
enum PermissionStatus {
    case granted
    case denied
    case restricted
}

@MainActor
struct RecorderPermissions {
    /// Check/request camera and microphone permissions in sequence.
    /// - Parameters:
    ///   - context: A human-readable context string for ErrorHandlerService.
    ///   - autoReport: If true, reports denials to ErrorHandlerService.
    /// - Returns: `.granted` only if both camera and microphone are authorized; otherwise `.denied` or `.restricted`.
    static func ensureCapturePermissions(context: String = "VideoRecorder", autoReport: Bool = true) async -> PermissionStatus {
        let camera = await requestCameraPermission()
        if camera != .granted {
            if autoReport { reportPermissionFailure(camera, context: context, resource: "Camera") }
            return camera
        }
        let mic = await requestMicrophonePermission()
        if mic != .granted {
            if autoReport { reportPermissionFailure(mic, context: context, resource: "Microphone") }
            return mic
        }
        return .granted
    }

    /// Request camera permission if needed, or return current status.
    static func requestCameraPermission() async -> PermissionStatus {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return .granted
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            return granted ? .granted : .denied
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .denied
        }
    }

    /// Request microphone permission if needed, or return current status.
    static func requestMicrophonePermission() async -> PermissionStatus {
        let status = AVAudioSession.sharedInstance().recordPermission
        switch status {
        case .granted:
            return .granted
        case .undetermined:
            let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                    continuation.resume(returning: allowed)
                }
            }
            return granted ? .granted : .denied
        case .denied:
            return .denied
        @unknown default:
            return .denied
        }
    }

    /// Optionally route permission failures through ErrorHandlerService for consistent UX.
    private static func reportPermissionFailure(_ status: PermissionStatus, context: String, resource: String) {
        let error: PlayerPathError
        switch status {
        case .denied:
            // Map to authenticationRequired to encourage user action (open Settings, etc.)
            error = .authenticationRequired
        case .restricted:
            // Use unknownError with a specific message for parental/device restrictions.
            error = .unknownError("\(resource) access is restricted on this device.")
        case .granted:
            return
        }
        ErrorHandlerService.shared.handle(
            error,
            context: context,
            severity: .high,
            canRetry: false,
            autoRetry: false,
            userInfo: ["resource": resource]
        )
    }
}
