//
//  VideoTagFilterBar.swift
//  PlayerPath
//
//  Horizontal scrolling tag filter bar for filtering videos by tag.
//

import SwiftUI

struct VideoTagFilterBar: View {
    let tags: [String]
    @Binding var selectedTag: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" chip
                TagChip(
                    text: "All",
                    isSelected: selectedTag == nil,
                    onTap: {
                        selectedTag = nil
                        Haptics.selection()
                    }
                )

                ForEach(tags, id: \.self) { tag in
                    TagChip(
                        text: tag,
                        isSelected: selectedTag == tag,
                        onTap: {
                            selectedTag = selectedTag == tag ? nil : tag
                            Haptics.selection()
                        }
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .background(Color(.secondarySystemBackground).opacity(0.5))
    }
}
