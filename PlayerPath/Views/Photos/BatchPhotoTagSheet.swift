//
//  BatchPhotoTagSheet.swift
//  PlayerPath
//
//  Sheet to tag MANY selected photos to one game/round or practice at once.
//  Wraps the shared EventTargetPicker; PhotosView applies the chosen target
//  across the whole selection in one save.
//

import SwiftUI

struct BatchPhotoTagSheet: View {
    let athlete: Athlete
    let photoCount: Int
    let onSelect: (EventTargetPicker.Target) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            EventTargetPicker(athlete: athlete) { target in
                onSelect(target)
                dismiss()
            }
            .ppDetailBackground()
            .navigationTitle(photoCount == 1 ? "Tag 1 Photo" : "Tag \(photoCount) Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
