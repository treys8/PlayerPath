//
//  PlayResultOverlayView.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/23/25.
//

import SwiftUI
import SwiftData
import AVKit

struct PlayResultOverlayView: View {
    let videoURL: URL
    let athlete: Athlete?
    let game: Game?
    let practice: Practice?
    let onSave: (PlayResultType?) -> Void
    let onCancel: () -> Void
    
    @State private var selectedResult: PlayResultType?
    @State private var showingConfirmation = false
    
    init(videoURL: URL, athlete: Athlete?, game: Game? = nil, practice: Practice? = nil, onSave: @escaping (PlayResultType?) -> Void, onCancel: @escaping () -> Void) {
        self.videoURL = videoURL
        self.athlete = athlete
        self.game = game
        self.practice = practice
        self.onSave = onSave
        self.onCancel = onCancel
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Video Player Background
                VideoPlayer(player: AVPlayer(url: videoURL))
                    .disabled(true)
                    .overlay(Color.black.opacity(0.3))
                
                // Play Result Selection Overlay
                VStack {
                    Spacer()
                    
                    VStack(spacing: 20) {
                        if practice != nil {
                            Text("Add play result for statistics tracking?")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                        } else {
                            Text("What was the result of this play?")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                        }
                        
                        // Play Result Grid
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 15) {
                            ForEach(PlayResultType.allCases, id: \.self) { result in
                                PlayResultButton(
                                    result: result,
                                    isSelected: selectedResult == result
                                ) {
                                    selectedResult = result
                                    showingConfirmation = true
                                }
                            }
                        }
                        
                        // Action Buttons
                        HStack(spacing: 20) {
                            Button("Cancel") {
                                onCancel()
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.gray.opacity(0.3))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            
                            Button(practice != nil ? "Save Video Only" : "Skip & Save") {
                                // Save without play result
                                onSave(nil)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.black.opacity(0.8))
                            .background(.ultraThinMaterial)
                    )
                    .padding()
                    
                    Spacer().frame(height: 50)
                }
                
                // Info Header
                VStack {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            if let game = game {
                                Text("vs \(game.opponent)")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                
                                Text(game.date, formatter: DateFormatter.shortDate)
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.8))
                            } else if let practice = practice {
                                Text("Practice Session")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                
                                Text(practice.date, formatter: DateFormatter.shortDate)
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            
                            if let athlete = athlete {
                                Text(athlete.name)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        
                        Spacer()
                        
                        Button("Done") {
                            // This will be handled by individual result selection
                        }
                        .foregroundColor(.white)
                        .opacity(0) // Hidden for now
                    }
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [Color.black.opacity(0.6), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    
                    Spacer()
                }
            }
            .ignoresSafeArea()
            .navigationBarHidden(true)
        }
        .alert("Confirm Play Result", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) {
                selectedResult = nil
            }
            Button("Save") {
                if let result = selectedResult {
                    onSave(result)
                }
            }
        } message: {
            if let result = selectedResult {
                Text("Save this play as a \(result.rawValue)?")
            }
        }
    }
}

struct PlayResultButton: View {
    let result: PlayResultType
    let isSelected: Bool
    let action: () -> Void
    
    private var backgroundColor: Color {
        switch result {
        case .single, .double, .triple, .homeRun:
            return .green
        case .walk:
            return .blue
        case .strikeout, .groundOut, .flyOut:
            return .red
        }
    }
    
    private var icon: String {
        switch result {
        case .single:
            return "1.circle.fill"
        case .double:
            return "2.circle.fill"
        case .triple:
            return "3.circle.fill"
        case .homeRun:
            return "4.circle.fill"
        case .walk:
            return "figure.walk"
        case .strikeout:
            return "k.circle.fill"
        case .groundOut:
            return "arrow.down.circle.fill"
        case .flyOut:
            return "arrow.up.circle.fill"
        }
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                
                Text(result.rawValue)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(height: 80)
            .frame(maxWidth: .infinity)
            .background(
                backgroundColor.opacity(isSelected ? 1.0 : 0.8)
            )
            .cornerRadius(12)
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .animation(.spring(response: 0.3), value: isSelected)
        }
    }
}

// MARK: - Preview
#Preview {
    PlayResultOverlayView(
        videoURL: URL(string: "https://sample-videos.com/zip/10/mp4/SampleVideo_1280x720_1mb.mp4")!,
        athlete: nil,
        game: nil,
        onSave: { _ in },
        onCancel: { }
    )
}