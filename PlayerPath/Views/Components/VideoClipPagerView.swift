//
//  VideoClipPagerView.swift
//  PlayerPath
//
//  Full-screen player with previous/next through a list of clips (the Videos
//  tab's filtered set). Buttons, not a swipe pager: horizontal drags belong to
//  the scrubber, and each page of a pager would hold its own AVPlayer and
//  coach-annotation listener.
//

import SwiftUI

/// Prev/next state handed to `VideoPlayerView`. A nil closure disables that
/// direction (start or end of the list).
struct ClipNavigation {
    let position: Int
    let total: Int
    let onPrevious: (() -> Void)?
    let onNext: (() -> Void)?
}

/// Identifies one presentation of the pager (`fullScreenCover(item:)`).
struct VideoPlayerSession: Identifiable {
    let id = UUID()
    let clipIDs: [UUID]
    let startID: UUID
}

struct VideoClipPagerView: View {
    let athlete: Athlete
    /// IDs, never models: a clip deleted or moved to another athlete while the
    /// player is open must not be held here, or touching it traps. Each ID is
    /// resolved against the live relationship on every render.
    let clipIDs: [UUID]

    @State private var currentID: UUID
    /// One speed for the whole prev/next session — each clip gets a fresh
    /// player (`.id(clip.id)`), so it can't live in the player's own @State.
    @State private var playbackSpeed: PlaybackSpeed = .normal
    @Environment(\.dismiss) private var dismiss

    init(athlete: Athlete, session: VideoPlayerSession) {
        self.athlete = athlete
        self.clipIDs = session.clipIDs
        self._currentID = State(initialValue: session.startID)
    }

    private func resolve(_ id: UUID) -> VideoClip? {
        athlete.videoClips?.first { $0.id == id }
    }

    /// Nearest ID in `direction` from `currentID` that still resolves.
    private func neighbor(_ direction: Int) -> UUID? {
        guard let index = clipIDs.firstIndex(of: currentID) else { return nil }
        var i = index + direction
        while clipIDs.indices.contains(i) {
            if resolve(clipIDs[i]) != nil { return clipIDs[i] }
            i += direction
        }
        return nil
    }

    var body: some View {
        if let clip = resolve(currentID) {
            let previous = neighbor(-1)
            let next = neighbor(1)
            VideoPlayerView(
                clip: clip,
                navigation: clipIDs.count > 1 ? ClipNavigation(
                    position: (clipIDs.firstIndex(of: currentID) ?? 0) + 1,
                    total: clipIDs.count,
                    onPrevious: previous.map { id in { currentID = id } },
                    onNext: next.map { id in { currentID = id } }
                ) : nil,
                playbackSpeed: $playbackSpeed
            )
            // A fresh identity per clip rebuilds the player's @State, runs its
            // onDisappear teardown (pause + listener removal), and re-runs its
            // .task — so exactly one AVPlayer is alive at a time.
            .id(clip.id)
        } else {
            // The current clip was deleted or moved away mid-view. Step to a
            // surviving neighbor, or close when none is left.
            Color.black
                .ignoresSafeArea()
                .task {
                    if let replacement = neighbor(1) ?? neighbor(-1) {
                        currentID = replacement
                    } else {
                        dismiss()
                    }
                }
        }
    }
}
