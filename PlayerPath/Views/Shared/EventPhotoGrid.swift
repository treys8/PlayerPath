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

    // Tapping a cell opens a full-screen, swipeable viewer. A NavigationLink
    // here is unreliable: this grid lives in a LazyVGrid inside a List row, where
    // eager links double-push and strand the user with no working close button.
    @State private var viewerPhoto: Photo?
    @Namespace private var photoNS

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(photos) { photo in
                Button {
                    viewerPhoto = photo
                } label: {
                    PhotoThumbnailCell(photo: photo, style: .dense) {
                        onDelete(photo)
                    }
                    .photoTransitionSource(photo.id, in: photoNS)
                }
                // Plain style keeps each cell an independent tap target
                // inside the single List row the grid occupies.
                .buttonStyle(.plain)
            }
        }
        .photoViewer($viewerPhoto, in: photos, namespace: photoNS, onDelete: onDelete)
    }
}
