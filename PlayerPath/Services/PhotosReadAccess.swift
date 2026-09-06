//
//  PhotosReadAccess.swift
//  PlayerPath
//
//  Requests Photos READ authorization at the bulk-import entry point, which is
//  what makes `PhotosPickerItem.itemIdentifier` non-nil and therefore what makes
//  import de-duplication cheap and exact.
//
//  Without it, the only available fingerprint is a hash of the item's bytes —
//  which for video means exporting (and, for HEVC, transcoding) the whole asset
//  before we can tell it is a duplicate we are about to throw away. At a 100-item
//  cap, a second backfill sitting over an overlapping selection would spend
//  minutes producing nothing.
//

import Foundation
import Photos
import os

private let photosAuthLog = Logger(subsystem: "com.playerpath.app", category: "PhotosAuth")

enum PhotosReadAccess {

    /// Ask for read access once, if the user has never been asked.
    ///
    /// Deliberately fire-and-forget on the caller's side: the Photos **picker**
    /// is out-of-process and works at any authorization level, so nothing here
    /// gates the import. Access only upgrades the dedupe key from a content
    /// fingerprint to the library's own identifier, and the fingerprint path
    /// stays in place for every row written before this was granted.
    ///
    /// TRADE-OFF worth knowing: iOS presents Photos permission as ONE setting
    /// (None / Limited / All / Add Photos Only), so a user who declines full
    /// access here may end up with less permission than the `.addOnly` prompts
    /// elsewhere in the app would have obtained on their own (saving a clip to
    /// the camera roll — `ClipPersistenceService`, `ReelExportControls`,
    /// `VideoClipCard`, `PhotoDetailView`, `CoachVideoPlayerViewModel`). That is
    /// why this asks ONLY at the bulk-import entry point, where the user has
    /// just chosen to bring in library media and the request reads as expected,
    /// and never on launch or from a save flow.
    ///
    /// - Returns: true when the app ends up with read access (`.authorized` or
    ///   `.limited`). Callers may use it for logging; none should block on it.
    @discardableResult
    static func requestIfNeeded() async -> Bool {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard current == .notDetermined else { return isReadable(current) }

        // `.readWrite` is the only level that grants reads — PHAccessLevel has no
        // read-only option — and it satisfies the app's existing `.addOnly` checks.
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        photosAuthLog.info("Photos read authorization resolved: \(status.rawValue, privacy: .public)")
        return isReadable(status)
    }

    /// Whether the app currently holds read access, without prompting.
    static var hasReadAccess: Bool {
        isReadable(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    private static func isReadable(_ status: PHAuthorizationStatus) -> Bool {
        // `.limited` still populates `itemIdentifier` for what the user picked,
        // which is all the dedupe needs — it never resolves the id to a PHAsset.
        status == .authorized || status == .limited
    }
}
