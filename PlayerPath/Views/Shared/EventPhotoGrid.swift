//
//  EventPhotoGrid.swift
//  PlayerPath
//
//  Shared thumbnail grid for photos attached to a game/round or practice.
//  Used by GameDetailView and PracticeDetailView (replaced the old
//  EventPhotoRow list rows). Same grid idiom as JournalPhotoDaySheet /
//  PhotosView dense mode: square PhotoThumbnailCells, 3-up, tight gutters.
//

import SwiftUI

struct EventPhotoGrid: View {
    let photos: [Photo]
    let onDelete: (Photo) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(photos) { photo in
                NavigationLink {
                    PhotoDetailView(photo: photo) {
                        onDelete(photo)
                    }
                } label: {
                    PhotoThumbnailCell(photo: photo, style: .dense) {
                        onDelete(photo)
                    }
                }
                // Plain style keeps each cell an independent tap target
                // inside the single List row the grid occupies.
                .buttonStyle(.plain)
            }
        }
    }
}
