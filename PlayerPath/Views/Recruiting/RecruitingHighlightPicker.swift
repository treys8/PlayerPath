//
//  RecruitingHighlightPicker.swift
//  PlayerPath
//
//  Curates which highlight clips appear on the published profile, and in what
//  order — the first clip is the page's hero player.
//
//  Only clips that finished uploading can be published: the page serves signed
//  URLs to `athlete_videos/`, so a local-only clip would render as a broken
//  player on a coach's screen. Un-uploaded highlights are shown greyed rather
//  than hidden — an athlete who flagged a clip should see it here, with a reason
//  it can't be picked yet.
//

import SwiftUI
import SwiftData

struct RecruitingHighlightPicker: View {
    let athlete: Athlete
    @Binding var selection: [UUID]

    @Environment(\.ppAccent) private var ppAccent

    /// The clip open in the full-screen player. Picking the hero clip from a
    /// 72-point thumbnail and a caption was guesswork.
    @State private var playingClip: VideoClip?

    private var atCap: Bool { selection.count >= RecruitingProfileService.maxHighlights }

    var body: some View {
        // Everything derives from ONE read of `recruitingHighlights` per render.
        // These used to be computed properties that each re-read it — on a golf
        // athlete that's a SwiftData fetch (the birdie-reel union) apiece, four-plus
        // times per redraw.
        let allHighlights = athlete.recruitingHighlights
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        let publishable = allHighlights.filter(\.hasPublishableUpload)
        let pending = allHighlights.filter { !$0.hasPublishableUpload }
        // Selected clips in the athlete's chosen order (the page's display order).
        let byID = Dictionary(publishable.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let selectedClips = selection.compactMap { byID[$0] }

        List {
            if !selectedClips.isEmpty {
                Section {
                    ForEach(selectedClips) { clip in
                        clipRow(clip, isOn: true)
                    }
                    .onMove(perform: move)
                } header: {
                    Text("On your profile (\(selection.count) of \(RecruitingProfileService.maxHighlights))")
                } footer: {
                    Text(selection.count > 1
                         ? "The first clip is the big one at the top of your page. Tap Edit to reorder."
                         : "This clip is the big one at the top of your page.")
                }
            }

            let unselected = publishable.filter { !selection.contains($0.id) }
            if !unselected.isEmpty {
                Section {
                    ForEach(unselected) { clip in
                        clipRow(clip, isOn: false)
                    }
                } header: {
                    Text("Your highlights")
                } footer: {
                    // At the cap these rows are disabled, and without this they are
                    // just greyed out for no stated reason — especially for someone
                    // who arrived from the editor's "new highlights aren't on your
                    // page yet" nudge and came here to add exactly these.
                    if atCap {
                        Text("Your page holds \(RecruitingProfileService.maxHighlights) clips. Remove one above to add another.")
                    }
                }
            }

            if !pending.isEmpty {
                Section {
                    ForEach(pending) { clip in
                        clipRow(clip, isOn: false, isPending: true)
                    }
                } header: {
                    Text("Still uploading")
                } footer: {
                    Text("These finish uploading in the background, usually on Wi-Fi. They can be added once they're done.")
                }
            }

            if allHighlights.isEmpty {
                Section {
                    Text("Flag your best clips as highlights to feature them here.")
                        .font(.bodySmall)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Choose Clips")
        .navigationBarTitleDisplayMode(.inline)
        .tint(ppAccent)
        .ppAccent(for: athlete.sport)
        .toolbar {
            // Edit mode is a MODE, not the default: pinning it active would put
            // every section into edit state and swallow the taps that toggle
            // selection. Tap to pick; tap Edit to drag. Same shape as
            // TournamentDetailView, the app's other .onMove list.
            //
            // No separate "Done" to leave: this screen is pushed, so Back does
            // that — and while editing, EditButton ALSO reads "Done", which put two
            // identical buttons on screen doing different things.
            if selection.count > 1 {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
        }
        .fullScreenCover(item: $playingClip) { clip in
            VideoPlayerView(clip: clip)
        }
    }

    // MARK: - Rows

    private func clipRow(_ clip: VideoClip, isOn: Bool, isPending: Bool = false) -> some View {
        // At the cap, unselected rows stop responding rather than silently no-op.
        let isDisabled = isPending || (!isOn && atCap)
        return HStack(spacing: 12) {
            // Its own button so any clip can be watched — including still-uploading
            // and at-cap ones, which can't be toggled. Both buttons are .plain so a
            // List row doesn't hand every tap to the first one.
            Button {
                playingClip = clip
            } label: {
                VideoThumbnailView(
                    clip: clip,
                    size: CGSize(width: 72, height: 40),
                    cornerRadius: 8,
                    showPlayResult: false,
                    showHighlight: false,
                    showSeason: false,
                    showContext: false,
                    showDuration: true,
                    fillsContainer: false
                )
                .frame(width: 72, height: 40)
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play clip")

            Button {
                toggle(clip)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(clip.recruitingLabel.isEmpty ? "Clip" : clip.recruitingLabel)
                            .font(.bodyMedium)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if isPending {
                            Label("Uploading…", systemImage: "arrow.up.circle")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if !isPending {
                        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isOn ? ppAccent : Theme.textTertiary)
                    }
                }
                .contentShape(Rectangle())
                .opacity(isDisabled ? 0.45 : 1)
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
        }
    }

    // MARK: - Mutation

    private func toggle(_ clip: VideoClip) {
        if let index = selection.firstIndex(of: clip.id) {
            selection.remove(at: index)
        } else if !atCap {
            selection.append(clip.id)
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        selection.move(fromOffsets: source, toOffset: destination)
    }
}

// MARK: - Publishability

extension VideoClip {
    /// A clip can only be published once its file is in Firebase Storage — the
    /// public page serves a signed URL to `athlete_videos/`, and there's nothing
    /// to sign until the upload lands. Apply to `Athlete.recruitingHighlights`,
    /// never to raw `videoClips` — this is the upload gate only, not "is a highlight".
    var hasPublishableUpload: Bool {
        isUploaded && cloudURL != nil && !fileName.isEmpty
    }
}

extension Athlete {
    /// Every clip that counts as a highlight for the recruiting page, still-uploading
    /// ones included. THE single definition — the picker, preview strip, stale-clip
    /// nudge and publish defaults must agree on it.
    ///
    /// Golf unions the birdie-or-better reel clips (GolfHighlightUnion): golf never
    /// auto-stars, so a starred-only set left a golfer's best holes unpickable unless
    /// each clip had been starred by hand.
    @MainActor
    var recruitingHighlights: [VideoClip] {
        let clips = videoClips ?? []
        guard sport == .golf, let modelContext else { return clips.filter(\.isHighlight) }
        let reelClipIDs = GolfHighlightUnion.reelClipIDStrings(
            gameIDs: Set((games ?? []).map(\.id)),
            practiceIDs: Set((practices ?? []).map(\.id)),
            in: modelContext
        )
        return clips.filter { $0.isHighlight || reelClipIDs.contains($0.id.uuidString) }
    }
}
