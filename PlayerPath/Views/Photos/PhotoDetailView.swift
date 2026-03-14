//
//  PhotoDetailView.swift
//  PlayerPath
//
//  Full-screen photo detail with pinch-to-zoom, caption editing, and metadata.
//

import SwiftUI
import SwiftData

struct PhotoDetailView: View {
    @Bindable var photo: Photo
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var fullImage: UIImage?
    @State private var showingDeleteConfirmation = false
    @State private var showingTagSheet = false
    @State private var isEditingCaption = false
    @State private var captionText: String = ""
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    let onDelete: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let fullImage {
                Image(uiImage: fullImage)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = lastScale * value
                            }
                            .onEnded { value in
                                lastScale = scale
                                // Snap back if zoomed out too far
                                if scale < 1.0 {
                                    withAnimation(.spring(response: 0.3)) {
                                        scale = 1.0
                                        lastScale = 1.0
                                    }
                                }
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.3)) {
                            if scale > 1.0 {
                                scale = 1.0
                                lastScale = 1.0
                            } else {
                                scale = 2.5
                                lastScale = 2.5
                            }
                        }
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
            }
        }
        .alert("Delete Photo?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
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
                try? modelContext.save()
            }
            .presentationDetents([.height(200)])
        }
        .sheet(isPresented: $showingTagSheet) {
            PhotoTagSheet(photo: photo)
        }
        .task {
            await loadFullImage()
        }
        .onAppear {
            captionText = photo.caption ?? ""
        }
    }

    // MARK: - Metadata Overlay

    @ViewBuilder
    private var metadataOverlay: some View {
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
            .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
        )
    }

    private func loadFullImage() async {
        if let image = UIImage(contentsOfFile: photo.filePath) {
            fullImage = image
        }
    }
}

// MARK: - Caption Edit Sheet

private struct CaptionEditSheet: View {
    @Binding var captionText: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("Add a caption...", text: $captionText)
                    .focused($isFocused)
                    .submitLabel(.done)
                    .onSubmit {
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
                        onSave()
                        dismiss()
                    }
                }
            }
            .onAppear { isFocused = true }
        }
    }
}
