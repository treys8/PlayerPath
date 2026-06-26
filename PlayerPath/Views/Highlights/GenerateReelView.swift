//
//  GenerateReelView.swift
//  PlayerPath
//
//  Full-screen "generate → play → export" surface for a stitched highlight reel.
//  One surface for every retrospective reel: per-game, per-season, and golf
//  per-hole on-demand export. Drives ReelStitchCoordinator over a passed-in clip
//  set and presents ReelExportControls once ready.
//
//  Distinct from TodaysReelHeroCard (an inline hero on the Highlights grid) and
//  ReelPlayerView (golf virtual-queue playback); this is a modal export flow.
//

import SwiftUI
import AVKit

struct GenerateReelView: View {
    /// Clips to stitch, in playback order (chronological for game/season reels).
    let clips: [VideoClip]
    /// StitchedReelCache scope, e.g. "game_<uuid>", "season_<uuid>", "reel_<uuid>".
    let scopeKey: String
    /// Header label shown while generating, e.g. "vs Tigers · Jun 8". Also seeds the
    /// social-export caption.
    let title: String
    /// Athlete name for the optional overlay (nil ⇒ no name toggle in the options sheet).
    var athleteName: String? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var coordinator = ReelStitchCoordinator()
    @State private var player: AVPlayer?
    /// Currently-applied social-export options. `.default` reproduces today's reel.
    @State private var options: ReelExportOptions = .default
    @State private var showingOptions = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            content
            topBar
        }
        .onAppear {
            guard !clips.isEmpty else { return }
            coordinator.generate(clips: clips, scopeKey: scopeKey, options: options)
        }
        .onChange(of: coordinator.state) { _, newState in
            if case .ready(let url) = newState { setupPlayer(url) }
        }
        .onDisappear {
            coordinator.cancel()
            teardownPlayer()
        }
        .sheet(isPresented: $showingOptions) {
            ReelExportOptionsView(
                athleteName: resolvedAthleteName,
                initial: seededOptions
            ) { newOptions in
                applyOptions(newOptions)
            }
        }
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        if clips.isEmpty {
            messageView(
                icon: "film.stack",
                title: "No Highlights Yet",
                message: "Star some clips first, then come back to build a reel."
            )
        } else {
            switch coordinator.state {
            case .idle, .generating:
                generatingView
            case .ready:
                if let player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                }
            case .failed(let message):
                failedView(message)
            }
        }
    }

    private var generatingView: some View {
        VStack(spacing: 18) {
            ProgressView(value: progressValue)
                .progressViewStyle(.circular)
                .tint(.white)
                .scaleEffect(1.4)
            Text("Building your reel…")
                .font(.headingMedium)
                .foregroundStyle(.white)
            Text(title)
                .font(.bodySmall)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            Text("\(Int(progressValue * 100))%")
                .font(.labelSmall)
                .foregroundStyle(.white.opacity(0.6))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.warning)
            Text("Couldn't Build Reel")
                .font(.headingMedium)
                .foregroundStyle(.white)
            Text(message)
                .font(.bodySmall)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                Haptics.light()
                coordinator.generate(clips: clips, scopeKey: scopeKey, options: options)
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

    private func messageView(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.7))
            Text(title)
                .font(.headingMedium)
                .foregroundStyle(.white)
            Text(message)
                .font(.bodySmall)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Top bar (close + export)

    private var topBar: some View {
        VStack(spacing: 6) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.white, .black.opacity(0.5))
                }
                Spacer()
                if case .ready(let url) = coordinator.state {
                    HStack(spacing: 16) {
                        // Social overlay + 9:16 are a Plus+ perk (parity with reel
                        // generation). Basic Save/Share stays available regardless of
                        // how this surface was reached.
                        if canCustomize {
                            Button {
                                Haptics.light()
                                showingOptions = true
                            } label: {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.title3)
                                    .foregroundStyle(.white)
                            }
                            .accessibilityLabel("Customize reel for social")
                        }
                        ReelExportControls(url: url)
                    }
                }
            }
            if isPartial {
                HStack {
                    Spacer()
                    Text("Built from \(coordinator.usableCount) of \(coordinator.requestedCount) clips · others still syncing")
                        .font(.labelSmall)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.black.opacity(0.4)))
                }
            }
        }
        .padding()
    }

    // MARK: - Social-export options

    /// The overlay/9:16 customization is a Plus+ perk. Most surfaces already gate the
    /// whole reel behind this; checking here also covers any ungated entry point (e.g.
    /// the golf reel player) so the social options never leak to free users.
    private var canCustomize: Bool {
        SubscriptionGate.effectiveAthleteTier.hasAutoHighlights
    }

    /// Athlete name for the overlay. Prefers an explicitly-passed name, else derives it
    /// from the clips (every reel's clips belong to one athlete) so the prefill works on
    /// all surfaces — including golf, where no Athlete is held directly.
    private var resolvedAthleteName: String? {
        if let athleteName, !athleteName.isEmpty { return athleteName }
        return clips.lazy.compactMap { $0.athlete?.name }.first
    }

    /// Options to seed the sheet with. When nothing custom is applied yet, pre-fill the
    /// name (athlete) + caption (reel title) so the common case is one tap; once the user
    /// has applied a real variant, reopen with their current choices.
    private var seededOptions: ReelExportOptions {
        guard options.isVisuallyDefault else { return options }
        return ReelExportOptions(
            nameText: resolvedAthleteName,
            captionText: title,
            aspect: options.aspect,
            cropMode: options.cropMode
        )
    }

    /// Apply new options and re-stitch the matching variant (cache-keyed by the options
    /// suffix, so a previously-built variant returns instantly). No-op if unchanged.
    private func applyOptions(_ newOptions: ReelExportOptions) {
        guard newOptions != options else { return }
        options = newOptions
        teardownPlayer()   // reset the `player == nil` guard so the new URL plays
        coordinator.generate(clips: clips, scopeKey: scopeKey, options: newOptions)
        // A cache hit resolves synchronously to `.ready`. If the URL equals the prior
        // one (e.g. the options netted back to visually-default), `onChange` won't fire,
        // so set the player up explicitly here. The `player == nil` guard inside
        // setupPlayer makes the async / different-URL paths (handled by onChange) no-ops.
        if case .ready(let url) = coordinator.state { setupPlayer(url) }
    }

    // MARK: - Helpers

    private var progressValue: Float {
        if case .generating(let p) = coordinator.state { return p }
        return 0
    }

    /// True once a reel is ready but some requested clips were cloud-only and skipped.
    private var isPartial: Bool {
        if case .ready = coordinator.state {
            return coordinator.usableCount > 0 && coordinator.usableCount < coordinator.requestedCount
        }
        return false
    }

    private func setupPlayer(_ url: URL) {
        guard player == nil else { return }
        AudioSessionManager.configureForPlayback()
        let p = AVPlayer(url: url)
        player = p
        p.play()
    }

    private func teardownPlayer() {
        player?.pause()
        player = nil
    }
}
