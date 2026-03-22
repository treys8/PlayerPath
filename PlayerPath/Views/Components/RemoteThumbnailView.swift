//
//  RemoteThumbnailView.swift
//  PlayerPath
//
//  Reusable thumbnail view for URL-based video thumbnails (coach/shared folder videos).
//  Matches VideoThumbnailView visual quality with proper loading states and overlays.
//

import SwiftUI

struct RemoteThumbnailView: View {
    let urlString: String?
    var size: CGSize = CGSize(width: 120, height: 68)
    var cornerRadius: CGFloat = 10
    var duration: Double?
    var annotationCount: Int?
    var contextLabel: String?
    var isHighlight: Bool = false
    var hasNotes: Bool = false

    var body: some View {
        ZStack {
            // Image layer
            thumbnailImage

            // Play button (center)
            playButton

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
                            metadataPill(text: context)
                        }
                        if let d = duration, d > 0 {
                            metadataPill(text: d.formattedTimestamp)
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
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }

    // MARK: - Thumbnail Image

    private var thumbnailImage: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .transition(.opacity)
                    case .failure:
                        placeholder(icon: "exclamationmark.triangle.fill", iconColor: .yellow, text: "Failed to Load")
                    case .empty:
                        placeholder(icon: nil, iconColor: .white, text: nil, showSpinner: true)
                    @unknown default:
                        placeholder(icon: "video.fill", iconColor: .white, text: nil)
                    }
                }
            } else {
                placeholder(icon: "video.fill", iconColor: .white, text: "No Preview")
            }
        }
        .frame(width: size.width, height: size.height)
        .background(Color.black)
        .clipped()
        .animation(.easeIn(duration: 0.2), value: urlString)
    }

    // MARK: - Placeholder

    private func placeholder(icon: String?, iconColor: Color, text: String?, showSpinner: Bool = false) -> some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [Color.gray.opacity(0.5), Color.gray.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .overlay(
                VStack(spacing: 6) {
                    if showSpinner {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else if let icon {
                        Image(systemName: icon)
                            .foregroundColor(iconColor)
                            .font(.system(size: 20))
                    }
                    if let text {
                        Text(text)
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            )
    }

    // MARK: - Overlays

    private var playButton: some View {
        Circle()
            .fill(.black.opacity(0.35))
            .background(.ultraThinMaterial, in: Circle())
            .frame(width: 36, height: 36)
            .overlay(
                Image(systemName: "play.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 12))
                    .offset(x: 1)
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
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 5).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 5).fill(.black.opacity(0.3))
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
        .padding(.top, 6)
        .padding(.trailing, 6)
    }

    private func metadataPill(text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 4).fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.4))
                }
            }
            .padding(.leading, 6)
            .padding(.bottom, 2)
    }

    private var highlightIndicator: some View {
        Image(systemName: "star.fill")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.yellow)
            .padding(5)
            .background(.ultraThinMaterial, in: Circle())
            .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
            .padding(.bottom, 6)
            .padding(.trailing, 6)
    }

    private var noteIndicator: some View {
        Image(systemName: "note.text")
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(.white.opacity(0.9))
            .padding(4)
            .background(.ultraThinMaterial, in: Circle())
            .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
            .padding(.bottom, 6)
            .padding(.trailing, isHighlight ? 0 : 6)
    }
}
