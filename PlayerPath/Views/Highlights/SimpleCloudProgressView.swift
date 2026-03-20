//
//  SimpleCloudProgressView.swift
//  PlayerPath
//
//  Cloud upload progress indicator for individual video clips.
//

import SwiftUI
import SwiftData

// MARK: - Temporary Simple Cloud Progress View
struct SimpleCloudProgressView: View {
    let clip: VideoClip
    let athlete: Athlete?

    @Environment(\.modelContext) private var modelContext
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0.0
    @State private var uploadError: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: cloudStatusIcon)
                .foregroundColor(cloudStatusColor)
                .font(.caption)

            if isUploading {
                HStack(spacing: 4) {
                    ProgressView(value: uploadProgress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 100)

                    Text("\(Int(uploadProgress * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            } else {
                Text(cloudStatusText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if clip.needsUpload && !isUploading {
                Button("Upload") {
                    Task {
                        await uploadVideo()
                    }
                }
                .font(.caption2)
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            if let error = uploadError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
                    .help(error)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.systemGray6))
        .cornerRadius(.cornerMedium)
    }

    private func uploadVideo() async {
        guard let athlete = athlete else {
            uploadError = "No athlete associated with clip"
            return
        }

        isUploading = true
        uploadError = nil
        uploadProgress = 0.0

        do {
            let cloudURL = try await VideoCloudManager.shared.uploadVideo(clip, athlete: athlete)

            await MainActor.run {
                clip.cloudURL = cloudURL
                clip.isUploaded = true
                clip.lastSyncDate = Date()
                if let user = athlete.user {
                    let fileSize = (try? FileManager.default.attributesOfItem(atPath: clip.resolvedFilePath)[.size] as? Int64) ?? 0
                    user.cloudStorageUsedBytes += fileSize
                }

                do {
                    try modelContext.save()
                } catch {
                    uploadError = "Failed to save: \(error.localizedDescription)"
                }

                isUploading = false
            }
        } catch {
            await MainActor.run {
                uploadError = error.localizedDescription
                isUploading = false
            }
        }
    }

    private var cloudStatusIcon: String {
        if clip.isUploaded && clip.isAvailableOffline {
            return "icloud.and.arrow.down.fill"
        } else if clip.isUploaded {
            return "icloud.fill"
        } else if clip.needsUpload {
            return "icloud.and.arrow.up"
        } else {
            return "externaldrive.fill"
        }
    }

    private var cloudStatusColor: Color {
        if clip.isUploaded && clip.isAvailableOffline {
            return .green
        } else if clip.isUploaded {
            return .blue
        } else if clip.needsUpload {
            return .orange
        } else {
            return .gray
        }
    }

    private var cloudStatusText: String {
        if clip.isUploaded && clip.isAvailableOffline {
            return "Available Offline"
        } else if clip.isUploaded {
            return "In Cloud"
        } else if clip.needsUpload {
            return "Ready to Upload"
        } else {
            return "Local Only"
        }
    }
}
