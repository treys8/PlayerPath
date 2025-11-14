//
//  CameraPermissionManager.swift
//  PlayerPath
//
//  Manages camera and microphone permissions with async/await support
//

import AVFoundation
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.app", category: "CameraPermissionManager")

@MainActor
final class CameraPermissionManager: ObservableObject {
    
    enum PermissionStatus {
        case authorized
        case denied(message: String)
        case restricted(message: String)
        case notDetermined
    }
    
    enum PermissionResult {
        case success
        case failure(message: String)
    }
    
    // MARK: - Status Checks
    
    static func cameraStatus() -> PermissionStatus {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return .authorized
        case .denied:
            return .denied(message: "Camera access is required to record videos. Please enable camera access in Settings.")
        case .restricted:
            return .restricted(message: "Camera access is restricted on this device.")
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied(message: "Unknown camera permission status.")
        }
    }
    
    static func microphoneStatus() -> PermissionStatus {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return .authorized
        case .denied:
            return .denied(message: "Microphone access is required to record videos with audio. Please enable microphone access in Settings.")
        case .restricted:
            return .restricted(message: "Microphone access is restricted on this device.")
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied(message: "Unknown microphone permission status.")
        }
    }
    
    // MARK: - Request Permissions
    
    static func requestCameraPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            logger.info("Requesting camera permission...")
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            logger.info("Camera permission result: \(granted)")
            return granted
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
    
    static func requestMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            logger.info("Requesting microphone permission...")
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            logger.info("Microphone permission result: \(granted)")
            return granted
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
    
    // MARK: - Combined Check
    
    static func checkAndRequestAllPermissions() async -> PermissionResult {
        let cameraGranted = await requestCameraPermission()
        let microphoneGranted = await requestMicrophonePermission()
        
        if cameraGranted && microphoneGranted {
            return .success
        } else if !cameraGranted {
            let status = cameraStatus()
            switch status {
            case .denied(let message), .restricted(let message):
                return .failure(message: message)
            default:
                return .failure(message: "Camera permission was not granted.")
            }
        } else {
            let status = microphoneStatus()
            switch status {
            case .denied(let message), .restricted(let message):
                return .failure(message: message)
            default:
                return .failure(message: "Microphone permission was not granted.")
            }
        }
    }
    
    // MARK: - Utilities
    
    static func openSettings() {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
        }
    }
}
