//
//  VideoRecordingOptionsView.swift
//  PlayerPath
//
//  Created by Assistant on 10/27/25.
//

import SwiftUI

struct VideoRecordingOptionsView: View {
    let onRecordVideo: () -> Void
    let onUploadVideo: () -> Void
    var tipText: String? = "Tip: Position camera to capture the full swing and follow-through"
    var isRecordingDisabled: Bool = false
    var isUploadDisabled: Bool = false
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var hideUpload: Bool = false // Hide upload for live games

    var body: some View {
        VStack(spacing: 16) {
            recordVideoButton

            if !hideUpload {
                uploadVideoButton
            }

            if let errorMessage {
                errorMessageView(text: errorMessage)
            }

            if let tipText {
                helpfulTip(text: tipText)
            }
        }
    }

    private var recordVideoButton: some View {
        Button {
            Haptics.medium()
            onRecordVideo()
        } label: {
            RecordingOptionButtonContent(
                icon: "camera.fill",
                iconColor: .red,
                title: "Record Video",
                subtitle: isRecordingDisabled ? "Camera unavailable" : "Use device camera",
                isLoading: isLoading,
                isDisabled: isRecordingDisabled
            )
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .disabled(isRecordingDisabled || isLoading)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.6)
                .onEnded { _ in
                    if !isRecordingDisabled && !isLoading {
                        Haptics.heavy()
                        onRecordVideo()
                    }
                }
        )
        .accessibilityLabel("Record new video using device camera")
        .accessibilityHint(isRecordingDisabled ? "Camera is not available" : "Opens camera to record a new video. Long press for quick record.")
        .contentShape(Rectangle())
    }

    private var uploadVideoButton: some View {
        Button {
            Haptics.medium()
            onUploadVideo()
        } label: {
            RecordingOptionButtonContent(
                icon: "photo.on.rectangle",
                iconColor: .blue,
                title: "Upload Video",
                subtitle: isUploadDisabled ? "Photo library unavailable" : "Choose from library",
                isLoading: isLoading,
                isDisabled: isUploadDisabled
            )
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .disabled(isUploadDisabled || isLoading)
        .accessibilityLabel("Upload video from photo library")
        .accessibilityHint(isUploadDisabled ? "Photo library is not available" : "Opens photo library to select an existing video")
        .contentShape(Rectangle())
    }

    private func errorMessageView(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.red)

            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
                )
        )
        .accessibilityLabel("Error: \(text)")
    }

    private func helpfulTip(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 14))
                .foregroundStyle(.yellow)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.yellow.opacity(0.3), lineWidth: 1)
                )
        )
        .accessibilityLabel("Tip: \(text)")
    }
}

struct RecordingOptionButtonContent: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    var isLoading: Bool = false
    var isDisabled: Bool = false

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(isDisabled ? Color.gray.opacity(0.5) : iconColor)
                    .frame(width: 50, height: 50)

                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !isLoading {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(buttonBackground)
        .opacity(isDisabled && !isLoading ? 0.5 : 1.0)
    }

    private var buttonBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(.secondarySystemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 1)
            )
    }
}

#Preview("Normal") {
    VideoRecordingOptionsView(
        onRecordVideo: { print("Record video tapped") },
        onUploadVideo: { print("Upload video tapped") }
    )
    .padding()
}

#Preview("Loading") {
    VideoRecordingOptionsView(
        onRecordVideo: { print("Record video tapped") },
        onUploadVideo: { print("Upload video tapped") },
        isLoading: true
    )
    .padding()
}

#Preview("Camera Disabled") {
    VideoRecordingOptionsView(
        onRecordVideo: { print("Record video tapped") },
        onUploadVideo: { print("Upload video tapped") },
        isRecordingDisabled: true
    )
    .padding()
}

#Preview("With Error") {
    VideoRecordingOptionsView(
        onRecordVideo: { print("Record video tapped") },
        onUploadVideo: { print("Upload video tapped") },
        errorMessage: "Camera permission denied. Please enable in Settings."
    )
    .padding()
}

#Preview("Dark Mode") {
    VideoRecordingOptionsView(
        onRecordVideo: { print("Record video tapped") },
        onUploadVideo: { print("Upload video tapped") }
    )
    .padding()
    .preferredColorScheme(.dark)
}
