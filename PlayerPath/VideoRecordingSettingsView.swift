//
//  VideoRecordingSettingsView.swift
//  PlayerPath
//
//  Created by Assistant on 11/13/25.
//

import SwiftUI
import AVFoundation
import Observation
import SwiftData

/// View for configuring video recording settings: quality, format, frame rate, capture, upload, and trimmer
struct VideoRecordingSettingsView: View {
    /// Controls which cloud-upload options are shown. Coaches only see settings
    /// that actually affect their upload path (cellular policy); the athlete-only
    /// auto-upload gate, highlights filter, and file-size cap are hidden because
    /// they are not honored by `UploadQueueManager.enqueueCoachUpload`.
    let role: UserRole

    // Access singleton directly - don't create a copy with @State
    @State private var settings = VideoRecordingSettings.shared
    @State private var showingResetConfirmation = false
    @State private var showingUnsupportedAlert = false
    @State private var unsupportedMessage = ""

    init(role: UserRole = .athlete) {
        self.role = role
    }

    @AppStorage(TrimmerPrefKeys.autoShowTrimmer) private var autoShowTrimmer = false
    @AppStorage(TrimmerPrefKeys.skipTrimmerForShortClips) private var skipTrimmerForShortClips = true

    @Environment(\.ppAccent) private var ppAccent

    // User preferences for cloud upload settings
    @Environment(\.modelContext) private var modelContext
    @Query private var userPreferences: [UserPreferences]

    private var preferences: UserPreferences? {
        userPreferences.first
    }

    var body: some View {
        Form {
            qualitySection
            formatSection
            frameRateSection
            additionalSettingsSection
            cloudUploadSection
            if role == .athlete {
                deviceCopySection
            }
            workflowSection
            resetSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.surface)
        .tint(ppAccent)
        .navigationTitle("Recording & Uploads")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Reset Settings", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetSettings()
            }
        } message: {
            Text("Reset quality, format, frame rate, audio, stabilization, and trimmer settings to their defaults? Cloud upload settings won't change.")
        }
        .alert("Not Available", isPresented: $showingUnsupportedAlert) {
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
                    subtitle: qualityDescription(quality),
                    mbPerMinute: settings.estimatedFileSizePerMinute(for: quality),
                    isSelected: settings.quality == quality,
                    isSupported: settings.isQualitySupported(quality)
                ) {
                    selectQuality(quality)
                }
            }
        } header: {
            Text("Video Quality")
        } footer: {
            Text("Sizes reflect your format and frame rate.")
                .font(.ppFootnote)
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
            Text("HEVC files are about half the size. H.264 plays on more older and non-Apple devices.")
                .font(.ppFootnote)
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
                    isCompatible: isCompatible,
                    unavailableText: isCompatible ? "" : unavailableLabel(for: frameRate)
                ) {
                    // Model's `frameRate.didSet` persists; incompatible rows are disabled.
                    settings.frameRate = frameRate
                    Haptics.light()
                }
                .disabled(!isCompatible)
                .opacity(isCompatible ? 1.0 : 0.5)
            }
        } header: {
            Text("Frame Rate")
        } footer: {
            Group {
                if role == .coach {
                    Text("120 fps and up records slow-motion. Higher frame rates make larger files. 60 fps or higher gives smoother frame-by-frame review of swings and throws.")
                } else {
                    Text("120 fps and up records slow-motion. Higher frame rates make larger files.")
                }
            }
            .font(.ppFootnote)
        }
    }

    private var additionalSettingsSection: some View {
        @Bindable var settings = settings
        return Section {
            Toggle(isOn: $settings.audioEnabled) {
                SettingLabel(
                    icon: settings.audioEnabled ? "mic.fill" : "mic.slash.fill",
                    iconColor: settings.audioEnabled ? ppAccent : .secondary,
                    title: "Record Audio"
                )
            }

            Picker(selection: $settings.stabilizationMode) {
                ForEach(StabilizationMode.allCases) { mode in
                    Text(mode.displayName)
                        .tag(mode)
                }
            } label: {
                SettingLabel(icon: "camera.viewfinder", iconColor: ppAccent, title: "Stabilization")
            }
        } header: {
            Text("Camera")
        } footer: {
            Text("Reduces camera shake. Auto picks the best mode for your resolution and frame rate.")
                .font(.ppFootnote)
        }
    }

    private var cloudUploadSection: some View {
        Section {
            if let prefs = preferences {
                if role == .athlete {
                    Toggle(isOn: Binding(
                        get: { prefs.autoUploadToCloud },
                        set: { prefs.autoUploadToCloud = $0; ErrorHandlerService.shared.saveContext(modelContext, caller: "RecordingSettings.autoUpload") }
                    )) {
                        SettingLabel(
                            icon: prefs.autoUploadToCloud ? "icloud.and.arrow.up.fill" : "icloud.slash.fill",
                            iconColor: prefs.autoUploadToCloud ? ppAccent : .secondary,
                            title: "Auto-Upload to Cloud"
                        )
                    }

                    if prefs.autoUploadToCloud {
                        Toggle(isOn: Binding(
                            get: { prefs.syncHighlightsOnly },
                            set: { prefs.syncHighlightsOnly = $0; ErrorHandlerService.shared.saveContext(modelContext, caller: "RecordingSettings.highlightsOnly") }
                        )) {
                            SettingLabel(
                                icon: "star.fill",
                                iconColor: prefs.syncHighlightsOnly ? ppAccent : .secondary,
                                title: "Highlights Only"
                            )
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            SettingLabel(
                                icon: "externaldrive",
                                iconColor: ppAccent,
                                title: "Max File Size: \(prefs.maxVideoFileSize) MB",
                                subtitle: minutesPerClipText(capMB: prefs.maxVideoFileSize)
                            )

                            VStack(spacing: 4) {
                                Slider(
                                    value: Binding(
                                        get: { Double(prefs.maxVideoFileSize) },
                                        set: { prefs.maxVideoFileSize = Int($0) }   // in-memory; persisted on release
                                    ),
                                    in: 50...2000,
                                    step: 50,
                                    onEditingChanged: { editing in
                                        if !editing {
                                            ErrorHandlerService.shared.saveContext(modelContext, caller: "RecordingSettings.maxFileSize")
                                        }
                                    }
                                )

                                HStack {
                                    Text("50 MB")
                                    Spacer()
                                    Text("2 GB")
                                }
                                .font(.ppFootnote)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.leading, SettingLabel.textInset)
                        }
                        .padding(.vertical, 4)

                        cellularToggle(for: prefs)
                    }
                } else {
                    // Coach: only the cellular toggle applies — the other three
                    // options are athlete-only and have no effect on coach uploads.
                    cellularToggle(for: prefs)
                }
            } else {
                Text("Loading preferences...")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Cloud Upload")
        } footer: {
            cloudUploadFooter
                .font(.ppFootnote)
        }
    }

    @ViewBuilder
    private func cellularToggle(for prefs: UserPreferences) -> some View {
        Toggle(isOn: Binding(
            get: { prefs.allowCellularUploads },
            set: { prefs.allowCellularUploads = $0; ErrorHandlerService.shared.saveContext(modelContext, caller: "RecordingSettings.cellularUploads") }
        )) {
            SettingLabel(
                icon: "antenna.radiowaves.left.and.right",
                iconColor: prefs.allowCellularUploads ? Theme.warning : .secondary,
                title: "Allow Cellular Uploads",
                subtitle: "May use significant mobile data"
            )
        }
    }

    @ViewBuilder
    private var cloudUploadFooter: some View {
        if role == .coach {
            if preferences?.allowCellularUploads == true {
                Text("Clips you upload to athlete folders will use Wi-Fi and cellular.")
            } else {
                Text("Clips you upload to athlete folders will only transfer when connected to Wi-Fi.")
            }
        } else if let prefs = preferences, prefs.autoUploadToCloud {
            let capNote = "Clips larger than \(prefs.maxVideoFileSize) MB won't auto-upload."
            if prefs.allowCellularUploads {
                Text("Videos upload automatically on Wi-Fi and cellular. \(capNote)")
            } else if prefs.syncHighlightsOnly {
                Text("Only highlight videos upload automatically, when connected to Wi-Fi. \(capNote)")
            } else {
                Text("All videos upload automatically when connected to Wi-Fi. \(capNote)")
            }
        } else {
            Text("Videos stay on this device. Turn on auto-upload to back them up to the cloud.")
        }
    }

    /// "≈ 7 min per clip at current settings" — how long a clip fits under the upload cap.
    private func minutesPerClipText(capMB: Int) -> String {
        let minutes = Double(capMB) / max(settings.estimatedFileSizePerMinute, 1)
        let amount = minutes < 1 ? "under 1" : "≈ \(Int(minutes))"
        return "\(amount) min per clip at current settings"
    }

    /// Athlete-only: what happens to the copy on this iPhone. Coach recordings
    /// don't go through ClipPersistenceService or the athlete upload queue, so
    /// neither toggle applies to them. Remove After Upload sits here, outside the
    /// auto-upload gate: UploadQueueManager deletes the local copy after ANY
    /// successful upload, manual ones included.
    @ViewBuilder
    private var deviceCopySection: some View {
        if let prefs = preferences {
            Section {
                Toggle(isOn: Binding(
                    get: { prefs.saveToPhotosLibrary },
                    set: { prefs.saveToPhotosLibrary = $0; ErrorHandlerService.shared.saveContext(modelContext, caller: "RecordingSettings.saveToPhotos") }
                )) {
                    SettingLabel(icon: "photo.on.rectangle", iconColor: ppAccent, title: "Save to Photos Library")
                }

                Toggle(isOn: Binding(
                    get: { prefs.autoDeleteAfterUpload },
                    set: { prefs.autoDeleteAfterUpload = $0; ErrorHandlerService.shared.saveContext(modelContext, caller: "RecordingSettings.autoDelete") }
                )) {
                    SettingLabel(
                        icon: "iphone.slash",
                        iconColor: prefs.autoDeleteAfterUpload ? Theme.warning : .secondary,
                        title: "Remove After Upload",
                        subtitle: "Frees space on this iPhone"
                    )
                }
            } header: {
                Text("On This iPhone")
            } footer: {
                // Honest about the trade-off: VideoPlayerView re-downloads on play,
                // but the reel stitcher only uses clips present on this device.
                Text("Removed clips download again when you play them. Highlight reels can only include clips that are still on this iPhone.")
                    .font(.ppFootnote)
            }
        }
    }

    private var workflowSection: some View {
        Section {
            Toggle(isOn: $autoShowTrimmer) {
                SettingLabel(
                    icon: "scissors",
                    iconColor: ppAccent,
                    title: "Always Show Trimmer",
                    subtitle: "Edit video length after recording"
                )
            }
            .onChange(of: autoShowTrimmer) { _, _ in
                Haptics.light()
            }

            if !autoShowTrimmer {
                Toggle(isOn: $skipTrimmerForShortClips) {
                    SettingLabel(
                        icon: "timer",
                        iconColor: ppAccent,
                        title: "Auto-Skip for Short Clips",
                        subtitle: "Under \(Int(TrimmerPrefKeys.shortClipThreshold)) seconds"
                    )
                }
                .onChange(of: skipTrimmerForShortClips) { _, _ in
                    Haptics.light()
                }
            }
        } header: {
            Text("Recording Workflow")
        } footer: {
            Group {
                // Coaches have no trim-after-save path, and coach clips are never tagged.
                if role == .coach {
                    if autoShowTrimmer {
                        Text("The trimmer appears after every recording so you can cut clips before they're saved.")
                    } else {
                        Text("Clips under \(Int(TrimmerPrefKeys.shortClipThreshold)) seconds skip the trimmer. Trim before saving — clips can't be trimmed afterward.")
                    }
                } else if autoShowTrimmer {
                    Text("The video trimmer will appear after every recording, allowing you to precisely edit start and end points.")
                } else {
                    Text("Clips under \(Int(TrimmerPrefKeys.shortClipThreshold)) seconds skip the trimmer so you can tag faster. You can still trim any clip later.")
                }
            }
            .font(.ppFootnote)
        }
    }

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                showingResetConfirmation = true
            } label: {
                Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    // MARK: - Row Copy

    /// Coaches pick quality for reviewing mechanics, so their copy speaks to that.
    /// Kept short: the row appends " · ~NN MB/min".
    private func qualityDescription(_ quality: RecordingQuality) -> String {
        guard role == .coach else { return quality.description }
        switch quality {
        case .low480p: return "Too soft for mechanics"
        case .medium720p: return "Fine for quick feedback"
        case .high1080p: return "Sharp detail, recommended"
        case .ultra4K: return "Most detail, large uploads"
        }
    }

    /// "Needs 720p" — the highest supported quality that offers this frame rate.
    private func unavailableLabel(for rate: FrameRate) -> String {
        let quality = RecordingQuality.allCases.reversed().first {
            settings.isQualitySupported($0) && settings.compatibleFrameRates(for: $0).contains(rate)
        }
        return quality.map { "Needs \($0.rawValue)" } ?? "Not available"
    }

    // MARK: - Actions

    private func selectQuality(_ quality: RecordingQuality) {
        guard settings.isQualitySupported(quality) else {
            unsupportedMessage = "\(quality.displayName) is not supported on this device."
            showingUnsupportedAlert = true
            return
        }

        // Model's `quality.didSet` reconciles the frame rate.
        settings.quality = quality
        Haptics.light()
    }

    private func resetSettings() {
        withAnimation {
            settings.resetToDefaults()
            autoShowTrimmer = false
            skipTrimmerForShortClips = true
        }
        Haptics.medium()
    }
}

// MARK: - Setting Label

/// Icon + title (+ optional subtitle) for toggle/picker rows, on a fixed icon
/// column so every row's text starts at the same x.
private struct SettingLabel: View {
    static let iconWidth: CGFloat = 28
    static let spacing: CGFloat = 12
    /// Leading offset of the text column — for content placed under a label.
    static let textInset: CGFloat = iconWidth + spacing

    let icon: String
    var iconColor: Color = .secondary
    let title: String
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: Self.spacing) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .frame(width: Self.iconWidth)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.ppBody)
                if let subtitle {
                    Text(subtitle)
                        .font(.ppFootnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Quality Row

struct QualityRow: View {
    let quality: RecordingQuality
    let subtitle: String
    let mbPerMinute: Double
    let isSelected: Bool
    let isSupported: Bool
    let action: () -> Void

    @Environment(\.ppAccent) private var ppAccent

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(quality.displayName)
                        .font(.ppBody)
                        .foregroundStyle(isSupported ? .primary : .secondary)

                    Text("\(subtitle) · ~\(Int(mbPerMinute.rounded())) MB/min")
                        .font(.ppFootnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !isSupported {
                    // Stays tappable — the tap explains why via an alert.
                    Text("Not available")
                        .font(.ppFootnote)
                        .foregroundStyle(.secondary)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(ppAccent)
                        .font(.title3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Format Row

struct FormatRow: View {
    let format: VideoFormat
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.ppAccent) private var ppAccent

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(format.displayName)
                        .font(.ppBody)

                    Text(format.description)
                        .font(.ppFootnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(ppAccent)
                        .font(.title3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Frame Rate Row

struct FrameRateRow: View {
    let frameRate: FrameRate
    let isSelected: Bool
    let isCompatible: Bool
    /// Shown in place of the checkmark when incompatible, e.g. "Needs 720p".
    let unavailableText: String
    let action: () -> Void

    @Environment(\.ppAccent) private var ppAccent

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(frameRate.displayName)
                        .font(.ppBody)

                    Text(frameRate.description)
                        .font(.ppFootnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !isCompatible {
                    Text(unavailableText)
                        .font(.ppFootnote)
                        .foregroundStyle(.secondary)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(ppAccent)
                        .font(.title3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Preview

#Preview {
    VideoRecordingSettingsView()
}

