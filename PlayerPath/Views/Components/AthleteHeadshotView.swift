//
//  AthleteHeadshotView.swift
//  PlayerPath
//
//  Circular athlete avatar that renders the athlete's chosen headshot photo
//  (`Athlete.headshotPhotoId`, SchemaV33) when set, falling back to a
//  caller-supplied view (initials, gradient person icon, …) when there's no
//  headshot or it can't be decoded.
//
//  Resolves the pointer against `athlete.photos` and decodes through the shared
//  `PhotoThumbnailLoader` (same NSCache + disk→cloud fallback chain as the photo
//  grid), so the image rides the normal Photo sync/storage path — only the
//  pointer is new. Reloads automatically when the pointer changes.
//

import SwiftUI

struct AthleteHeadshotView<Fallback: View>: View {
    let athlete: Athlete
    let size: CGFloat
    @ViewBuilder var fallback: () -> Fallback

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                fallback()
            }
        }
        // Re-runs on appear, when the pointer changes (set / cleared / switched
        // athlete), AND when the pointed-to Photo row first links into
        // `athlete.photos`. On a fresh device the athlete (carrying the pointer)
        // syncs BEFORE its photos, so the first load finds no row and shows the
        // fallback; without the `resolved` half of this key the `.task` would never
        // re-fire when the row lands, stranding the avatar on the fallback until the
        // view is recreated. Reading `athlete.photos` here also registers SwiftData
        // observation so the refresh is automatic. (Once the row resolves, the loader
        // pulls the file from cloud if it isn't on disk yet.)
        .task(id: HeadshotLoadKey(id: athlete.headshotPhotoId, resolved: headshotPhotoResolved)) {
            await loadHeadshot()
        }
    }

    /// Whether the pointed-to headshot Photo is present in `athlete.photos` yet.
    /// Part of the `.task` id so the load re-runs the moment the row syncs in.
    private var headshotPhotoResolved: Bool {
        guard let id = athlete.headshotPhotoId else { return false }
        return (athlete.photos ?? []).contains { $0.id == id }
    }

    private func loadHeadshot() async {
        guard let id = athlete.headshotPhotoId,
              let photo = (athlete.photos ?? []).first(where: { $0.id == id }) else {
            image = nil
            return
        }
        // ~3× the point size keeps the avatar crisp on Retina without decoding
        // the full-resolution photo.
        image = await PhotoThumbnailLoader.load(for: photo, maxPixelSize: Int(size * 3))
    }
}

/// Identity for `AthleteHeadshotView`'s load task: the headshot pointer plus
/// whether its Photo row is locally resolvable yet, so the load re-fires both
/// when the user picks a different headshot and when a just-synced row lands.
private struct HeadshotLoadKey: Equatable {
    let id: UUID?
    let resolved: Bool
}
