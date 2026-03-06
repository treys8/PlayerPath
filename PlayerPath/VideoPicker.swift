//
//  VideoPicker.swift
//  PlayerPath
//
//  Created by Assistant on 12/2/25.
//

import SwiftUI
import PhotosUI
import SwiftData

struct VideoPicker: UIViewControllerRepresentable {
    let athlete: Athlete
    let onError: (String) -> Void
    let onImportStart: () -> Void
    let onImportComplete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .videos
        configuration.selectionLimit = 1
        // .compatible transcodes to a universally-readable H.264/QuickTime format,
        // avoiding failures with HEVC, ProRes, Dolby Vision, and slow-motion formats.
        configuration.preferredAssetRepresentationMode = .compatible

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: VideoPicker

        init(_ parent: VideoPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()

            guard let result = results.first else { return }

            // Check if it can provide a movie
            guard result.itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else {
                parent.onError("Selected item is not a video")
                return
            }

            parent.onImportStart()

            // Load the video file. The URL provided in the callback is a temporary
            // file that is deleted once the closure returns, so we copy it to a
            // stable location synchronously before escaping into an async Task.
            result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                if let error = error {
                    DispatchQueue.main.async {
                        self.parent.onImportComplete()
                        self.parent.onError("Failed to load video: \(error.localizedDescription)")
                    }
                    return
                }

                guard let tempURL = url else {
                    DispatchQueue.main.async {
                        self.parent.onImportComplete()
                        self.parent.onError("Failed to access video file")
                    }
                    return
                }

                // Copy synchronously while the temp URL is still alive.
                guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                    DispatchQueue.main.async {
                        self.parent.onImportComplete()
                        self.parent.onError("Could not access documents directory")
                    }
                    return
                }
                let ext = tempURL.pathExtension.isEmpty ? "mov" : tempURL.pathExtension
                let stableURL = documentsDir.appendingPathComponent("imported_\(UUID().uuidString).\(ext)")
                do {
                    try FileManager.default.copyItem(at: tempURL, to: stableURL)
                } catch {
                    DispatchQueue.main.async {
                        self.parent.onImportComplete()
                        self.parent.onError("Failed to copy video: \(error.localizedDescription)")
                    }
                    return
                }

                Task {
                    await self.importVideo(from: stableURL)
                }
            }
        }

        // stableURL is already a copy in the documents directory made synchronously
        // in the picker callback — no second copy needed here.
        private func importVideo(from stableURL: URL) async {
            // Validate the stable copy
            let validationResult = await VideoFileManager.validateVideo(at: stableURL)

            switch validationResult {
            case .failure(let error):
                try? FileManager.default.removeItem(at: stableURL)
                await MainActor.run {
                    parent.onImportComplete()
                    parent.onError(error.localizedDescription)
                }
                return
            case .success:
                break
            }

            let destinationURL = stableURL

            // Generate thumbnail
            let thumbnailResult = await VideoFileManager.generateThumbnail(from: destinationURL)
            let thumbnailPath: String?

            switch thumbnailResult {
            case .success(let path):
                thumbnailPath = path
            case .failure:
                thumbnailPath = nil
            }

            // Get video duration
            let asset = AVURLAsset(url: destinationURL)
            let duration = try? await asset.load(.duration)
            let durationSeconds = duration.map { CMTimeGetSeconds($0) }

            // Create VideoClip model
            await MainActor.run {
                let fileName = destinationURL.lastPathComponent
                let videoClip = VideoClip(fileName: fileName, filePath: destinationURL.path)
                videoClip.athlete = parent.athlete
                videoClip.season = parent.athlete.activeSeason
                videoClip.thumbnailPath = thumbnailPath
                videoClip.duration = durationSeconds
                videoClip.createdAt = Date()

                parent.modelContext.insert(videoClip)

                do {
                    try parent.modelContext.save()
                    parent.onImportComplete()
                } catch {
                    // Clean up on save failure
                    VideoFileManager.cleanup(url: destinationURL)
                    if let thumbPath = thumbnailPath {
                        try? FileManager.default.removeItem(atPath: thumbPath)
                    }
                    parent.onImportComplete()
                    parent.onError("Failed to save video: \(error.localizedDescription)")
                }
            }
        }
    }
}
