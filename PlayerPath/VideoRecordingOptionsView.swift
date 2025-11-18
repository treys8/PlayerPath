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
    
    var body: some View {
        VStack(spacing: 16) {
            recordVideoButton
            uploadVideoButton
            
            if let tipText {
                helpfulTip(text: tipText)
            }
        }
    }
    
    private var recordVideoButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onRecordVideo()
        } label: {
            RecordingOptionButtonContent(
                icon: "camera.fill",
                iconColor: .red,
                title: "Record Video",
                subtitle: "Use device camera"
            )
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Record new video using device camera")
        .accessibilityHint("Opens camera to record a new video")
        .contentShape(Rectangle())
    }
    
    private var uploadVideoButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onUploadVideo()
        } label: {
            RecordingOptionButtonContent(
                icon: "photo.on.rectangle",
                iconColor: .blue,
                title: "Upload Video",
                subtitle: "Choose from library"
            )
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Upload video from photo library")
        .accessibilityHint("Opens photo library to select an existing video")
        .contentShape(Rectangle())
    }
    
    private func helpfulTip(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "lightbulb")
                .font(.system(size: 14))
                .foregroundColor(.yellow)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.yellow.opacity(0.3), lineWidth: 1)
                )
        )
        .accessibilityLabel(text)
    }
}

struct RecordingOptionButtonContent: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(iconColor)
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(buttonBackground)
    }
    
    private var buttonBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VideoRecordingOptionsView(
            onRecordVideo: { print("Record video tapped") },
            onUploadVideo: { print("Upload video tapped") }
        )
    }
}
