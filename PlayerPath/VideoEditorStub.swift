//
//  VideoEditorStub.swift
//  PlayerPath
//
//  Temporary video editor placeholder extracted for reuse.
//

import SwiftUI

struct VideoEditorStub: View {
    let clip: VideoClip
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "scissors")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text("Video Editor")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Coming Soon")
                    .font(.title2)
                    .foregroundColor(.secondary)
                
                Text("Advanced video editing features will be available in a future update.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Edit Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    // Provide a lightweight preview using a mock clip
    let mock = VideoClip(fileName: "mock.mov", filePath: "/tmp/mock.mov")
    return VideoEditorStub(clip: mock)
}
