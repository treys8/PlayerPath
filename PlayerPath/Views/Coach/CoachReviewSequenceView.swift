//
//  CoachReviewSequenceView.swift
//  PlayerPath
//
//  Lets a coach step through an ordered list of clips in a single review
//  session (next / previous) instead of backing out to the folder between each
//  one. Pushed once; the inner CoachVideoPlayerView is keyed by clip id so
//  SwiftUI fully rebuilds the player — and its viewModel, observers, and loads —
//  on each clip change, which is the cleanest teardown/reload in SwiftUI.
//

import SwiftUI

/// 1-based position of a clip within a review sequence, for the "n of m" label.
struct CoachReviewSequencePosition {
    let current: Int
    let total: Int
}

struct CoachReviewSequenceView: View {
    let folder: SharedFolder
    /// Snapshot of the ordered clip list at the moment review began. Intentionally
    /// fixed for the session — paginating or re-filtering the folder underneath
    /// doesn't reshuffle the sequence the coach is stepping through.
    let clips: [CoachVideoItem]
    @State private var index: Int

    init(folder: SharedFolder, clips: [CoachVideoItem], startIndex: Int) {
        self.folder = folder
        self.clips = clips
        _index = State(initialValue: min(max(startIndex, 0), max(clips.count - 1, 0)))
    }

    var body: some View {
        if clips.indices.contains(index) {
            let clip = clips[index]
            CoachVideoPlayerView(
                folder: folder,
                video: clip,
                onNext: index < clips.count - 1 ? { advance(by: 1) } : nil,
                onPrevious: index > 0 ? { advance(by: -1) } : nil,
                sequencePosition: CoachReviewSequencePosition(
                    current: index + 1,
                    total: clips.count
                )
            )
            .id(clip.id)
        }
    }

    private func advance(by delta: Int) {
        let next = index + delta
        guard clips.indices.contains(next) else { return }
        index = next
    }
}
