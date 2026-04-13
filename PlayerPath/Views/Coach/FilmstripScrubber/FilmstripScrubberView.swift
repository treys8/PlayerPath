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

    private let thumbWidth: CGFloat = 80
    private let thumbHeight: CGFloat = 45

    /// Index of the thumbnail closest to the current playback time.
    private var activeIndex: Int? {
        guard !thumbnails.isEmpty, duration > 0 else { return nil }
        return thumbnails.enumerated().min(by: {
            abs($0.element.timestamp - currentTime) < abs($1.element.timestamp - currentTime)
        })?.offset
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 4) {
                    ForEach(thumbnails) { thumb in
                        thumbnailCell(thumb)
                            .id(thumb.id)
                    }
                }
                .padding(.horizontal, 8)
            }
            .onChange(of: activeIndex) { _, newIndex in
                guard let newIndex else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
        .frame(height: thumbHeight + 20)
        .background(Color(.secondarySystemBackground))
        .overlay(alignment: .center) {
            if isLoading && thumbnails.allSatisfy({ $0.image == nil }) {
                ProgressView()
                    .controlSize(.small)
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
