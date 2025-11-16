//
//  VideoRecordingSettings.swift
//  PlayerPath
//
//  Created by Assistant on 11/13/25.
//

import Foundation
import AVFoundation
import SwiftUI

// MARK: - Video Recording Settings Model

/// Stores user preferences for video recording quality, format, frame rate, and slow-motion
@Observable
final class VideoRecordingSettings {
    
    // MARK: - Singleton
    
    static let shared = VideoRecordingSettings()
    
    // MARK: - Settings Properties
    
    /// Video quality/resolution
    var quality: RecordingQuality {
        didSet {
            saveSettings()
        }
    }
    
    /// Video format (codec)
    var format: VideoFormat {
        didSet {
            saveSettings()
        }
    }
    
    /// Frame rate for recording
    var frameRate: FrameRate {
        didSet {
            saveSettings()
        }
    }
    
    /// Whether to enable slow-motion recording
    var slowMotionEnabled: Bool {
        didSet {
            saveSettings()
        }
    }
    
    /// Audio recording enabled
    var audioEnabled: Bool {
        didSet {
            saveSettings()
        }
    }
    
    /// Video stabilization preference
    var stabilizationMode: StabilizationMode {
        didSet {
            saveSettings()
        }
    }
    
    // MARK: - UserDefaults Keys
    
    private enum Keys {
        static let quality = "videoRecordingQuality"
        static let format = "videoRecordingFormat"
        static let frameRate = "videoRecordingFrameRate"
        static let slowMotionEnabled = "videoRecordingSlowMotion"
        static let audioEnabled = "videoRecordingAudio"
        static let stabilizationMode = "videoRecordingStabilization"
    }
    
    // MARK: - Initialization
    
    private init() {
        // Load saved settings or use defaults
        if let qualityRaw = UserDefaults.standard.string(forKey: Keys.quality),
           let savedQuality = RecordingQuality(rawValue: qualityRaw) {
            self.quality = savedQuality
        } else {
            self.quality = .high1080p
        }
        
        if let formatRaw = UserDefaults.standard.string(forKey: Keys.format),
           let savedFormat = VideoFormat(rawValue: formatRaw) {
            self.format = savedFormat
        } else {
            self.format = .hevc
        }
        
        if let frameRateRaw = UserDefaults.standard.string(forKey: Keys.frameRate),
           let savedFrameRate = FrameRate(rawValue: frameRateRaw) {
            self.frameRate = savedFrameRate
        } else {
            self.frameRate = .fps30
        }
        
        self.slowMotionEnabled = UserDefaults.standard.bool(forKey: Keys.slowMotionEnabled)
        
        // Audio defaults to true
        if UserDefaults.standard.object(forKey: Keys.audioEnabled) == nil {
            self.audioEnabled = true
        } else {
            self.audioEnabled = UserDefaults.standard.bool(forKey: Keys.audioEnabled)
        }
        
        if let stabRaw = UserDefaults.standard.string(forKey: Keys.stabilizationMode),
           let savedStab = StabilizationMode(rawValue: stabRaw) {
            self.stabilizationMode = savedStab
        } else {
            self.stabilizationMode = .auto
        }
    }
    
    // MARK: - Persistence
    
    private func saveSettings() {
        UserDefaults.standard.set(quality.rawValue, forKey: Keys.quality)
        UserDefaults.standard.set(format.rawValue, forKey: Keys.format)
        UserDefaults.standard.set(frameRate.rawValue, forKey: Keys.frameRate)
        UserDefaults.standard.set(slowMotionEnabled, forKey: Keys.slowMotionEnabled)
        UserDefaults.standard.set(audioEnabled, forKey: Keys.audioEnabled)
        UserDefaults.standard.set(stabilizationMode.rawValue, forKey: Keys.stabilizationMode)
        
        #if DEBUG
        print("💾 Video recording settings saved")
        #endif
    }
    
    // MARK: - Reset to Defaults
    
    func resetToDefaults() {
        quality = .high1080p
        format = .hevc
        frameRate = .fps30
        slowMotionEnabled = false
        audioEnabled = true
        stabilizationMode = .auto
        
        #if DEBUG
        print("🔄 Video recording settings reset to defaults")
        #endif
    }
    
    // MARK: - Computed Properties
    
    /// Estimated file size per minute of video (in MB)
    var estimatedFileSizePerMinute: Double {
        let baseSize = quality.estimatedMBPerMinute
        let formatMultiplier = format == .hevc ? 0.7 : 1.0 // HEVC is ~30% more efficient
        let frameRateMultiplier = frameRate.multiplier
        
        return baseSize * formatMultiplier * frameRateMultiplier
    }
    
    /// Whether the current settings support slow-motion recording
    var supportsSlowMotion: Bool {
        // Slow-motion requires high frame rates
        return frameRate.fps >= 120
    }
    
    /// Human-readable description of current settings
    var settingsDescription: String {
        var components: [String] = []
        components.append(quality.displayName)
        components.append(format.displayName)
        components.append(frameRate.displayName)
        if slowMotionEnabled {
            components.append("Slow-Mo")
        }
        return components.joined(separator: " • ")
    }
}

// MARK: - Video Quality

enum RecordingQuality: String, CaseIterable, Identifiable {
    case low480p = "480p"
    case medium720p = "720p"
    case high1080p = "1080p"
    case ultra4K = "4K"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .low480p: return "SD (480p)"
        case .medium720p: return "HD (720p)"
        case .high1080p: return "Full HD (1080p)"
        case .ultra4K: return "4K Ultra HD"
        }
    }
    
    var resolution: CGSize {
        switch self {
        case .low480p: return CGSize(width: 854, height: 480)
        case .medium720p: return CGSize(width: 1280, height: 720)
        case .high1080p: return CGSize(width: 1920, height: 1080)
        case .ultra4K: return CGSize(width: 3840, height: 2160)
        }
    }
    
    var avPreset: AVCaptureSession.Preset {
        switch self {
        case .low480p: return .vga640x480
        case .medium720p: return .hd1280x720
        case .high1080p: return .hd1920x1080
        case .ultra4K: return .hd4K3840x2160
        }
    }
    
    /// Estimated file size in MB per minute of video
    var estimatedMBPerMinute: Double {
        switch self {
        case .low480p: return 8.0
        case .medium720p: return 25.0
        case .high1080p: return 60.0
        case .ultra4K: return 200.0
        }
    }
    
    var systemIcon: String {
        switch self {
        case .low480p: return "rectangle.compress.vertical"
        case .medium720p: return "rectangle"
        case .high1080p: return "rectangle.expand.vertical"
        case .ultra4K: return "4k.tv"
        }
    }
    
    var description: String {
        switch self {
        case .low480p: return "Best for sharing and storage"
        case .medium720p: return "Good quality, smaller files"
        case .high1080p: return "High quality, recommended"
        case .ultra4K: return "Maximum quality, large files"
        }
    }
}

// MARK: - Video Format

enum VideoFormat: String, CaseIterable, Identifiable {
    case hevc = "HEVC"
    case h264 = "H.264"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .hevc: return "HEVC (H.265)"
        case .h264: return "H.264"
        }
    }
    
    var codec: AVVideoCodecType {
        switch self {
        case .hevc: return .hevc
        case .h264: return .h264
        }
    }
    
    var fileExtension: String {
        return "mov" // Both codecs can use MOV container
    }
    
    var systemIcon: String {
        switch self {
        case .hevc: return "arrow.down.circle"
        case .h264: return "arrow.left.arrow.right.circle"
        }
    }
    
    var description: String {
        switch self {
        case .hevc: return "Better compression, smaller files"
        case .h264: return "Maximum compatibility"
        }
    }
}

// MARK: - Frame Rate

enum FrameRate: String, CaseIterable, Identifiable {
    case fps24 = "24"
    case fps30 = "30"
    case fps60 = "60"
    case fps120 = "120"
    case fps240 = "240"
    
    var id: String { rawValue }
    
    var displayName: String {
        return "\(rawValue) fps"
    }
    
    var fps: Int {
        return Int(rawValue) ?? 30
    }
    
    var cmTime: CMTime {
        return CMTime(value: 1, timescale: CMTimeScale(fps))
    }
    
    /// File size multiplier relative to 30fps
    var multiplier: Double {
        let baseFPS: Double = 30.0
        return Double(fps) / baseFPS
    }
    
    var systemIcon: String {
        switch self {
        case .fps24: return "film"
        case .fps30: return "video"
        case .fps60: return "video.badge.checkmark"
        case .fps120, .fps240: return "video.badge.waveform"
        }
    }
    
    var description: String {
        switch self {
        case .fps24: return "Cinematic look"
        case .fps30: return "Standard video"
        case .fps60: return "Smooth motion"
        case .fps120: return "Slow-motion capable"
        case .fps240: return "Ultra slow-motion"
        }
    }
    
    var supportsSlowMotion: Bool {
        return fps >= 120
    }
}

// MARK: - Stabilization Mode

enum StabilizationMode: String, CaseIterable, Identifiable {
    case off = "off"
    case standard = "standard"
    case cinematic = "cinematic"
    case auto = "auto"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .off: return "Off"
        case .standard: return "Standard"
        case .cinematic: return "Cinematic"
        case .auto: return "Auto"
        }
    }
    
    var avMode: AVCaptureVideoStabilizationMode {
        switch self {
        case .off: return .off
        case .standard: return .standard
        case .cinematic: return .cinematic
        case .auto: return .auto
        }
    }
    
    var systemIcon: String {
        switch self {
        case .off: return "camera"
        case .standard: return "camera.viewfinder"
        case .cinematic: return "camera.aperture"
        case .auto: return "camera.metering.center.weighted"
        }
    }
    
    var description: String {
        switch self {
        case .off: return "No stabilization"
        case .standard: return "Reduces shake"
        case .cinematic: return "Smooth, movie-like"
        case .auto: return "Automatic selection"
        }
    }
}

// MARK: - Helper Extensions

extension VideoRecordingSettings {
    /// Check if device supports the selected quality
    func isQualitySupported(_ quality: RecordingQuality) -> Bool {
        // Most modern iOS devices support up to 4K
        // Check if the device supports the preset
        let captureSession = AVCaptureSession()
        return captureSession.canSetSessionPreset(quality.avPreset)
    }
    
    /// Check if device supports the selected frame rate at current quality
    func isFrameRateSupported(_ frameRate: FrameRate, for quality: RecordingQuality) -> Bool {
        // Higher frame rates may not be available at 4K
        if quality == .ultra4K && frameRate.fps > 60 {
            return false
        }
        
        // 240fps typically only available at lower resolutions
        if frameRate == .fps240 && quality.rawValue != "480p" {
            return false
        }
        
        return true
    }
    
    /// Get compatible frame rates for the selected quality
    func compatibleFrameRates(for quality: RecordingQuality) -> [FrameRate] {
        switch quality {
        case .ultra4K:
            return [.fps24, .fps30, .fps60]
        case .high1080p:
            return [.fps24, .fps30, .fps60, .fps120]
        case .medium720p, .low480p:
            return FrameRate.allCases
        }
    }
}
