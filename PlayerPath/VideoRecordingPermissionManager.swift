//
//  VideoRecordingPermissionManager.swift
//  PlayerPath
//
//  Created by Assistant on 10/27/25.
//

import AVFoundation
import UIKit
import Combine
import os

@MainActor
class VideoRecordingPermissionManager: ObservableObject {
    @Published var isRequestingPermissions = false
    @Published var permissionAlertMessage = ""
    @Published var showingPermissionAlert = false

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.playerpath", category: "PermissionManager")
    
    enum PermissionState {
        case authorized
        case denied(String)
        case restricted(String)
        case needsRequest
    }
    
    enum PermissionError: LocalizedError {
        case cameraNotAvailable
        case microphoneNotAvailable
        case cameraRestricted
        case microphoneRestricted
        
        var errorDescription: String? {
            switch self {
            case .cameraNotAvailable:
                return "Camera is not available on this device."
            case .microphoneNotAvailable:
                return "Microphone is not available on this device."
            case .cameraRestricted:
                return "Camera access is restricted. Please check your device settings."
            case .microphoneRestricted:
                return "Microphone access is restricted. Please check your device settings."
            }
        }
    }
    
    func checkPermissions() async -> Result<Void, PermissionError> {
        Self.logger.info("Checking camera and microphone permissions")

        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        Self.logger.debug("Camera status: \(cameraStatus.rawValue), Microphone status: \(microphoneStatus.rawValue)")

        // Check if both permissions are already granted
        if cameraStatus == .authorized && microphoneStatus == .authorized {
            Self.logger.info("Both permissions authorized")
            return .success(())
        }
        
        // Check for denied/restricted permissions
        if cameraStatus == .denied || cameraStatus == .restricted {
            let message = "Camera access is required to record videos. Please enable camera access in Settings."
            await showPermissionAlert(message: message)
            return .failure(.cameraRestricted)
        }
        
        if microphoneStatus == .denied || microphoneStatus == .restricted {
            let message = "Microphone access is required to record videos with audio. Please enable microphone access in Settings."
            await showPermissionAlert(message: message)
            return .failure(.microphoneRestricted)
        }
        
        // Request permissions that are not determined
        return await requestPermissions()
    }
    
    private func requestPermissions() async -> Result<Void, PermissionError> {
        Self.logger.info("Requesting permissions")

        isRequestingPermissions = true
        defer { isRequestingPermissions = false }

        // Request camera permission
        Self.logger.debug("Requesting camera permission")
        let cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
        Self.logger.debug("Camera permission result: \(cameraGranted)")

        // Request microphone permission
        Self.logger.debug("Requesting microphone permission")
        let microphoneGranted = await AVCaptureDevice.requestAccess(for: .audio)
        Self.logger.debug("Microphone permission result: \(microphoneGranted)")

        Self.logger.info("Final results - Camera: \(cameraGranted), Microphone: \(microphoneGranted)")
        
        if cameraGranted && microphoneGranted {
            return .success(())
        } else if !cameraGranted {
            let message = "Camera access is required to record videos. Please enable camera access in Settings."
            await showPermissionAlert(message: message)
            return .failure(.cameraNotAvailable)
        } else {
            let message = "Microphone access is required to record videos with audio. Please enable microphone access in Settings."
            await showPermissionAlert(message: message)
            return .failure(.microphoneNotAvailable)
        }
    }
    
    private func showPermissionAlert(message: String) async {
        permissionAlertMessage = message
        showingPermissionAlert = true
    }
    
    func openSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            Self.logger.error("Failed to create settings URL")
            return
        }

        UIApplication.shared.open(settingsURL) { success in
            if success {
                Self.logger.info("Successfully opened Settings")
            } else {
                Self.logger.error("Failed to open Settings")
            }
        }
    }
}