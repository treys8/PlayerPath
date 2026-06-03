//
//  VideoClip+Sharing.swift
//  PlayerPath
//
//  Share-friendly filenames. On disk a clip is named by a UUID
//  (`<uuid>.mov`), so a raw ShareLink/AirDrop/Save-to-Files would land as
//  that opaque string. These helpers expose the clip under a readable name
//  like "Double - Apr 22, 2026.mov" by hard-linking the real file (no data
//  copy) into a temp directory under the friendly name.
//

import Foundation

extension VideoClip {
    /// Human-readable base filename — tag + capture date, sanitized for the
    /// filesystem. Falls back to a generic name for untagged clips.
    var shareDisplayName: String {
        var parts: [String] = []
        if let displayTagName { parts.append(displayTagName) }
        if let createdAt {
            parts.append(createdAt.formatted(.dateTime.month(.abbreviated).day().year()))
        }
        let base = parts.isEmpty ? "PlayerPath Clip" : parts.joined(separator: " - ")
        // Drop characters that are illegal or awkward in a filename.
        let illegal = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return base.components(separatedBy: illegal).joined(separator: "-")
    }

    /// A URL pointing at this clip's video under `shareDisplayName`, suitable
    /// for `ShareLink`. Hard-links the real file (instant, no data duplication)
    /// into a per-clip temp folder so collisions between two same-titled clips
    /// can't cross-serve. Returns nil when the local file is missing (e.g. a
    /// cloud clip that hasn't downloaded yet) — callers then hide Share.
    ///
    /// Cheap enough to call once per player open; do NOT call it inside a view
    /// body (it touches the filesystem).
    func makeShareURL() -> URL? {
        let source = resolvedFileURL
        guard FileManager.default.fileExists(atPath: source.path) else { return nil }

        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension
        // Per-clip subdir keeps the visible filename friendly while guaranteeing
        // uniqueness. Cleared each call so a re-trim or rename never serves
        // stale content under the old link.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Shared", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let dest = dir.appendingPathComponent(shareDisplayName).appendingPathExtension(ext)
        do {
            try FileManager.default.linkItem(at: source, to: dest)
        } catch {
            // Hard links can't cross volumes — fall back to a copy, then to the
            // original (UUID-named, but still shareable) if even that fails.
            guard (try? FileManager.default.copyItem(at: source, to: dest)) != nil else {
                return source
            }
        }
        return dest
    }
}
