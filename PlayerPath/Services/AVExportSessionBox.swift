//
//  AVExportSessionBox.swift
//  PlayerPath
//
//  Shared wrapper around AVAssetExportSession for use inside Task cancellation
//  handlers. Previously duplicated in VideoCompressionService,
//  VideoStitchingService, and VideoTrimExporter.
//

import AVFoundation

// AVAssetExportSession isn't Sendable, but `cancelExport()` is documented as
// thread-safe. Wrap it so the Task cancellation handler closure compiles
// cleanly under strict concurrency.
final class AVExportSessionBox: @unchecked Sendable {
    nonisolated(unsafe) let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
    nonisolated func cancel() { session.cancelExport() }
}
