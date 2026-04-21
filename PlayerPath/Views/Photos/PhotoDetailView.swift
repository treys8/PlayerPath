//
//  PhotoDetailView.swift
//  PlayerPath
//
//  Full-screen photo detail with pinch-to-zoom, caption editing, and metadata.
//

import SwiftUI
import SwiftData
import Photos

struct PhotoDetailView: View {
    @Bindable var photo: Photo
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var fullImage: UIImage?
    @State private var loadFailed = false
    @State private var showingDeleteConfirmation = false
    @State private var showingTagSheet = false
    @State private var isEditingCaption = false
    @State private var captionText: String = ""
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    /// Separate from `scale`: `.fill` = photo crops to fill the screen (no
    /// letterbox), `.fit` = photo letterboxes to show every pixel. Double-tap
    /// toggles between these two — pinch only adjusts zoom on top.
    @State private var photoContentMode: ContentMode = .fill
    /// Pan offset when the photo is zoomed in. Reset to `.zero` any time
    /// scale returns to 1× so the next zoom-in starts centered.
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showingSavedToast = false
    @State private var saveError: String?

    let onDelete: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let fullImage {
                // Fill the screen by default (no letterbox). Double-tap toggles
                // fit (see the whole photo, letterboxed) vs fill (cropped). Pinch
                // adjusts zoom from 1× to 5× on top of whichever mode is active.
                // Drag pans when zoomed in.
                GeometryReader { geometry in
                    Image(uiImage: fullImage)
                        .resizable()
                        .aspectRatio(contentMode: photoContentMode)
                        .scaleEffect(scale)
                        .offset(offset)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .contentShape(Rectangle())
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = min(5.0, max(1.0, lastScale * value))
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                    if scale == 1.0 {
                                        // Zoomed back to default — drop any pan
                                        // so the next zoom starts centered.
                                        withAnimation(.spring(response: 0.3)) {
                                            offset = .zero
                                            lastOffset = .zero
                                        }
                                    }
                                }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    // Pan only when zoomed in; at 1× a drag
                                    // would uselessly shove a screen-filling
                                    // image around empty canvas.
                                    guard scale > 1.0 else { return }
                                    let proposed = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                    offset = clampOffset(proposed, scale: scale, in: geometry.size)
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.3)) {
                                if scale > 1.0 {
                                    // Zoomed in → reset to default zoom + pan.
                                    scale = 1.0
                                    lastScale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    // At default zoom → toggle fit/fill.
                                    photoContentMode = photoContentMode == .fill ? .fit : .fill
                                }
                            }
                        }
                }
            } else if loadFailed {
                VStack(spacing: 8) {
                    Image(systemName: photo.cloudURL != nil ? "icloud.and.arrow.down" : "photo")
                        .font(.largeTitle)
                        .foregroundColor(.white.opacity(0.5))
                    Text(photo.cloudURL != nil ? "Photo not yet downloaded" : "Photo unavailable")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.5))
                }
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .overlay(alignment: .bottom) {
            if scale <= 1.0 {
                metadataOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let fullImage {
                        ShareLink(item: Image(uiImage: fullImage), preview: SharePreview("Photo", image: Image(uiImage: fullImage)))

                        Button {
                            saveToCameraRoll(fullImage)
                        } label: {
                            Label("Save to Camera Roll", systemImage: "square.and.arrow.down")
                        }
                    }

                    Button {
                        showingTagSheet = true
                    } label: {
                        Label("Tag to Game/Practice", systemImage: "tag")
                    }

                    Button {
                        isEditingCaption = true
                        captionText = photo.caption ?? ""
                    } label: {
                        Label(photo.caption != nil ? "Edit Caption" : "Add Caption", systemImage: "text.bubble")
                    }

                    Divider()

                    Button(role: .destructive) {
                        Haptics.warning()
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Photo", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .white.opacity(0.3))
                        .font(.title3)
                }
                .accessibilityLabel("Photo options")
            }
        }
        .alert("Delete Photo?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Haptics.heavy()
                onDelete()
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This photo will be permanently deleted.")
        }
        .sheet(isPresented: $isEditingCaption) {
            CaptionEditSheet(captionText: $captionText) {
                photo.caption = captionText.isEmpty ? nil : captionText
                photo.needsSync = true
                ErrorHandlerService.shared.saveContext(modelContext, caller: "PhotoDetail.saveCaption")
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingTagSheet) {
            PhotoTagSheet(photo: photo)
        }
        .toast(isPresenting: $showingSavedToast, message: "Saved to Camera Roll")
        .alert("Cannot Save Photo", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        .task {
            await loadFullImage()
        }
        .onAppear {
            captionText = photo.caption ?? ""
        }
        .onDisappear {
            fullImage = nil
        }
    }

    // MARK: - Metadata Overlay

    @ViewBuilder
    private var metadataOverlay: some View {
        // Modifier order is intentional: padding → frame(maxWidth: .infinity)
        // → background. Putting padding AFTER the infinity frame expands the
        // view past the container by 2×padding.horizontal, which clips content
        // on the leading edge (e.g. "Apr " disappearing from the date label).
        VStack(alignment: .leading, spacing: 6) {
            if let caption = photo.caption, !caption.isEmpty {
                Text(caption)
                    .font(.body)
                    .foregroundColor(.white)
            }

            HStack(spacing: 12) {
                if let date = photo.createdAt {
                    Label(date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                }

                if let game = photo.game {
                    Label("vs \(game.opponent)", systemImage: "baseball.diamond.bases")
                } else if photo.practice != nil {
                    Label("Practice", systemImage: "figure.run")
                }
            }
            .font(.caption)
            .foregroundColor(.white.opacity(0.85))
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
    }

    /// Clamps a proposed pan offset so the zoomed image's edges can't be
    /// dragged past the corresponding screen edges. The extra-per-side is
    /// `(scale - 1) * viewport / 2` in each dimension, assuming the image's
    /// base size at scale 1× is at least the viewport (true for `.fill`; for
    /// `.fit` the bound is tighter but this cap is safe and intuitive).
    private func clampOffset(_ proposed: CGSize, scale: CGFloat, in viewport: CGSize) -> CGSize {
        let maxX = max(0, (scale - 1) * viewport.width / 2)
        let maxY = max(0, (scale - 1) * viewport.height / 2)
        return CGSize(
            width: min(maxX, max(-maxX, proposed.width)),
            height: min(maxY, max(-maxY, proposed.height))
        )
    }

    private func loadFullImage() async {
        if let image = UIImage(contentsOfFile: photo.resolvedFilePath) {
            fullImage = image
            return
        }
        // If local file is missing but we have a cloud URL, try downloading
        if let cloudURL = photo.cloudURL, !cloudURL.isEmpty {
            do {
                try await VideoCloudManager.shared.downloadPhoto(from: cloudURL, to: photo.resolvedFilePath)
                if let image = UIImage(contentsOfFile: photo.resolvedFilePath) {
                    fullImage = image
                    return
                }
            } catch {
                ErrorHandlerService.shared.handle(error, context: "PhotoDetail.downloadPhoto", showAlert: false)
            }
        }
        loadFailed = true
    }

    private func saveToCameraRoll(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    saveError = "Please allow photo library access in Settings."
                }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                Task { @MainActor in
                    if success {
                        showingSavedToast = true
                    } else {
                        saveError = error?.localizedDescription ?? "Failed to save photo."
                    }
                }
            }
        }
    }
}

// MARK: - Caption Edit Sheet

struct CaptionEditSheet: View {
    @Binding var captionText: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var hasSaved = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Add a caption...", text: $captionText)
                    .focused($isFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        guard !hasSaved else { return }
                        hasSaved = true
                        onSave()
                        dismiss()
                    }
            }
            .navigationTitle("Caption")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard !hasSaved else { return }
                        hasSaved = true
                        onSave()
                        dismiss()
                    }
                }
            }
            .onAppear { isFocused = true }
        }
    }
}
