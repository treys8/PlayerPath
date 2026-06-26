//
//  ReelExportControls.swift
//  PlayerPath
//
//  Reusable Save-to-Photos + Share buttons for a stitched reel MP4. Shared by
//  StitchedReelPlayerView (today's reel) and GenerateReelView (game/season/golf).
//  Save mirrors VideoClipCard.saveToPhotos() exactly; Share reuses the ShareSheet
//  wrapper. Both fire the (self-gating) review prompt on completion.
//
//  Designed to sit in dark player chrome — defaults to white tint.
//

import SwiftUI
import Photos

struct ReelExportControls: View {
    /// The stitched reel file. Owned by StitchedReelCache, so the share sheet must
    /// NOT delete it on dismiss (cleanupFilesOnDismiss: false).
    let url: URL
    var tint: Color = .white

    @State private var isSavingToPhotos = false
    @State private var showingShare = false
    @State private var showingSaveSuccess = false
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        HStack(spacing: 20) {
            Button {
                Haptics.light()
                saveToPhotos()
            } label: {
                if isSavingToPhotos {
                    ProgressView().tint(tint)
                } else {
                    Image(systemName: "square.and.arrow.down")
                }
            }
            .disabled(isSavingToPhotos)
            .accessibilityLabel("Save reel to Photos")

            Button {
                Haptics.light()
                // Guard a missing/empty export before handing it to the share sheet.
                guard reelFileIsUsable else {
                    errorMessage = "Reel file not found. Try generating it again."
                    showingError = true
                    return
                }
                showingShare = true
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Share reel")
        }
        .font(.title3)
        .foregroundStyle(tint)
        .sheet(isPresented: $showingShare, onDismiss: {
            // Fires whenever the sheet closes; ReviewPromptManager self-gates so an
            // occasional cancel-without-share is harmless.
            ReviewPromptManager.shared.requestReviewIfAppropriate()
        }) {
            ShareSheet(items: [url], cleanupFilesOnDismiss: false)
        }
        .toast(isPresenting: $showingSaveSuccess, message: "Saved to Photos")
        .alert("Couldn't Save Reel", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    /// True when the reel file exists on disk and is non-empty — a failed/cancelled
    /// export can leave a missing or zero-byte file, which must never reach share/save.
    private var reelFileIsUsable: Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0
        return size > 0
    }

    // Mirrors VideoClipCard.saveToPhotos() — addOnly auth → creation request.
    private func saveToPhotos() {
        guard reelFileIsUsable else {
            errorMessage = "Reel file not found. Try generating it again."
            showingError = true
            return
        }

        isSavingToPhotos = true
        Task { @MainActor in
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                isSavingToPhotos = false
                errorMessage = "Photo library access is required to save reels. Please enable it in Settings > PlayerPath > Photos."
                showingError = true
                return
            }

            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }
                isSavingToPhotos = false
                Haptics.success()
                showingSaveSuccess = true
                ReviewPromptManager.shared.requestReviewIfAppropriate()
            } catch {
                isSavingToPhotos = false
                errorMessage = "Could not save reel to Photos. \(error.localizedDescription)"
                showingError = true
            }
        }
    }
}
