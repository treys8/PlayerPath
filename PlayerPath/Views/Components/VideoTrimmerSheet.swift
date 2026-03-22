//
//  VideoTrimmerSheet.swift
//  PlayerPath
//
//  Sheet for trimming a video clip with start/end time sliders.
//

import SwiftUI
import AVKit

struct VideoTrimmerSheet: View {
    let player: AVPlayer
    let sourceURL: URL
    var onExported: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var startTime: Double = 0
    @State private var endTime: Double = 0
    @State private var duration: Double = 0
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var exportedTempURL: URL?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VideoPlayer(player: player)
                    .frame(height: 200)
                    .cornerRadius(8)

                if duration > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Start: \(format(time: startTime))  •  End: \(format(time: endTime))")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("Trim Range")
                            .font(.headline)

                        // Start slider
                        Slider(value: $startTime, in: 0...endTime - 0.1, step: 0.1) {
                            Text("Start")
                        }
                        .accessibilityLabel("Trim start time")

                        // End slider
                        Slider(value: $endTime, in: startTime + 0.1...duration, step: 0.1) {
                            Text("End")
                        }
                        .accessibilityLabel("Trim end time")
                    }
                    .padding(.horizontal)
                }

                if let exportError {
                    Text(exportError)
                        .foregroundColor(.red)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()
            }
            .navigationTitle("Trim Clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isExporting ? "Exporting…" : "Save") {
                        Task { await exportTrim() }
                    }
                    .disabled(isExporting || endTime - startTime < 0.2)
                }
            }
            .onAppear {
                setup()
            }
            .onDisappear {
                player.pause()

                if let tempURL = exportedTempURL, FileManager.default.fileExists(atPath: tempURL.path) {
                    try? FileManager.default.removeItem(at: tempURL)
                }
            }
        }
    }

    private func setup() {
        let asset = AVURLAsset(url: sourceURL)
        Task {
            do {
                let d = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(d)
                await MainActor.run {
                    self.duration = seconds
                    self.startTime = 0
                    self.endTime = seconds
                }
            } catch {
                await MainActor.run {
                    self.exportError = "Unable to read duration: \(error.localizedDescription)"
                }
            }
        }
    }

    private func exportTrim() async {
        isExporting = true
        exportError = nil
        let asset = AVURLAsset(url: sourceURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            exportError = "Export session could not be created."
            isExporting = false
            return
        }
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("trimmed_\(UUID().uuidString).mp4")
        let start = CMTime(seconds: startTime, preferredTimescale: 600)
        let end = CMTime(seconds: endTime, preferredTimescale: 600)
        session.timeRange = CMTimeRangeFromTimeToTime(start: start, end: end)
        session.outputURL = outputURL
        session.outputFileType = .mp4

        if #available(iOS 18.0, *) {
            do {
                try await session.export(to: outputURL, as: .mp4)
                await MainActor.run {
                    self.isExporting = false
                    self.exportedTempURL = outputURL
                    self.onExported(outputURL)
                    self.dismiss()
                }
            } catch {
                await MainActor.run {
                    try? FileManager.default.removeItem(at: outputURL)
                    self.isExporting = false
                    self.exportError = error.localizedDescription
                }
            }
        } else {
            await session.export()
            await MainActor.run {
                switch session.status {
                case .completed:
                    self.isExporting = false
                    self.exportedTempURL = outputURL
                    self.onExported(outputURL)
                    self.dismiss()
                case .failed:
                    try? FileManager.default.removeItem(at: outputURL)
                    self.isExporting = false
                    self.exportError = session.error?.localizedDescription ?? "Export failed"
                case .cancelled:
                    try? FileManager.default.removeItem(at: outputURL)
                    self.isExporting = false
                    self.exportError = "Export was cancelled"
                default:
                    try? FileManager.default.removeItem(at: outputURL)
                    self.isExporting = false
                    self.exportError = "Export ended with unknown status"
                }
            }
        }
    }

    private func format(time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
