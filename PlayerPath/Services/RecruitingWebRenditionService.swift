//
//  RecruitingWebRenditionService.swift
//  PlayerPath
//
//  Produces the web-safe copy of a highlight that the published recruiting page
//  actually serves.
//
//  WHY THIS EXISTS. Every clip in the app is HEVC-in-QuickTime by the time it
//  reaches Storage: VideoRecordingSettings records .hevc, VideoCompressionService
//  re-encodes to AVAssetExportPresetHEVC1920x1080 with outputFileType .mov, and
//  VideoCloudManager stamps contentType "video/quicktime". That is the right
//  master for coaching analysis and it plays fine in-app. It does NOT play for a
//  college coach on Firefox (quicktime isn't in Firefox's supported media types,
//  so it never attempts a decode) or on a Windows machine without Microsoft's
//  paid HEVC Video Extensions (the element just fires `error`). The published
//  page has CSP `default-src 'none'`, so there is no JS to detect or explain it.
//
//  The failure is silent on BOTH ends — the athlete previews it working on their
//  iPhone, and a coach who got a black box doesn't write back to say so. So the
//  page gets its own H.264/AAC .mp4 rendition rather than the master.
//
//  The master is never touched. Renditions live beside the clip at
//  `athlete_videos/{uid}/recruiting/{base}.mp4`, which storage.rules already
//  covers (`athlete_videos/{userID}/{allPaths=**}`, video/* content type) and
//  which serveRecruitingProfile's ownedPath() already allows (it prefix-matches
//  `athlete_videos/{ownerUID}/`). No security change was needed for either.
//

import AVFoundation
import FirebaseStorage
import Foundation
import os

private let renditionLog = Logger(subsystem: "com.playerpath.app", category: "RecruitingRendition")

/// Everything the rendition step needs from a `VideoClip`, snapshotted off the
/// model before the first await. `@Model` reads after a suspension point can trap
/// if a concurrent delete invalidated the object.
struct RecruitingClipSource {
    let id: UUID
    let fileName: String
    let localPath: String
    let cloudURL: String?
}

@MainActor
final class RecruitingWebRenditionService {

    static let shared = RecruitingWebRenditionService()
    private init() {}

    /// 720p, not the master's 1080p. A recruiter watches in a browser window on a
    /// laptop, the page loads eight of these, and every view is signed-URL egress
    /// we pay for — 720p H.264 is ample for evaluation and roughly halves both.
    private static let preferredPreset = AVAssetExportPreset1280x720
    private static let fallbackPreset = AVAssetExportPreset960x540

    /// Storage path of the web rendition for `fileName`, or nil if the name has no
    /// usable base. Deterministic, so a republish reuses whatever already exists.
    static func renditionPath(ownerUID: String, fileName: String) -> String? {
        let base = (fileName as NSString).deletingPathExtension
        guard !base.isEmpty, !ownerUID.isEmpty else { return nil }
        return "athlete_videos/\(ownerUID)/recruiting/\(base).mp4"
    }

    /// Makes sure every source has a web-safe rendition in Storage, and returns the
    /// path to use for each clip.
    ///
    /// Runs sequentially on purpose: each step holds a hardware encode plus a file
    /// download and upload, and eight of those in flight is a memory-pressure
    /// termination on an older device for no wall-clock win that matters here.
    ///
    /// A clip whose rendition can't be produced maps to nil, and the caller falls
    /// back to the master path — a clip that plays for most viewers beats a clip
    /// silently dropped from the page.
    func ensureRenditions(
        for sources: [RecruitingClipSource],
        ownerUID: String,
        progress: @MainActor (Int, Int) -> Void
    ) async -> [UUID: String] {
        var result: [UUID: String] = [:]
        for (index, source) in sources.enumerated() {
            progress(index, sources.count)
            if let path = await ensureRendition(for: source, ownerUID: ownerUID) {
                result[source.id] = path
            }
        }
        progress(sources.count, sources.count)
        return result
    }

    private func ensureRendition(for source: RecruitingClipSource, ownerUID: String) async -> String? {
        guard let path = Self.renditionPath(ownerUID: ownerUID, fileName: source.fileName) else {
            return nil
        }
        let ref = Storage.storage().reference(withPath: path)

        // A clip's fileName is unique and its bytes never change in place, so an
        // existing rendition is always current — republishing skips the encode.
        if (try? await ref.getMetadata()) != nil {
            return path
        }

        guard let localURL = await localSource(for: source, ownerUID: ownerUID) else {
            renditionLog.warning("No local copy available for \(source.fileName, privacy: .public) — page will serve the master")
            return nil
        }
        defer {
            // Only clean up what WE fetched. Deleting the athlete's own local clip
            // would silently undo their library.
            if localURL.path.hasPrefix(FileManager.default.temporaryDirectory.path) {
                try? FileManager.default.removeItem(at: localURL)
            }
        }

        guard let exportedURL = await exportWebSafe(from: localURL) else {
            renditionLog.error("Web rendition export failed for \(source.fileName, privacy: .public)")
            return nil
        }
        defer { try? FileManager.default.removeItem(at: exportedURL) }

        let metadata = StorageMetadata()
        metadata.contentType = "video/mp4"
        do {
            _ = try await ref.putFileAsync(from: exportedURL, metadata: metadata)
            renditionLog.info("Uploaded web rendition for \(source.fileName, privacy: .public)")
            return path
        } catch {
            renditionLog.error("Web rendition upload failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Source file

    /// The local file to transcode. Clips are not guaranteed to be on this device:
    /// the "Auto-delete After Upload" preference removes them once uploaded, and a
    /// clip synced from another device downloads lazily. When it's missing we fetch
    /// to a TEMP file rather than rehydrating Documents/Clips — re-materialising a
    /// file the athlete asked us to delete would quietly undo that setting.
    private func localSource(for source: RecruitingClipSource, ownerUID: String) async -> URL? {
        if !source.localPath.isEmpty, FileManager.default.fileExists(atPath: source.localPath) {
            return URL(fileURLWithPath: source.localPath)
        }
        guard source.cloudURL != nil, !source.fileName.isEmpty else { return nil }

        // Mint a fresh signed URL the way playback does — the stored cloudURL
        // carries an access token that may already have been rotated.
        let downloadURL: String
        do {
            downloadURL = try await SecureURLManager.shared.getPersonalVideoURL(
                ownerUID: ownerUID,
                fileName: source.fileName
            )
        } catch {
            renditionLog.warning("Could not sign \(source.fileName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("recruiting_src_\(UUID().uuidString)")
            .appendingPathExtension((source.fileName as NSString).pathExtension.isEmpty
                                    ? "mov"
                                    : (source.fileName as NSString).pathExtension)
        do {
            try await VideoCloudManager.shared.downloadVideo(from: downloadURL,
                                                             to: temp.path,
                                                             clipId: source.id)
            return temp
        } catch {
            renditionLog.warning("Download failed for \(source.fileName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: temp)
            return nil
        }
    }

    // MARK: - Export

    /// H.264 + AAC in an .mp4 container with the moov atom up front. Every one of
    /// those three matters: the container is what Firefox will accept, the video
    /// codec is what a decoder-less Windows machine can play, and faststart is what
    /// lets the browser begin playback before the whole file arrives.
    private func exportWebSafe(from sourceURL: URL) async -> URL? {
        let asset = AVURLAsset(url: sourceURL)

        let preset: String
        if await AVAssetExportSession.compatibility(ofExportPreset: Self.preferredPreset,
                                                    with: asset, outputFileType: .mp4) {
            preset = Self.preferredPreset
        } else if await AVAssetExportSession.compatibility(ofExportPreset: Self.fallbackPreset,
                                                           with: asset, outputFileType: .mp4) {
            preset = Self.fallbackPreset
        } else {
            renditionLog.warning("No H.264/mp4 preset is compatible with this asset")
            return nil
        }

        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { return nil }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("recruiting_web_\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        let box = AVExportSessionBox(session)
        await withTaskCancellationHandler {
            await session.export()
        } onCancel: {
            box.cancel()
        }

        guard session.status == .completed else {
            renditionLog.error("Export failed: \(session.error?.localizedDescription ?? "unknown", privacy: .public)")
            try? FileManager.default.removeItem(at: outputURL)
            return nil
        }
        return outputURL
    }
}
