//
//  SharedFolderCard.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI

struct SharedFolderCard: View {
    let folder: SharedFolder
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundColor(.blue)
                
                Text(folder.name)
                    .font(.headline)
                
                Spacer()
                
                if let videoCount = folder.videoCount {
                    Text("\(videoCount) videos")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if let updatedAt = folder.updatedAt {
                Text("Last updated: \(updatedAt, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .appCard()
    }
}
