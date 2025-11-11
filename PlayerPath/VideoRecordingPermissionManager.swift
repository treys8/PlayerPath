//
//  VideoRecordingPermissionManager.swift
//  PlayerPath
//
//  Created by Assistant on 10/27/25.
//

import AVFoundation
import UIKit
import Combine

@MainActor
class VideoRecordingPermissionManager: ObservableObject {
    @Published var isRequestingPermissions = false
    @Published var permissionAlertMessage = ""
    @Published var showingPermissionAlert = false
    
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
        print("PermissionManager: Checking camera and microphone permissions...")
        
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        
        print("PermissionManager: Camera status: \(cameraStatus.rawValue), Microphone status: \(microphoneStatus.rawValue)")
        
        // Check if both permissions are already granted
        if cameraStatus == .authorized && microphoneStatus == .authorized {
            print("PermissionManager: Both permissions authorized")
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
        print("PermissionManager: Requesting permissions...")
        
        isRequestingPermissions = true
        defer { isRequestingPermissions = false }
        
        var cameraGranted = false
        var microphoneGranted = false
        
        // Request camera permission first
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if cameraStatus == .notDetermined {
            print("PermissionManager: Requesting camera permission...")
            cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
            print("PermissionManager: Camera permission result: \(cameraGranted)")
        } else {
            cameraGranted = (cameraStatus == .authorized)
        }
        
        // Request microphone permission
        let microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if microphoneStatus == .notDetermined {
            print("PermissionManager: Requesting microphone permission...")
            microphoneGranted = await AVCaptureDevice.requestAccess(for: .audio)
            print("PermissionManager: Microphone permission result: \(microphoneGranted)")
        } else {
            microphoneGranted = (microphoneStatus == .authorized)
        }
        
        print("PermissionManager: Final results - Camera: \(cameraGranted), Microphone: \(microphoneGranted)")
        
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
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
        }
    }
}