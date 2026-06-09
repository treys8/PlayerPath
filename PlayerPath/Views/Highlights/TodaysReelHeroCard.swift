//
//  TodaysReelHeroCard.swift
//  PlayerPath
//
//  Hero card at the top of HighlightsView that stitches today's highlight
//  clips into a single MP4 on demand. Plus+ feature.
//

import SwiftUI
import AVKit
import AVFoundation
import os

nonisolated private let reelLog = Logger(subsystem: "com.playerpath.app", category: "TodaysReel")

struct TodaysReelHeroCard: View {
    let athleteId: UUID
    let clips: [VideoClip]
    let onPlay: (URL) -> Void

    @State private var state: ReelState = .idle
    @State private var stitchTask: Task<Void, Never>?
    @State private var thumbnail: UIImage?

    enum ReelState: Equatable {
        case idle
        case generating(progress: Float)
        case ready(URL)
        case failed(String)
    }

    var body: some View {
        cardContent
            .frame(maxWidth: .infinity)
            .frame(height: 110)
            .background(cardBackground)
            .shadow(color: Color.brandGold.opacity(0.15), radius: 8, x: 0, y: 4)
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            .onAppear {
                if case .ready = state { return }
                if let cached = StitchedReelCache.cachedURLIfPresent(scopeKey: todayScopeKey, clips: clips) {
                    state = .ready(cached)
                    loadThumbnail(for: cached)
                }
            }
            .onDisappear {
                stitchTask?.cancel()
                stitchTask = nil
            }
            .onChange(of: clips.map(\.id)) { _, _ in
                // Today's set changed (new highlight added or rolled past midnight).
                // Drop any in-flight stitch so the next Generate uses the new clips.
                stitchTask?.cancel()
                stitchTask = nil
                if case .ready = state { state = .idle }
                thumbnail = nil
            }
    }

    @ViewBuilder
    private var cardContent: some View {
        switch state {
        case .idle:
            idleContent
        case .generating(let progress):
            generatingContent(progress: progress)
        case .ready(let url):
            readyContent(url: url)
        case .failed(let message):
            failedContent(message: message)
        }
    }

    // MARK: - States

    private var idleContent: some View {
        HStack(spacing: 14) {
            Image(systemName: "film.stack")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.brandGold)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("Today's Reel")
                    .font(.headingMedium)
                    .foregroundColor(.primary)
                Text("\(clips.count) highlights from today")
                    .font(.labelSmall)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                Haptics.light()
                generate()
            } label: {
                Text("Generate")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(Color.brandGold)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    private func generatingContent(progress: Float) -> some View {
        HStack(spacing: 14) {
            ProgressView(value: progress)
                .progressViewStyle(.circular)
                .tint(.brandGold)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("Stitching today's reel…")
                    .font(.headingMedium)
                    .foregroundColor(.primary)
                Text("\(Int(progress * 100))%")
                    .font(.labelSmall)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            Button {
                stitchTask?.cancel()
                stitchTask = nil
                state = .idle
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    private func readyContent(url: URL) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.4))
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .shadow(radius: 2)
            }
            .frame(width: 70, height: 70)
            .clipped()
            VStack(alignment: .leading, spacing: 4) {
                Text("Today's Reel")
                    .font(.headingMedium)
                    .foregroundColor(.primary)
                Text("\(clips.count) highlights · Ready to play")
                    .font(.labelSmall)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                Haptics.light()
                onPlay(url)
            } label: {
                Text("Play")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.brandGold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    private func failedContent(message: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(Theme.warning)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("Couldn't build reel")
                    .font(.headingMedium)
                    .foregroundColor(.primary)
                Text(message)
                    .font(.labelSmall)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            Button {
                Haptics.light()
                generate()
            } label: {
                Text("Retry")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.brandGold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Background

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: .cornerXLarge, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
            VStack {
                RoundedRectangle(cornerRadius: .cornerXLarge, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.brandGold.opacity(0.12), .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .frame(height: 60)
                Spacer()
            }
            .clipShape(RoundedRectangle(cornerRadius: .cornerXLarge, style: .continuous))
            VStack {
                HStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.brandGold)
                        .frame(width: 40, height: 3)
                    Spacer()
                }
                .padding(.leading, 16)
                .padding(.top, 10)
                Spacer()
            }
        }
    }

    // MARK: - Actions

    private var todayScopeKey: String { "today_\(athleteId.uuidString)" }

    private func generate() {
        let cacheURL = StitchedReelCache.url(scopeKey: todayScopeKey, clips: clips)
        if let existing = StitchedReelCache.cachedURLIfPresent(scopeKey: todayScopeKey, clips: clips) {
            state = .ready(existing)
            loadThumbnail(for: existing)
            return
        }

        state = .generating(progress: 0)
        let capturedURLs = clips.map { $0.resolvedFileURL }
        stitchTask = Task { @MainActor in
            do {
                let url = try await VideoStitchingService.stitch(
                    sourceURLs: capturedURLs,
                    outputURL: cacheURL
                ) { p in
                    if case .generating = state {
                        state = .generating(progress: p)
                    }
                }
                guard !Task.isCancelled else { return }
                state = .ready(url)
                loadThumbnail(for: url)
                Haptics.success()
            } catch is CancellationError {
                if case .generating = state { state = .idle }
            } catch let error as VideoStitchingService.StitchError {
                reelLog.error("Stitch failed: \(error.localizedDescription)")
                state = .failed(error.localizedDescription)
            } catch {
                reelLog.error("Stitch failed: \(error.localizedDescription)")
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func loadThumbnail(for url: URL) {
        Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 280, height: 280)
            do {
                let cgImage: CGImage
                if #available(iOS 16.0, *) {
                    cgImage = try await generator.image(at: CMTime(seconds: 0.1, preferredTimescale: 600)).image
                } else {
                    cgImage = try generator.copyCGImage(at: CMTime(seconds: 0.1, preferredTimescale: 600), actualTime: nil)
                }
                let image = UIImage(cgImage: cgImage)
                await MainActor.run { thumbnail = image }
            } catch {
                reelLog.warning("Thumbnail generation failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Stitched Reel Player

struct StitchedReelPlayerView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
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
                ReelExportControls(url: url)
            }
            .padding()
        }
        .onAppear {
            AudioSessionManager.configureForPlayback()
            let p = AVPlayer(url: url)
            player = p
            p.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
