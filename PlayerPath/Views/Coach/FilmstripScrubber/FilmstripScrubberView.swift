//
//  FilmstripScrubberView.swift
//  PlayerPath
//
//  Horizontal scrollable strip of video frame thumbnails.
//  Tap a frame to seek; the current playback position is highlighted.
//

import SwiftUI

struct FilmstripScrubberView: View {
    let thumbnails: [FilmstripThumbnail]
    let currentTime: Double
    let duration: Double
    let onSeek: (Double) -> Void
    let isLoading: Bool
    let isPlaying: Bool
    /// Optional drawing-annotation markers rendered as tickmarks above the
    /// filmstrip. Each is positioned at `(timestamp / duration) * contentWidth`.
    var markers: [VideoAnnotation] = []
    /// Invoked when a marker is tapped. Caller is expected to seek + open the
    /// drawing overlay (see `CoachVideoPlayerViewModel.showDrawingOverlay`).
    var onTapMarker: ((VideoAnnotation) -> Void)? = nil

    private let thumbWidth: CGFloat = 80
    private let thumbHeight: CGFloat = 45
    private let markerRowHeight: CGFloat = 14

    /// Index of the thumbnail closest to the current playback time.
    private var activeIndex: Int? {
        guard !thumbnails.isEmpty, duration > 0 else { return nil }
        return thumbnails.enumerated().min(by: {
            abs($0.element.timestamp - currentTime) < abs($1.element.timestamp - currentTime)
        })?.offset
    }

    /// Total horizontal extent of the thumbnail strip (matches the LazyHStack's
    /// content size including the 8pt edge padding). Used to position markers
    /// that should align with thumbnail timestamps.
    private var contentWidth: CGFloat {
        let count = CGFloat(thumbnails.count)
        guard count > 0 else { return 0 }
        return count * thumbWidth + max(0, count - 1) * 4 + 16
    }

    private var hasMarkers: Bool {
        !markers.isEmpty && duration > 0
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    if hasMarkers {
                        markerRow
                    }
                    LazyHStack(spacing: 4) {
                        ForEach(thumbnails) { thumb in
                            thumbnailCell(thumb)
                                .id(thumb.id)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            .onChange(of: activeIndex) { _, newIndex in
                guard !isPlaying, let newIndex else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
        .frame(height: thumbHeight + 20 + (hasMarkers ? markerRowHeight + 2 : 0))
        .background(Color(.secondarySystemBackground))
        .overlay(alignment: .center) {
            if isLoading && thumbnails.allSatisfy({ $0.image == nil }) {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    /// Tickmark strip aligned to the filmstrip's content width. Each marker is
    /// a tappable hit-region (24pt wide) wrapping a 3pt navy bar.
    private var markerRow: some View {
        ZStack(alignment: .leading) {
            Color.clear
                .frame(width: contentWidth, height: markerRowHeight)
            ForEach(markers) { annotation in
                let x = (CGFloat(annotation.timestamp) / CGFloat(duration)) * contentWidth
                Button {
                    Haptics.light()
                    onTapMarker?(annotation)
                } label: {
                    ZStack {
                        Color.clear.frame(width: 24, height: markerRowHeight)
                        Rectangle()
                            .fill(Color.brandNavy)
                            .frame(width: 3, height: 12)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(x: x - 12)
                .accessibilityLabel("Drawing at \(formatTimestamp(annotation.timestamp))")
            }
        }
    }

    @ViewBuilder
    private func thumbnailCell(_ thumb: FilmstripThumbnail) -> some View {
        let isActive = activeIndex == thumb.id

        Button {
            Haptics.light()
            onSeek(thumb.timestamp)
        } label: {
            VStack(spacing: 2) {
                Group {
                    if let image = thumb.image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Color(.systemGray4)
                    }
                }
                .frame(width: thumbWidth, height: thumbHeight)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isActive ? Color.brandNavy : .clear, lineWidth: 2)
                )

                Text(formatTimestamp(thumb.timestamp))
                    .font(.system(size: 9, weight: isActive ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundColor(isActive ? .brandNavy : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Frame at \(formatTimestamp(thumb.timestamp))")
    }

    private func formatTimestamp(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let frac = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        if mins > 0 {
            return String(format: "%d:%02d.%d", mins, secs, frac)
        }
        return String(format: "%d.%d", secs, frac)
    }
}
