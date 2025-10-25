//
//  HighlightsView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import SwiftData

struct HighlightsView: View {
    let athlete: Athlete?
    @State private var selectedClip: VideoClip?
    @State private var showingVideoPlayer = false
    
    var highlights: [VideoClip] {
        athlete?.videoClips.filter { $0.isHighlight }.sorted { $0.createdAt > $1.createdAt } ?? []
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if highlights.isEmpty {
                    EmptyHighlightsView()
                } else {
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 15) {
                            ForEach(highlights) { clip in
                                HighlightCard(clip: clip) {
                                    selectedClip = clip
                                    showingVideoPlayer = true
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Highlights")
        }
        .sheet(isPresented: $showingVideoPlayer) {
            if let clip = selectedClip {
                VideoPlayerView(clip: clip)
            }
        }
    }
}

struct EmptyHighlightsView: View {
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "star")
                .font(.system(size: 80))
                .foregroundColor(.yellow)
            
            Text("No Highlights Yet")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Record some great plays! Singles, doubles, triples, and home runs automatically become highlights")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

struct HighlightCard: View {
    let clip: VideoClip
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Video thumbnail area
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: playResultGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 120)
                    .overlay(
                        VStack {
                            Image(systemName: "play.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                            
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundColor(.yellow)
                        }
                    )
                
                // Info overlay at bottom
                VStack(alignment: .leading, spacing: 4) {
                    if let playResult = clip.playResult {
                        Text(playResult.type.rawValue)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                    }
                    
                    if let game = clip.game {
                        Text("vs \(game.opponent)")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                        
                        Text(game.date, formatter: DateFormatter.shortDate)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Practice")
                            .font(.subheadline)
                            .foregroundColor(.green)
                        
                        Text(clip.createdAt, formatter: DateFormatter.shortDate)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
            }
        }
        .buttonStyle(PlainButtonStyle())
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
    
    private var playResultGradient: [Color] {
        guard let playResult = clip.playResult else { return [.gray, .gray.opacity(0.7)] }
        
        switch playResult.type {
        case .single:
            return [.green, .green.opacity(0.7)]
        case .double:
            return [.blue, .blue.opacity(0.7)]
        case .triple:
            return [.orange, .orange.opacity(0.7)]
        case .homeRun:
            return [.red, .red.opacity(0.7)]
        default:
            return [.gray, .gray.opacity(0.7)]
        }
    }
}

#Preview {
    HighlightsView(athlete: nil)
}