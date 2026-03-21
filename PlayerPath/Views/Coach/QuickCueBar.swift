//
//  QuickCueBar.swift
//  PlayerPath
//
//  Horizontal scrolling bar of quick-tap coaching cues.
//  Shown below the video player. Tap = instant annotation at current timestamp.
//

import SwiftUI

struct QuickCueBar: View {
    let cues: [QuickCue]
    let onTap: (QuickCue) -> Void
    let onManage: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(cues) { cue in
                    Button {
                        onTap(cue)
                    } label: {
                        HStack(spacing: 4) {
                            if let cat = cue.annotationCategory {
                                Circle()
                                    .fill(cat.color)
                                    .frame(width: 6, height: 6)
                            }
                            Text(cue.text)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .cornerRadius(16)
                    }
                    .buttonStyle(.plain)
                }

                // Manage button
                Button(action: onManage) {
                    Image(systemName: "ellipsis.circle")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .background(Color(.secondarySystemBackground).opacity(0.8))
    }
}
