//
//  VideoRecorderView_Refactored.swift
//  PlayerPath
//
//  Created by Xcode on 11/2/25.
//

import SwiftUI

struct VideoRecorderView_Refactored: View {
    let athlete: Athlete?
    let game: Game?
    let practice: Practice?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "video.badge.plus")
                    .font(.system(size: 60))
                    .foregroundColor(.red)
                
                Text("Video Recorder")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                if let athlete = athlete {
                    Text("Recording for \(athlete.name)")
                        .font(.title2)
                        .foregroundColor(.secondary)
                } else {
                    Text("No athlete selected")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                
                Text("Video recording feature coming soon")
                    .font(.headline)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Record Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    VideoRecorderView_Refactored(athlete: nil, game: nil, practice: nil)
}