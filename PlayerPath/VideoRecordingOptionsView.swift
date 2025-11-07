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
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Choose Recording Option")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            VStack(spacing: 16) {
                recordVideoButton
                uploadVideoButton
            }
            
            helpfulTip
        }
    }
    
    private var recordVideoButton: some View {
        Button(action: onRecordVideo) {
            RecordingOptionButtonContent(
                icon: "camera.fill",
                iconColor: .red,
                title: "Record Video",
                subtitle: "Use device camera"
            )
        }
        .accessibilityLabel("Record new video using device camera")
        .accessibilityHint("Opens camera to record a new video")
    }
    
    private var uploadVideoButton: some View {
        Button(action: onUploadVideo) {
            RecordingOptionButtonContent(
                icon: "photo.on.rectangle",
                iconColor: .blue,
                title: "Upload Video",
                subtitle: "Choose from library"
            )
        }
        .accessibilityLabel("Upload video from photo library")
        .accessibilityHint("Opens photo library to select an existing video")
    }
    
    private var helpfulTip: some View {
        HStack(spacing: 8) {
            Image(systemName: "lightbulb")
                .font(.system(size: 14))
                .foregroundColor(.yellow)
            
            Text("Tip: Position camera to capture the full swing and follow-through")
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
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(buttonBackground)
    }
    
    private var buttonBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
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