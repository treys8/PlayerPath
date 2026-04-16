//
//  RemoteThumbnailView.swift
//  PlayerPath
//
//  Reusable thumbnail view for URL-based video thumbnails (coach/shared folder videos).
//  Uses ThumbnailCache for disk + memory caching, matching athlete thumbnail performance.
//

import SwiftUI
import os

struct RemoteThumbnailView: View {
    let urlString: String?
    var size: CGSize = CGSize(width: 120, height: 68)
    var cornerRadius: CGFloat = 12
    var duration: Double?
    var annotationCount: Int?
    var contextLabel: String?
    var isHighlight: Bool = false
    var hasNotes: Bool = false
    var fillsContainer: Bool = false

    // Secure URL parameters — when provided, uses signed URLs instead of the raw urlString
    var folderID: String?
    var videoFileName: String?

    @State private var thumbnailImage: UIImage?
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var loadAttempts = 0

    private static let log = Logger(subsystem: "com.playerpath.app", category: "RemoteThumbnailView")
    private let maxLoadAttempts = 2

    // MARK: - Convenience Factories

    static func small(
        urlString: String? = nil,
        folderID: String? = nil,
        videoFileName: String? = nil
    ) -> RemoteThumbnailView {
        RemoteThumbnailView(
            urlString: urlString,
            size: CGSize(width: 50, height: 28),
            cornerRadius: 8,
            folderID: folderID,
            videoFileName: videoFileName
        )
    }

    static func medium(
        urlString: String? = nil,
        folderID: String? = nil,
        videoFileName: String? = nil
    ) -> RemoteThumbnailView {
        RemoteThumbnailView(
            urlString: urlString,
            size: CGSize(width: 80, height: 45),
            cornerRadius: 12,
            folderID: folderID,
            videoFileName: videoFileName
        )
    }

    static func large(
        urlString: String? = nil,
        folderID: String? = nil,
        videoFileName: String? = nil
    ) -> RemoteThumbnailView {
        RemoteThumbnailView(
            urlString: urlString,
            size: CGSize(width: 120, height: 68),
            cornerRadius: 12,
            folderID: folderID,
            videoFileName: videoFileName
        )
    }

    // MARK: - Body

    var body: some View {
        let safeSize = CGSize(width: max(size.width, 1), height: max(size.height, 1))

        ZStack {
            // Thumbnail image with fade-in transition
            ZStack {
                if let thumbnail = thumbnailImage {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(
                            minWidth: fillsContainer ? 0 : safeSize.width,
                            maxWidth: fillsContainer ? .infinity : safeSize.width,
                            minHeight: fillsContainer ? 0 : safeSize.height,
                            maxHeight: fillsContainer ? .infinity : safeSize.height
                        )
                        .clipped()
                        .transition(.opacity)
                } else {
                    if fillsContainer {
                        placeholder(size: safeSize)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.opacity)
                    } else {
                        placeholder(size: safeSize)
                            .transition(.opacity)
                    }
                }
            }
            .animation(.easeIn(duration: 0.2), value: thumbnailImage == nil)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(playButtonOverlay)

            // Annotation count (top-right)
            if let count = annotationCount, count > 0 {
                VStack {
                    HStack {
                        Spacer()
                        annotationBadge(count: count)
                    }
                    Spacer()
                }
            }

            // Bottom-left: context label + duration
            VStack {
                Spacer()
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        if let context = contextLabel {
                            contextBadge(text: context)
                        }
                        if let d = duration, d > 0 {
                            contextBadge(text: d.formattedTimestamp)
                        }
                    }
                    Spacer()
                }
            }

            // Bottom-right: highlight star + note indicator
            VStack {
                Spacer()
                HStack(spacing: 4) {
                    Spacer()
                    if hasNotes {
                        noteIndicator
                    }
                    if isHighlight {
                        highlightIndicator
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        .task(id: cacheKey) {
            await loadThumbnail()
        }
    }

    // MARK: - Cache Key

    private var cacheKey: String? {
        if let folderID, let videoFileName {
            return "\(folderID)_\(videoFileName)"
        }
        return urlString
    }

    // MARK: - Loading

    @MainActor
    private func loadThumbnail() async {
        guard thumbnailImage == nil, !isLoading, !Task.isCancelled else { return }

        // Secure mode: load through ThumbnailCache with disk caching
        if let folderID, let videoFileName {
            isLoading = true
            loadFailed = false
            let key = "\(folderID)_\(videoFileName)"
            let targetSize = CGSize(width: size.width * 2, height: size.height * 2)

            do {
                let image = try await ThumbnailCache.shared.loadRemoteThumbnail(
                    cacheKey: key,
                    urlProvider: {
                        try await SecureURLManager.shared.getSecureThumbnailURL(
                            videoFileName: videoFileName,
                            folderID: folderID
                        )
                    },
                    targetSize: targetSize
                )
                guard !Task.isCancelled else { isLoading = false; return }
                thumbnailImage = image
            } catch {
                guard !Task.isCancelled else { isLoading = false; return }
                Self.log.error("Failed to load thumbnail: \(error.localizedDescription, privacy: .public)")
                loadAttempts += 1
                if loadAttempts < maxLoadAttempts {
                    try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(loadAttempts)) * 1_000_000_000))
                    isLoading = false
                    guard !Task.isCancelled else { return }
                    await loadThumbnail()
                    return
                }
                loadFailed = true
            }
            isLoading = false
            return
        }

        // Fallback: direct URL loading (non-secure, no folder context)
        guard let urlString, let url = URL(string: urlString) else {
            loadFailed = true
            return
        }
        isLoading = true
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled else { isLoading = false; return }
            if let image = UIImage(data: data) {
                thumbnailImage = image
            } else {
                loadFailed = true
            }
        } catch {
            guard !Task.isCancelled else { isLoading = false; return }
            loadFailed = true
        }
        isLoading = false
    }

    // MARK: - Placeholder

    private func placeholder(size: CGSize) -> some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [Color.gray.opacity(0.5), Color.gray.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .frame(width: size.width, height: size.height)
            .overlay(
                VStack(spacing: scaledSpacing(8)) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(scaledValue(1.0))
                    } else if loadFailed {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                            .font(.system(size: scaledValue(24)))
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "video.fill")
                            .foregroundColor(.white)
                            .font(.system(size: scaledValue(24)))
                            .accessibilityHidden(true)
                    }
                    Text(placeholderText)
                        .font(.system(size: scaledValue(10)))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                .padding(scaledSpacing(4))
            )
    }

    private var placeholderText: String {
        if isLoading { return "Loading..." }
        else if loadFailed { return "Failed to Load" }
        else { return contextLabel ?? "No Preview" }
    }

    // MARK: - Overlays

    @ViewBuilder
    private var playButtonOverlay: some View {
        let circleSize = min(scaledValue(44), 44)
        let iconSize = min(scaledValue(14), 15)
        Circle()
            .fill(.black.opacity(0.35))
            .background(.ultraThinMaterial, in: Circle())
            .frame(width: circleSize, height: circleSize)
            .overlay(
                Image(systemName: "play.fill")
                    .foregroundColor(.white)
                    .font(.system(size: iconSize))
                    .offset(x: 1)
                    .accessibilityHidden(true)
            )
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
    }

    private func annotationBadge(count: Int) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "bubble.left.fill")
                .font(.system(size: 8))
            Text("\(count)")
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundColor(.white)
        .badgeSmall()
        .background {
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(.black.opacity(0.3))
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
        .padding(.top, 8)
        .padding(.trailing, 8)
    }

    private func contextBadge(text: String) -> some View {
        Text(text)
            .font(.system(size: min(scaledValue(9), 11), weight: .semibold))
            .foregroundColor(.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, min(scaledSpacing(5), 7))
            .padding(.vertical, min(scaledSpacing(2), 3))
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 5).fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 5).fill(.black.opacity(0.4))
                }
            }
            .padding(.bottom, 8)
            .padding(.leading, 8)
    }

    private var highlightIndicator: some View {
        Image(systemName: "star.fill")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.yellow)
            .padding(6)
            .background(.ultraThinMaterial, in: Circle())
            .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
            .padding(.bottom, 8)
            .padding(.trailing, 8)
            .accessibilityHidden(true)
    }

    private var noteIndicator: some View {
        Image(systemName: "note.text")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.white.opacity(0.9))
            .padding(5)
            .background(.ultraThinMaterial, in: Circle())
            .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
            .padding(.bottom, 8)
            .padding(.trailing, isHighlight ? 0 : 8)
            .accessibilityLabel("Has note")
    }

    // MARK: - Scaling Helpers

    private func scaledValue(_ baseValue: CGFloat) -> CGFloat {
        let baseWidth: CGFloat = 80
        return baseValue * (size.width / baseWidth)
    }

    private func scaledSpacing(_ baseSpacing: CGFloat) -> CGFloat {
        scaledValue(baseSpacing)
    }
}
