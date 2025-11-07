//
//  VideoPlayerView.swift
//  PlayerPath
//
//  Created by Assistant on 11/05/25.
//

import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let clip: VideoClip
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .onAppear { player.play() }
                    .onDisappear { player.pause() }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(missingMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            }
        }
        .task {
            await preparePlayer()
        }
        .navigationTitle(clip.playResult?.type.displayName ?? clip.fileName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var missingMessage: String {
        if clip.isUploaded && !clip.isAvailableOffline {
            return "This video is in the cloud. Download it to play."
        } else {
            return "Loading video… If it doesn’t start, the video file may be missing."
        }
    }

    @MainActor
    private func preparePlayer() async {
        let url = URL(fileURLWithPath: clip.filePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("Video file missing at: \(url.path)")
            return
        }
        player = AVPlayer(url: url)
    }
}

#Preview {
    // This preview requires a mock VideoClip. Replace with a real instance from your environment if available.
    Text("VideoPlayerView Preview")
}
