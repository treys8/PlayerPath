//
//  VideoRecordingSettingsView.swift
//  PlayerPath
//
//  Created by Assistant on 11/13/25.
//

import SwiftUI
import AVFoundation
import Observation

/// View for configuring video recording settings including quality, format, frame rate, and slow-motion
struct VideoRecordingSettingsView: View {
    // Access singleton directly - don't create a copy with @State
    @State private var settings = VideoRecordingSettings.shared
    @State private var showingResetConfirmation = false
    @State private var showingUnsupportedAlert = false
    @State private var unsupportedMessage = ""
    @State private var lastSaveTime: Date?
    
    var body: some View {
        @Bindable var settings = settings
        Form {
            qualitySection
            formatSection
            frameRateSection
            slowMotionSection
            additionalSettingsSection
            summarySection
            resetSection
        }
        .navigationTitle("Recording Settings")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)  // Explicitly show system back button
        .toolbar {
            ToolbarItem(placement: .status) {
                Text("Settings auto-save")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .alert("Reset Settings", isPresented: $showingResetConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    resetSettings()
                }
            } message: {
                Text("Are you sure you want to reset all video recording settings to their default values?")
            }
            .alert("Unsupported Frame Rate", isPresented: $showingUnsupportedAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(unsupportedMessage)
            }
    }
    
    // MARK: - Sections
    
    private var qualitySection: some View {
        Section {
            ForEach(RecordingQuality.allCases) { quality in
                QualityRow(
                    quality: quality,
                    isSelected: settings.quality == quality,
                    isSupported: settings.isQualitySupported(quality)
                ) {
                    selectQuality(quality)
                }
            }
        } header: {
            Text("Video Quality")
        } footer: {
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text("Estimated: \(String(format: "%.0f", settings.estimatedFileSizePerMinute)) MB per minute")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var formatSection: some View {
        Section {
            ForEach(VideoFormat.allCases) { format in
                FormatRow(
                    format: format,
                    isSelected: settings.format == format
                ) {
                    settings.format = format
                    Haptics.light()
                }
            }
        } header: {
            Text("Video Format")
        } footer: {
            Text("HEVC (H.265) provides better compression and smaller file sizes, while H.264 offers maximum compatibility across devices and platforms.")
        }
    }
    
    private var frameRateSection: some View {
        Section {
            let compatibleRates = settings.compatibleFrameRates(for: settings.quality)
            
            ForEach(FrameRate.allCases) { frameRate in
                let isCompatible = compatibleRates.contains(frameRate)
                
                FrameRateRow(
                    frameRate: frameRate,
                    isSelected: settings.frameRate == frameRate,
                    isCompatible: isCompatible
                ) {
                    if isCompatible {
                        selectFrameRate(frameRate)
                    } else {
                        showUnsupportedFrameRate(frameRate)
                    }
                }
                .disabled(!isCompatible)
                .opacity(isCompatible ? 1.0 : 0.5)
            }
        } header: {
            Text("Frame Rate")
        } footer: {
            Text("Higher frame rates enable slow-motion playback but increase file sizes. Some frame rates may not be available at higher resolutions.")
        }
    }
    
    private var slowMotionSection: some View {
        Section {
            Toggle(isOn: $settings.slowMotionEnabled) {
                HStack {
                    Image(systemName: "slowmo")
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Slow-Motion Recording")
                            .font(.body)
                        
                        Text("Capture at high frame rate for smooth slow-motion playback")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(!settings.supportsSlowMotion)
            
            if settings.slowMotionEnabled {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.caption)
                    Text("Videos will be recorded at \(settings.frameRate.displayName) and can be played back at slower speeds")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Slow-Motion")
        } footer: {
            if !settings.supportsSlowMotion {
                Text("Slow-motion requires a frame rate of 120 fps or higher. Select a higher frame rate to enable this feature.")
            }
        }
    }
    
    private var additionalSettingsSection: some View {
        Section {
            Toggle(isOn: $settings.audioEnabled) {
                HStack {
                    Image(systemName: settings.audioEnabled ? "mic.fill" : "mic.slash.fill")
                        .foregroundStyle(settings.audioEnabled ? .blue : .secondary)
                    Text("Record Audio")
                }
            }
            
            Picker("Stabilization", selection: $settings.stabilizationMode) {
                ForEach(StabilizationMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.systemIcon)
                        .tag(mode)
                }
            }
        } header: {
            Text("Additional Settings")
        } footer: {
            Text("Video stabilization reduces shake and improves footage quality. \(settings.stabilizationMode.description).")
        }
    }
    
    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                SummaryRow(
                    icon: "video.fill",
                    title: "Quality",
                    value: settings.quality.displayName
                )
                
                SummaryRow(
                    icon: "waveform",
                    title: "Format",
                    value: settings.format.displayName
                )
                
                SummaryRow(
                    icon: "speedometer",
                    title: "Frame Rate",
                    value: settings.frameRate.displayName
                )
                
                if settings.slowMotionEnabled {
                    SummaryRow(
                        icon: "slowmo",
                        title: "Slow-Motion",
                        value: "Enabled"
                    )
                }
                
                Divider()
                
                HStack {
                    Image(systemName: "doc.fill")
                        .foregroundStyle(.secondary)
                    Text("Estimated file size:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(String(format: "%.0f", settings.estimatedFileSizePerMinute)) MB/min")
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
            }
            .padding(.vertical, 8)
        } header: {
            Text("Current Settings")
        }
    }
    
    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                showingResetConfirmation = true
            } label: {
                Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
    
    // MARK: - Actions
    
    private func selectQuality(_ quality: RecordingQuality) {
        guard settings.isQualitySupported(quality) else {
            unsupportedMessage = "\(quality.displayName) is not supported on this device."
            showingUnsupportedAlert = true
            return
        }
        
        settings.quality = quality
        
        // Adjust frame rate if incompatible with new quality
        if !settings.isFrameRateSupported(settings.frameRate, for: quality) {
            // Auto-select highest compatible frame rate
            let compatibleRates = settings.compatibleFrameRates(for: quality)
            if let highestCompatible = compatibleRates.last {
                settings.frameRate = highestCompatible
            }
        }
        
        // Disable slow-motion if no longer supported
        if !settings.supportsSlowMotion {
            settings.slowMotionEnabled = false
        }
        
        Haptics.light()
    }
    
    private func selectFrameRate(_ frameRate: FrameRate) {
        settings.frameRate = frameRate
        
        // Disable slow-motion if new frame rate doesn't support it
        if !settings.supportsSlowMotion {
            settings.slowMotionEnabled = false
        }
        
        Haptics.light()
    }
    
    private func showUnsupportedFrameRate(_ frameRate: FrameRate) {
        unsupportedMessage = "\(frameRate.displayName) is not available at \(settings.quality.displayName) resolution. Try selecting a lower quality setting."
        showingUnsupportedAlert = true
    }
    
    private func resetSettings() {
        withAnimation {
            settings.resetToDefaults()
        }
        Haptics.medium()
    }
}

// MARK: - Quality Row

struct QualityRow: View {
    let quality: RecordingQuality
    let isSelected: Bool
    let isSupported: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: quality.systemIcon)
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.title3)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(quality.displayName)
                        .font(.body)
                        .foregroundStyle(isSupported ? .primary : .secondary)
                    
                    Text(quality.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("~\(String(format: "%.0f", quality.estimatedMBPerMinute)) MB/min")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.title3)
                }
                
                if !isSupported {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Format Row

struct FormatRow: View {
    let format: VideoFormat
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: format.systemIcon)
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.title3)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(format.displayName)
                        .font(.body)
                    
                    Text(format.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.title3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Frame Rate Row

struct FrameRateRow: View {
    let frameRate: FrameRate
    let isSelected: Bool
    let isCompatible: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: frameRate.systemIcon)
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.title3)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(frameRate.displayName)
                            .font(.body)
                        
                        if frameRate.supportsSlowMotion {
                            Image(systemName: "slowmo")
                                .font(.caption)
                                .foregroundStyle(.purple)
                        }
                    }
                    
                    Text(frameRate.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if !isCompatible {
                    Text("Not available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.title3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Summary Row

struct SummaryRow: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)
            
            Text(title)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

// MARK: - Preview

#Preview {
    VideoRecordingSettingsView()
}

