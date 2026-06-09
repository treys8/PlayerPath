//
//  ReelPlayerView.swift
//  PlayerPath
//
//  AVQueuePlayer playback for HighlightReel — chains the referenced clips on
//  the fly with no re-encoding (v6.1 PR2). Prefers local files; falls back to
//  Firebase Storage URLs for cross-device playback before clips download.
//  Skips unresolvable clips silently; shows an "unavailable" state only when
//  zero clips can be played.
//
//  Distinct from StitchedReelPlayerView (baseball's TodaysReel) which plays a
//  single pre-rendered MP4 — golf reels are virtual queues.
//

import SwiftUI
import SwiftData
import AVKit

struct ReelPlayerView: View {
    let reel: HighlightReel

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVQueuePlayer?
    @State private var didResolve: Bool = false
    /// End-of-queue observer on the last item — without it the reel freezes on
    /// the final frame with no callback.
    @State private var endObserver: NSObjectProtocol?
    /// Per-item `status` observers — surface the unavailable state instead of a
    /// silent black screen when every item fails to load (e.g. expired URLs).
    @State private var statusObservations: [NSKeyValueObservation] = []

    /// Export flow — golf reels are virtual at playback, so Save/Share stitches
    /// the referenced clips into one MP4 on demand via GenerateReelView.
    @State private var showingExport = false
    @State private var exportClips: [VideoClip] = []

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else if didResolve {
                unavailableView
            }

            HStack {
                Button {
                    player?.pause()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.white, .black.opacity(0.5))
                }
                Spacer()
                // Only offer export once something is playable. Stitching itself
                // needs local files; GenerateReelView surfaces a friendly message
                // if the clips haven't downloaded to this device yet.
                if player != nil {
                    Button {
                        Haptics.light()
                        presentExport()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title3)
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Save or share this reel")
                }
            }
            .padding()
        }
        .onAppear {
            AudioSessionManager.configureForPlayback()
            resolveAndPlay()
        }
        .onDisappear { teardownPlayer() }
        .fullScreenCover(isPresented: $showingExport) {
            GenerateReelView(
                clips: exportClips,
                scopeKey: "reel_\(reel.id.uuidString)",
                title: reelExportTitle
            )
        }
    }

    private var reelExportTitle: String {
        reel.courseOrOpponent.isEmpty
            ? reel.displayName
            : "\(reel.displayName) · \(reel.courseOrOpponent)"
    }

    /// Resolve the reel's clips in chronological order, pause playback, and present
    /// the on-demand stitch/export surface.
    private func presentExport() {
        let ordered = fetchOrderedClips()
        guard !ordered.isEmpty else { return }
        exportClips = ordered
        player?.pause()
        showingExport = true
    }

    /// Fetch the reel's clips and restore `clipIDs` order. Shared by playback and
    /// export. Tolerates duplicate ids (multi-device row duplication); returns []
    /// on fetch failure (caller falls back to the unavailable state).
    private func fetchOrderedClips() -> [VideoClip] {
        let clipIDStrings = reel.clipIDs
        let clipUUIDs: [UUID] = clipIDStrings.compactMap { UUID(uuidString: $0) }
        guard !clipUUIDs.isEmpty else { return [] }
        let fetched: [VideoClip]
        do {
            let descriptor = FetchDescriptor<VideoClip>(
                predicate: #Predicate<VideoClip> { clip in
                    clipUUIDs.contains(clip.id)
                }
            )
            fetched = try modelContext.fetch(descriptor)
        } catch {
            ErrorHandlerService.shared.handle(
                error,
                context: "ReelPlayerView.fetchOrderedClips",
                showAlert: false
            )
            return []
        }
        let clipsByID: [String: VideoClip] = Dictionary(
            fetched.map { ($0.id.uuidString, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )
        return clipIDStrings.compactMap { clipsByID[$0] }
    }

    /// Pauses, drains the queue, and clears all observers. Safe to call
    /// repeatedly; runs on dismiss and at the top of every (re)resolve so a
    /// retry can't leave an old player/observers alive.
    private func teardownPlayer() {
        player?.pause()
        player?.removeAllItems()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        statusObservations.forEach { $0.invalidate() }
        statusObservations = []
        player = nil
    }

    @ViewBuilder
    private var unavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "film.stack")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.7))
            Text("Reel Unavailable")
                .font(.headingMedium)
                .foregroundStyle(.white)
            Text("Clips may still be uploading. Try again in a moment.")
                .font(.bodySmall)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                resolveAndPlay()
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.bodyMedium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(.white.opacity(0.15)))
            }
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Fetch clips by UUID, re-sort to chronological reel order, then resolve
    /// each to a playable URL. Local file first; cloudURL second; skipped if
    /// neither resolves. Empty result yields the unavailable UI.
    private func resolveAndPlay() {
        // Tear down any prior player/observers first (covers the Retry path).
        teardownPlayer()

        // Restore the reel's chronological order. Shared with the export path;
        // tolerates duplicate ids and returns [] on fetch failure.
        let orderedClips = fetchOrderedClips()
        guard !orderedClips.isEmpty else {
            player = nil
            didResolve = true
            return
        }

        // Resolve to playable URLs.
        let urls: [URL] = orderedClips.compactMap { clip in
            let localPath = clip.resolvedFilePath
            if FileManager.default.fileExists(atPath: localPath) {
                return URL(fileURLWithPath: localPath)
            }
            if let cloud = clip.cloudURL, let cloudURL = URL(string: cloud) {
                return cloudURL
            }
            return nil
        }

        didResolve = true

        guard !urls.isEmpty else {
            player = nil
            return
        }

        let items = urls.map { AVPlayerItem(url: $0) }
        let queue = AVQueuePlayer(items: items)

        // Dismiss when the last item finishes, instead of freezing on the
        // final frame. AVQueuePlayer auto-advances, so the last item's
        // end notification marks the whole reel done.
        if let lastItem = items.last {
            endObserver = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification,
                object: lastItem,
                queue: .main
            ) { _ in
                dismiss()
            }
        }

        // If every remaining item fails to load (e.g. expired Storage URLs),
        // fall back to the unavailable state rather than a silent black screen.
        statusObservations = items.map { item in
            item.observe(\.status, options: [.new]) { _, _ in
                DispatchQueue.main.async {
                    // Capture the concrete queue, not the `player` @State, which
                    // isn't assigned until after these observers are wired. Reading
                    // `player` here would early-return on any failure that lands
                    // before that assignment. teardownPlayer() invalidates these
                    // observers, so the closure can't fire after we're done.
                    let remaining = queue.items()
                    if !remaining.isEmpty, remaining.allSatisfy({ $0.status == .failed }) {
                        teardownPlayer()  // player = nil → unavailableView (didResolve is already true)
                    }
                }
            }
        }

        player = queue
        queue.play()
    }
}
