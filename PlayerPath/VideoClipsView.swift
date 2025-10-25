//
//  VideoClipsView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import SwiftData
import AVKit

struct VideoClipsView: View {
    let athlete: Athlete?
    @Environment(\.modelContext) private var modelContext
    @State private var showingVideoRecorder = false
    @State private var selectedClip: VideoClip?
    @State private var showingVideoPlayer = false
    
    var videoClips: [VideoClip] {
        athlete?.videoClips.sorted { $0.createdAt > $1.createdAt } ?? []
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if videoClips.isEmpty {
                    EmptyVideoClipsView {
                        showingVideoRecorder = true
                    }
                } else {
                    List {
                        ForEach(videoClips) { clip in
                            VideoClipListItem(clip: clip) {
                                selectedClip = clip
                                showingVideoPlayer = true
                            }
                        }
                        .onDelete(perform: deleteVideoClips)
                    }
                }
            }
            .navigationTitle("Video Clips")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingVideoRecorder = true }) {
                        Image(systemName: "video.badge.plus")
                    }
                }
                
                if !videoClips.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) {
                        EditButton()
                    }
                }
            }
        }
        .sheet(isPresented: $showingVideoRecorder) {
            VideoRecorderView(
                athlete: athlete,
                game: athlete?.games.first { $0.isLive }
            )
        }
        .sheet(isPresented: $showingVideoPlayer) {
            if let clip = selectedClip {
                VideoPlayerView(clip: clip)
            }
        }
    }
    
    private func deleteVideoClips(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let clip = videoClips[index]
                
                // Delete the video file
                if FileManager.default.fileExists(atPath: clip.filePath) {
                    try? FileManager.default.removeItem(atPath: clip.filePath)
                }
                
                modelContext.delete(clip)
            }
            
            do {
                try modelContext.save()
            } catch {
                print("Failed to delete video clips: \(error)")
            }
        }
    }
}

struct EmptyVideoClipsView: View {
    let onRecordVideo: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "video")
                .font(.system(size: 80))
                .foregroundColor(.purple)
            
            Text("No Video Clips Yet")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Record your first video clip to start building your baseball journal")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: onRecordVideo) {
                Text("Record Video")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding()
    }
}

struct VideoClipListItem: View {
    let clip: VideoClip
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Enhanced Thumbnail with Play Result Overlay
                ZStack(alignment: .bottomLeading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 80, height: 60)
                        .cornerRadius(8)
                        .overlay(
                            Image(systemName: "play.fill")
                                .foregroundColor(.white)
                                .font(.title3)
                                .shadow(color: .black.opacity(0.3), radius: 2)
                        )
                    
                    // Play Result Badge Overlay
                    if let playResult = clip.playResult {
                        HStack(spacing: 2) {
                            playResultIcon(for: playResult.type)
                                .foregroundColor(.white)
                                .font(.caption2)
                            
                            Text(playResultAbbreviation(for: playResult.type))
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(playResultColor(for: playResult.type))
                        .cornerRadius(4)
                        .offset(x: 4, y: -4)
                    } else {
                        // Unrecorded indicator
                        Text("?")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .frame(width: 16, height: 16)
                            .background(Color.gray)
                            .clipShape(Circle())
                            .offset(x: 4, y: -4)
                    }
                    
                    // Highlight star indicator
                    if clip.isHighlight {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                            .frame(width: 18, height: 18)
                            .offset(x: -4, y: 4)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    if let playResult = clip.playResult {
                        HStack {
                            Text(playResult.type.rawValue)
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            if clip.isHighlight {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                    .font(.caption)
                            }
                        }
                    } else {
                        Text("Unrecorded Play")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    
                    if let game = clip.game {
                        Text("vs \(game.opponent)")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    } else if let practice = clip.practice {
                        Text("Practice - \(practice.date, formatter: DateFormatter.shortDate)")
                            .font(.subheadline)
                            .foregroundColor(.green)
                    } else {
                        Text("Practice")
                            .font(.subheadline)
                            .foregroundColor(.green)
                    }
                    
                    Text(clip.createdAt, formatter: DateFormatter.mediumDateTime)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // Helper functions for play result styling
    private func playResultIcon(for type: PlayResultType) -> Image {
        switch type {
        case .single:
            return Image(systemName: "1.circle.fill")
        case .double:
            return Image(systemName: "2.circle.fill")
        case .triple:
            return Image(systemName: "3.circle.fill")
        case .homeRun:
            return Image(systemName: "4.circle.fill")
        case .walk:
            return Image(systemName: "figure.walk")
        case .strikeout:
            return Image(systemName: "k.circle.fill")
        case .groundOut:
            return Image(systemName: "arrow.down.circle.fill")
        case .flyOut:
            return Image(systemName: "arrow.up.circle.fill")
        }
    }
    
    private func playResultAbbreviation(for type: PlayResultType) -> String {
        switch type {
        case .single:
            return "1B"
        case .double:
            return "2B"
        case .triple:
            return "3B"
        case .homeRun:
            return "HR"
        case .walk:
            return "BB"
        case .strikeout:
            return "K"
        case .groundOut:
            return "GO"
        case .flyOut:
            return "FO"
        }
    }
    
    private func playResultColor(for type: PlayResultType) -> Color {
        switch type {
        case .single:
            return .green
        case .double:
            return .blue
        case .triple:
            return .orange
        case .homeRun:
            return .red
        case .walk:
            return .cyan
        case .strikeout:
            return .red.opacity(0.8)
        case .groundOut, .flyOut:
            return .gray
        }
    }
}

struct VideoPlayerView: View {
    let clip: VideoClip
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    
    var body: some View {
        NavigationStack {
            VStack {
                if let player = player {
                    VideoPlayer(player: player)
                        .onAppear {
                            player.play()
                        }
                        .onDisappear {
                            player.pause()
                        }
                } else {
                    Rectangle()
                        .fill(Color.black)
                        .overlay(
                            ProgressView("Loading...")
                                .foregroundColor(.white)
                        )
                }
                
                // Video Info
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        VStack(alignment: .leading) {
                            if let playResult = clip.playResult {
                                Text(playResult.type.rawValue)
                                    .font(.title2)
                                    .fontWeight(.bold)
                            } else {
                                Text("Unrecorded Play")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                            }
                            
                            if let game = clip.game {
                                Text("vs \(game.opponent)")
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                                
                                Text(game.date, formatter: DateFormatter.shortDate)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else if let practice = clip.practice {
                                Text("Practice Session")
                                    .font(.subheadline)
                                    .foregroundColor(.green)
                                
                                Text(practice.date, formatter: DateFormatter.shortDate)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        if clip.isHighlight {
                            VStack {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                    .font(.title2)
                                
                                Text("Highlight")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    
                    Text("Recorded: \(clip.createdAt, formatter: DateFormatter.mediumDateTime)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    ShareLink(item: URL(fileURLWithPath: clip.filePath)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
    
    private func setupPlayer() {
        let url = URL(fileURLWithPath: clip.filePath)
        player = AVPlayer(url: url)
    }
}

// Helper extension for date formatting
extension DateFormatter {
    static let mediumDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

#Preview {
    VideoClipsView(athlete: nil)
}