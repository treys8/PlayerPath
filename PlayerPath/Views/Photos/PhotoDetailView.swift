//
//  PhotoDetailView.swift
//  PlayerPath
//
//  Full-screen, swipeable photo viewer. Pages through a set of photos (pinch
//  zoom + double-tap fit/fill per page live in ZoomablePhotoPage) while this
//  container owns the chrome — close button, "N of M" counter, favorite, the
//  options menu, and the metadata overlay — so it renders once no matter how
//  many pages are loaded.
//
//  Present it full-screen via the `.photoViewer(_:in:onDelete:)` modifier below,
//  which wraps it in a NavigationStack inside a `.fullScreenCover`. A stray
//  NavigationLink push (e.g. from a LazyVGrid inside a List) is unreliable here:
//  it can double-push and strand the user with no working way out.
//
//  Dismissal is the ✕ button plus, on iOS 18+, the zoom transition's built-in
//  swipe-down. Do NOT add a custom swipe-to-dismiss DragGesture to the pages:
//  any drag recognizer attached to page content starves the TabView pager of
//  horizontal drags, killing photo-to-photo swiping (verified on iOS 26).
//

import SwiftUI
import SwiftData
import Photos

struct PhotoDetailView: View {
    let photos: [Photo]
    let onDelete: (Photo) -> Void

    @State private var selectionID: Photo.ID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var showingDeleteConfirmation = false
    @State private var showingTagSheet = false
    @State private var isEditingCaption = false
    @State private var captionText: String = ""
    @State private var showingSavedToast = false
    @State private var saveError: String?
    /// Whether the currently visible page is zoomed in — drives hiding the
    /// metadata overlay. Only the on-screen page emits zoom changes.
    @State private var isCurrentPageZoomed = false
    /// Immersive mode — a single tap hides the toolbar + metadata + status bar.
    @State private var chromeHidden = false

    /// Paged viewer over `photos`, opening on `initialPhotoID`.
    init(photos: [Photo], initialPhotoID: Photo.ID, onDelete: @escaping (Photo) -> Void) {
        self.photos = photos
        self._selectionID = State(initialValue: initialPhotoID)
        self.onDelete = onDelete
    }

    /// Single-photo convenience (no swiping) for callers that show one photo.
    init(photo: Photo, onDelete: @escaping () -> Void) {
        self.init(photos: [photo], initialPhotoID: photo.id) { _ in onDelete() }
    }

    /// The photo the chrome (toolbar, metadata, sheets) currently acts on.
    /// `photos` is always non-empty (the viewer is only presented over a set
    /// that contains the tapped photo), so `first!` is the safe fallback.
    private var currentPhoto: Photo {
        photos.first { $0.id == selectionID } ?? photos.first!
    }

    private var currentIndex: Int? {
        photos.firstIndex { $0.id == selectionID }
    }

    private var showChrome: Bool {
        !chromeHidden
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectionID) {
                ForEach(photos) { photo in
                    ZoomablePhotoPage(
                        photo: photo,
                        onZoomChanged: { zoomed in
                            // Ignore stray reports from off-screen pages.
                            if photo.id == selectionID { isCurrentPageZoomed = zoomed }
                        },
                        onSingleTap: {
                            withAnimation(.easeInOut(duration: 0.2)) { chromeHidden.toggle() }
                        }
                    )
                    .tag(photo.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
        }
        .statusBarHidden(chromeHidden)
        .overlay(alignment: .bottom) {
            if showChrome && !isCurrentPageZoomed {
                metadataOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: selectionID) {
            // New page starts fresh: un-zoomed, chrome shown.
            isCurrentPageZoomed = false
            chromeHidden = false
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(showChrome ? .visible : .hidden, for: .navigationBar)
        // Own the exit control explicitly. The default back button is unreliable
        // here (this is presented full-screen with the bar background hidden), so
        // provide an unmistakable close affordance.
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .white.opacity(0.3))
                        .font(.title3)
                }
                .accessibilityLabel("Close")
            }

            ToolbarItem(placement: .principal) {
                if photos.count > 1, let index = currentIndex {
                    Text("\(index + 1) of \(photos.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    toggleHighlight()
                } label: {
                    Image(systemName: currentPhoto.isHighlight ? "star.fill" : "star")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(currentPhoto.isHighlight ? .yellow : .white, .white.opacity(0.3))
                        .font(.title3)
                }
                .accessibilityLabel(currentPhoto.isHighlight ? "Remove favorite" : "Mark as favorite")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if currentPhoto.isAvailableOffline, let url = currentPhoto.fileURL {
                        ShareLink(item: url, preview: SharePreview(currentPhoto.caption ?? "Photo")) {
                            Label("Share Photo", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            saveCurrentToCameraRoll()
                        } label: {
                            Label("Save to Camera Roll", systemImage: "square.and.arrow.down")
                        }
                    }

                    Button {
                        showingTagSheet = true
                    } label: {
                        Label(currentPhoto.athlete?.sport == .golf ? "Tag to Tournament/Practice" : "Tag to Game/Practice", systemImage: "tag")
                    }

                    if let athlete = currentPhoto.athlete {
                        let isHeadshot = athlete.headshotPhotoId == currentPhoto.id
                        Button {
                            toggleHeadshot(for: athlete)
                        } label: {
                            Label(isHeadshot ? "Remove as Headshot" : "Set as Headshot",
                                  systemImage: isHeadshot ? "person.crop.circle.badge.xmark" : "person.crop.circle.badge.checkmark")
                        }
                    }

                    Button {
                        isEditingCaption = true
                        captionText = currentPhoto.caption ?? ""
                    } label: {
                        Label(currentPhoto.caption != nil ? "Edit Caption" : "Add Caption", systemImage: "text.bubble")
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
                // Tear the pager down BEFORE deleting the model. The TabView's
                // ForEach(photos) still references this Photo; deleting it while
                // the pager is live would trap on the invalidated @Model as the
                // body re-renders. Dismiss first, delete on the next runloop.
                let photo = currentPhoto
                dismiss()
                DispatchQueue.main.async {
                    onDelete(photo)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This photo will be permanently deleted.")
        }
        .sheet(isPresented: $isEditingCaption) {
            CaptionEditSheet(captionText: $captionText) {
                let photo = currentPhoto
                photo.caption = captionText.isEmpty ? nil : captionText
                photo.needsSync = true
                ErrorHandlerService.shared.saveContext(modelContext, caller: "PhotoDetail.saveCaption")
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingTagSheet) {
            PhotoTagSheet(photo: currentPhoto)
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
    }

    // MARK: - Metadata Overlay

    @ViewBuilder
    private var metadataOverlay: some View {
        let photo = currentPhoto
        // Modifier order is intentional: padding → frame(maxWidth: .infinity)
        // → background. Putting padding AFTER the infinity frame expands the
        // view past the container by 2×padding.horizontal, which clips content
        // on the leading edge (e.g. "Apr " disappearing from the date label).
        VStack(alignment: .leading, spacing: 6) {
            if let caption = photo.caption, !caption.isEmpty {
                Text(caption)
                    .font(.bodyLarge)
                    .foregroundColor(.white)
            }

            HStack(spacing: 12) {
                if let date = photo.createdAt {
                    Label(date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                }

                if let game = photo.game {
                    Label(game.opponentLabel, systemImage: game.isGolf ? "figure.golf" : "baseball.diamond.bases")
                } else if photo.practice != nil {
                    Label("Practice", systemImage: "figure.run")
                }
            }
            .font(.bodySmall)
            .foregroundColor(.white.opacity(0.85))
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Actions

    private func toggleHighlight() {
        let photo = currentPhoto
        photo.isHighlight.toggle()
        photo.needsSync = true
        ErrorHandlerService.shared.saveContext(modelContext, caller: "PhotoDetail.toggleHighlight")
        Haptics.light()
    }

    /// Set this photo as the athlete's headshot, or clear it if it already is.
    /// Only the `headshotPhotoId` pointer syncs on the athlete; the image rides
    /// the normal Photo path, so the id resolves to the already-synced Photo on
    /// another device.
    private func toggleHeadshot(for athlete: Athlete) {
        let photo = currentPhoto
        athlete.headshotPhotoId = (athlete.headshotPhotoId == photo.id) ? nil : photo.id
        athlete.needsSync = true
        ErrorHandlerService.shared.saveContext(modelContext, caller: "PhotoDetail.toggleHeadshot")
        Haptics.medium()
    }

    /// Decode the current photo's file and save it to the camera roll. The
    /// container doesn't hold a decoded image (each page owns its own), so
    /// decode on demand from the resolved file path.
    private func saveCurrentToCameraRoll() {
        let path = currentPhoto.resolvedFilePath
        Task {
            guard let image = await UIImage.decodedFullRes(atPath: path) else {
                saveError = "Photo unavailable."
                return
            }
            saveToCameraRoll(image)
        }
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

// MARK: - Presentation

extension View {
    /// Presents a full-screen, swipeable photo viewer over `photos`, opening on
    /// the bound photo. Prefer this over a NavigationLink push: it reliably
    /// dismisses and covers the tab bar. `selection` doubles as the trigger
    /// (non-nil → presented) and the initial page. Pass `namespace` (paired with
    /// `.photoTransitionSource` on the tapped cell) for the iOS 18 zoom transition.
    func photoViewer(_ selection: Binding<Photo?>,
                     in photos: [Photo],
                     namespace: Namespace.ID? = nil,
                     onDelete: @escaping (Photo) -> Void) -> some View {
        fullScreenCover(item: selection) { photo in
            NavigationStack {
                PhotoDetailView(photos: photos, initialPhotoID: photo.id, onDelete: onDelete)
            }
            .photoZoomTransition(sourceID: photo.id, in: namespace)
        }
    }

    /// Marks this view as the zoom-transition source for `id`, paired with the
    /// `namespace` passed to `photoViewer`. iOS 18+ only; a no-op on iOS 17,
    /// which keeps the default cover presentation.
    @ViewBuilder
    func photoTransitionSource(_ id: Photo.ID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// Applies the paired zoom transition to the presented viewer (iOS 18+).
    @ViewBuilder
    fileprivate func photoZoomTransition(sourceID: Photo.ID, in namespace: Namespace.ID?) -> some View {
        if #available(iOS 18.0, *), let namespace {
            navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self
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
            .ppDetailBackground()
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
