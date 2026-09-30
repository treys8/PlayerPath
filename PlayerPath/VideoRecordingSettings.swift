//
//  VideoRecordingSettings.swift
//  PlayerPath
//
//  Created by Assistant on 11/13/25.
//

import Foundation
import AVFoundation
import UIKit

// MARK: - Video Recording Settings Model

/// Stores user preferences for video recording quality, format, frame rate, and slow-motion
@Observable
@MainActor
final class VideoRecordingSettings {

    // MARK: - Singleton

    static let shared = VideoRecordingSettings()

    // MARK: - Debouncing

    private var saveTask: Task<Void, Never>?
    private let saveDebounceInterval: Duration = .milliseconds(500)
    private var isInitializing = true

    // MARK: - Settings Properties
    
    /// Video quality/resolution
    var quality: RecordingQuality {
        didSet {
            reconcileFrameRateForQuality()
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

    /// Slow-mo is simply recording at ≥120 fps — there is no separate flag.
    var isSlowMotion: Bool { frameRate.supportsSlowMotion }
    
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

        // Reconcile persisted state after all stored properties are initialized:
        // clamp frame rate to what the device supports at the loaded quality.
        // Unsticks users whose stored state drifted into an inconsistent combination.
        let compatible = compatibleFrameRates(for: self.quality)
        if !compatible.contains(self.frameRate), let fallback = compatible.last {
            self.frameRate = fallback
        }

        isInitializing = false

        // Flush any pending debounced save before the app can be suspended/killed.
        // `queue: nil` delivers synchronously on the posting thread — UIApplication
        // lifecycle notifications post on the main thread, so the save completes
        // before the app resigns (an enqueued/async handler could miss suspension).
        // The singleton lives for the app's lifetime, so the observer is never removed.
        _ = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveImmediately() }
        }
    }
    
    // MARK: - Persistence

    private func saveSettings() {
        guard !isInitializing else { return }

        // Cancel any pending save task
        saveTask?.cancel()

        // Schedule new save with debouncing
        saveTask = Task {
            try? await Task.sleep(for: saveDebounceInterval)

            guard !Task.isCancelled else { return }

            // Perform actual save
            UserDefaults.standard.set(quality.rawValue, forKey: Keys.quality)
            UserDefaults.standard.set(format.rawValue, forKey: Keys.format)
            UserDefaults.standard.set(frameRate.rawValue, forKey: Keys.frameRate)
            UserDefaults.standard.set(audioEnabled, forKey: Keys.audioEnabled)
            UserDefaults.standard.set(stabilizationMode.rawValue, forKey: Keys.stabilizationMode)

            #if DEBUG
            print("💾 Video recording settings saved")
            #endif
        }
    }

    /// Force immediate save (useful when app is backgrounding)
    func saveImmediately() {
        saveTask?.cancel()
        UserDefaults.standard.set(quality.rawValue, forKey: Keys.quality)
        UserDefaults.standard.set(format.rawValue, forKey: Keys.format)
        UserDefaults.standard.set(frameRate.rawValue, forKey: Keys.frameRate)
        UserDefaults.standard.set(audioEnabled, forKey: Keys.audioEnabled)
        UserDefaults.standard.set(stabilizationMode.rawValue, forKey: Keys.stabilizationMode)
    }
    
    // MARK: - Invariants

    /// Ensures `frameRate` is one the device can record at the current `quality`.
    private func reconcileFrameRateForQuality() {
        let compatible = compatibleFrameRates(for: quality)
        if !compatible.contains(frameRate), let fallback = compatible.last {
            frameRate = fallback
        }
    }

    // MARK: - Reset to Defaults

    func resetToDefaults() {
        quality = .high1080p
        format = .hevc
        frameRate = .fps30
        audioEnabled = true
        stabilizationMode = .auto
        
        #if DEBUG
        print("🔄 Video recording settings reset to defaults")
        #endif
    }
    
    // MARK: - Computed Properties
    
    /// Estimated file size per minute of video (in MB) at the current settings.
    var estimatedFileSizePerMinute: Double {
        estimatedFileSizePerMinute(for: quality)
    }

    /// Estimated MB per minute if `quality` were selected with the current format and
    /// frame rate. Uses the rate you'd actually get: switching quality clamps an
    /// unsupported rate to the highest compatible one (see reconcileFrameRateForQuality).
    func estimatedFileSizePerMinute(for quality: RecordingQuality) -> Double {
        let compatible = compatibleFrameRates(for: quality)
        let effectiveRate = compatible.contains(frameRate) ? frameRate : (compatible.last ?? frameRate)
        return quality.estimatedMBPerMinute * format.sizeMultiplier * effectiveRate.multiplier
    }
    
    /// Human-readable description of current settings
    var settingsDescription: String {
        var components: [String] = []
        components.append(quality.displayName)
        components.append(frameRate.displayName)
        if isSlowMotion {
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
        case .low480p: return CGSize(width: 640, height: 480)
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
    
    /// Returns a human-readable resolution name for a given width/height (supports portrait and landscape).
    nonisolated static func resolutionName(width: Int, height: Int) -> String {
        let landscape = (max(width, height), min(width, height))
        switch landscape {
        case (3840, 2160): return "4K"
        case (1920, 1080): return "1080p"
        case (1280, 720): return "720p"
        case (640, 480): return "480p"
        default: return "\(width)×\(height)"
        }
    }

    /// Estimated MB per minute of H.264 at 30 fps. Provisional figures, to be
    /// calibrated against real recordings; `VideoFormat.sizeMultiplier` and
    /// `FrameRate.multiplier` scale from here.
    var estimatedMBPerMinute: Double {
        switch self {
        case .low480p: return 20.0
        case .medium720p: return 45.0
        case .high1080p: return 130.0
        case .ultra4K: return 350.0
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

    /// File size relative to H.264 at the same resolution and frame rate.
    var sizeMultiplier: Double {
        switch self {
        case .hevc: return 0.5
        case .h264: return 1.0
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
    
    /// File size multiplier relative to 30fps. Sub-linear: encoders spend fewer
    /// bits per frame as frames get closer together (60 fps ≈ 1.6×, 120 ≈ 2.6×).
    var multiplier: Double {
        pow(Double(fps) / 30.0, 0.7)
    }
    
    var description: String {
        switch self {
        case .fps24: return "Film look, choppy for fast motion"
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
}

// MARK: - Helper Extensions

extension VideoRecordingSettings {
    /// Shared capture session for capability checking (reused to avoid memory leaks)
    private static let capabilityCheckSession: AVCaptureSession = {
        let session = AVCaptureSession()
        return session
    }()

    /// Check if device supports the selected quality
    func isQualitySupported(_ quality: RecordingQuality) -> Bool {
        // Most modern iOS devices support up to 4K
        // Check if the device supports the preset using shared session
        return Self.capabilityCheckSession.canSetSessionPreset(quality.avPreset)
    }
    
    /// Device camera formats never change at runtime, so each quality's answer is cached.
    private static var frameRateCache: [RecordingQuality: [FrameRate]] = [:]

    /// Frame rates the back camera can record at `quality`'s resolution. Mirrors the
    /// recorder's format choice (`CameraViewModel.setupCamera`): exact size first, else
    /// anything no larger — so a rate is only offered if it records at the resolution picked.
    func compatibleFrameRates(for quality: RecordingQuality) -> [FrameRate] {
        if let cached = Self.frameRateCache[quality] { return cached }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            return Self.fallbackFrameRates(for: quality)
        }

        let targetW = Int(quality.resolution.width)
        let targetH = Int(quality.resolution.height)
        func dimensions(_ format: AVCaptureDevice.Format) -> (w: Int, h: Int) {
            let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return (Int(max(d.width, d.height)), Int(min(d.width, d.height)))
        }

        let exact = device.formats.filter { dimensions($0) == (targetW, targetH) }
        let candidates = exact.isEmpty ? device.formats.filter { dimensions($0).w <= targetW } : exact
        let rates = FrameRate.allCases.filter { rate in
            candidates.contains { format in
                format.videoSupportedFrameRateRanges.contains {
                    $0.minFrameRate <= Double(rate.fps) && $0.maxFrameRate >= Double(rate.fps)
                }
            }
        }

        let result = rates.isEmpty ? [.fps30] : rates
        Self.frameRateCache[quality] = result
        return result
    }

    /// Used only when there is no camera (Simulator).
    private static func fallbackFrameRates(for quality: RecordingQuality) -> [FrameRate] {
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
