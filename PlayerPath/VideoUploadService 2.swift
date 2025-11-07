import Foundation
import os.log
import SwiftData

/// A minimal skeleton for handling video uploads with retry integration.
/// Replace the `performUpload` body with your actual upload mechanism (CloudKit assets, backend, etc.).
@MainActor
final class VideoUploadService {
    static let shared = VideoUploadService()
    private let logger = Logger(subsystem: "PlayerPath", category: "VideoUploadService")

    private init() {}

    enum UploadError: Error {
        case notEligible
        case network
        case processing
        case unauthorized
        case unknown(String)
    }

    /// Enqueue or immediately perform an upload for a clip.
    /// - Parameters:
    ///   - clip: The clip to upload.
    ///   - userPreferences: Preferences to decide eligibility (e.g., autoUploadToCloud, syncHighlightsOnly).
    ///   - modelContext: The model context for data operations.
    ///   - context: Context string used for ErrorHandlerService retry keys (e.g., "VideoUpload").
    func upload(clip: VideoClip, userPreferences: UserPreferences, modelContext: ModelContext, context: String = "VideoUpload") {
        // Eligibility checks based on preferences
        guard userPreferences.autoUploadToCloud else {
            logger.notice("Auto-upload disabled; skipping upload for clip: \(clip.id)")
            return
        }
        if userPreferences.syncHighlightsOnly && !clip.isHighlight {
            logger.notice("Sync highlights only; skipping non-highlight clip: \(clip.id)")
            return
        }

        let retryKey = "\(context)_\(PlayerPathError.videoUploadFailed(reason: "").id)"

        // Register a retry callback for this clip (idempotent: overwrites existing for same key)
        ErrorHandlerService.shared.registerRetryCallback(for: retryKey) { [weak self] in
            guard let self else { return false }
            do {
                try await self.performUpload(clip: clip, modelContext: modelContext)
                return true
            } catch {
                return false
            }
        }

        Task {
            do {
                try await performUpload(clip: clip, modelContext: modelContext)
                // On success, cleanup retry callback and attempts
                ErrorHandlerService.shared.unregisterRetryCallback(for: retryKey)
                ErrorHandlerService.shared.resetRetryAttempts(for: context)
            } catch {
                // Map the error to PlayerPathError for consistent UX
                let mapped: PlayerPathError
                switch error {
                case UploadError.unauthorized:
                    mapped = .authenticationRequired
                case UploadError.network:
                    mapped = .networkError(underlying: error)
                case UploadError.processing:
                    mapped = .videoProcessingFailed(reason: "Upload preparation failed")
                case UploadError.notEligible:
                    mapped = .unknownError("Clip not eligible for upload")
                case UploadError.unknown(let message):
                    mapped = .unknownError(message)
                default:
                    mapped = .unknownError(error.localizedDescription)
                }

                // Use ErrorHandlerService with autoRetry. The registered callback above will be used.
                ErrorHandlerService.shared.handle(
                    mapped,
                    context: context,
                    severity: mapped.severity,
                    canRetry: mapped.isRetryable,
                    autoRetry: mapped.isRetryable,
                    userInfo: [
                        "clipId": clip.id.uuidString,
                        "fileName": clip.fileName
                    ]
                )
            }
        }
    }

    /// Replace this with real upload logic. Throw network/processing errors to trigger retries.
    private func performUpload(clip: VideoClip, modelContext: ModelContext) async throws {
        // Example simulated upload logic:
        // - Validate file exists
        // - Optionally compress/transcode
        // - Upload to server/CloudKit
        // - Update clip state upon success

        // Simulate file presence check
        guard clip.localFileURL != nil else {
            throw UploadError.processing
        }

        // Simulate transient network failure randomly for demonstration
        if Bool.random() {
            throw UploadError.network
        }

        // Simulate success: mark as uploaded
        clip.isUploaded = true
        do { try modelContext.save() } catch {
            logger.error("Failed to save clip upload state: \(error.localizedDescription)")
        }

        logger.info("Upload succeeded for clip: \(clip.id)")
    }
}
