//
//  AnnotationBadgeCluster.swift
//  PlayerPath
//
//  Shared pencil + comment badge pair for video thumbnails. Used by
//  RemoteThumbnailView (coach folder), AthleteVideoRow (shared folder list),
//  and VideoClipCard (athlete's own Videos grid) so all three stay in sync.
//
//  Display modes:
//    • legacy — drawingCount is nil and annotationCount > 0 → show lumped bubble
//    • split  — drawingCount is known → pencil for drawings, bubble for remaining
//    • none   — both counts zero → render nothing
//

import SwiftUI

/// Visual weight variants. Thumbnails use `.thumbnail`; compact rows use `.compact`.
enum AnnotationBadgeStyle {
    case thumbnail  // Capsule over ultraThinMaterial, used on top-right of video tiles
    case compact    // Plain text + icon pair, used inline inside list rows
}

struct AnnotationBadgeCluster: View {
    let annotationCount: Int
    /// Nil means "legacy, no split available" — renders the lumped bubble so
    /// counts don't silently disappear on videos written before drawingCount existed.
    let drawingCount: Int?
    var style: AnnotationBadgeStyle = .thumbnail

    var body: some View {
        let ac = annotationCount
        let dc = drawingCount
        let isLegacy = dc == nil && ac > 0
        let drawings = dc ?? 0
        let comments = max(0, ac - drawings)
        let showDrawings = dc != nil && drawings > 0
        let showComments = dc != nil && comments > 0

        if isLegacy || showDrawings || showComments {
            HStack(spacing: style == .thumbnail ? 4 : 8) {
                if isLegacy {
                    badge(icon: "bubble.left.fill", count: ac, kind: .comment)
                } else {
                    if showDrawings {
                        badge(icon: "pencil.tip", count: drawings, kind: .drawing)
                    }
                    if showComments {
                        badge(icon: "bubble.left.fill", count: comments, kind: .comment)
                    }
                }
            }
        }
    }

    private enum BadgeKind { case drawing, comment }

    @ViewBuilder
    private func badge(icon: String, count: Int, kind: BadgeKind) -> some View {
        switch style {
        case .thumbnail:
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: kind == .drawing ? 9 : 8, weight: .bold))
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(.white)
            .badgeSmall()
            .background {
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(backgroundTint(for: kind))
                }
            }
            .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)

        case .compact:
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.caption2)
                Text("\(count)")
                    .font(.caption2)
            }
            .foregroundColor(.secondary)
        }
    }

    private func backgroundTint(for kind: BadgeKind) -> Color {
        switch kind {
        case .drawing: return Color.brandNavy.opacity(0.65)
        case .comment: return Color.black.opacity(0.3)
        }
    }
}
