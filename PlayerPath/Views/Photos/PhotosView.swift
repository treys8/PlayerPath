//
//  PhotosView.swift
//  PlayerPath
//
//  Grid view of all photos for an athlete. Supports camera capture
//  and photo library import with optional game/practice tagging.
//

import SwiftUI
import SwiftData
import PhotosUI

struct PhotosView: View {
    let athlete: Athlete
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Photo.createdAt, order: .reverse) private var allPhotos: [Photo]

    private var photos: [Photo] {
        let athleteID = athlete.id
        let filtered = allPhotos.filter { $0.athlete?.id == athleteID }

        switch activeFilter {
        case .all:
            return filtered
        case .games:
            return filtered.filter { $0.game != nil }
        case .practice:
            return filtered.filter { $0.practice != nil }
        }
    }

    // State
    @State private var activeFilter: PhotoFilter = .all
    @State private var showingSourcePicker = false
    @State private var showingCamera = false
    @State private var showingLibraryPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isImporting = false

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    enum PhotoFilter: String, CaseIterable {
        case all = "All"
        case games = "Games"
        case practice = "Practice"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter chips
            filterBar

            if photos.isEmpty {
                emptyState
            } else {
                photosGrid
            }
        }
        .navigationTitle("Photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSourcePicker = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .confirmationDialog("Add Photo", isPresented: $showingSourcePicker) {
            Button("Take Photo") {
                showingCamera = true
            }
            Button("Choose from Library") {
                showingLibraryPicker = true
            }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $showingCamera) {
            ImagePicker(sourceType: .camera) { image in
                savePhoto(image)
            }
        }
        .photosPicker(
            isPresented: $showingLibraryPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: 20,
            matching: .images
        )
        .onChange(of: selectedPhotoItems) { _, items in
            guard !items.isEmpty else { return }
            importPhotos(items)
            selectedPhotoItems = []
        }
        .overlay {
            if isImporting {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                        Text("Importing...")
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(PhotoFilter.allCases, id: \.self) { filter in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        activeFilter = filter
                    }
                } label: {
                    Text(filter.rawValue)
                        .font(.subheadline)
                        .fontWeight(activeFilter == filter ? .semibold : .regular)
                        .foregroundColor(activeFilter == filter ? .white : .secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(activeFilter == filter ? Color.pink : Color(.systemGray5))
                        )
                }
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Photos Grid

    private var photosGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(photos) { photo in
                    NavigationLink {
                        PhotoDetailView(photo: photo) {
                            deletePhoto(photo)
                        }
                    } label: {
                        PhotoThumbnailCell(photo: photo) {
                            deletePhoto(photo)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Photos Yet")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Tap + to take a photo or\nchoose from your library")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    // MARK: - Actions

    private func savePhoto(_ image: UIImage) {
        Task {
            do {
                _ = try await PhotoPersistenceService().savePhoto(
                    image: image,
                    context: modelContext,
                    athlete: athlete
                )
                Haptics.success()
            } catch {
                print("PhotosView: Failed to save photo: \(error)")
                Haptics.error()
            }
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        Task {
            isImporting = true
            defer { isImporting = false }

            let service = PhotoPersistenceService()
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    _ = try? await service.savePhoto(
                        image: image,
                        context: modelContext,
                        athlete: athlete
                    )
                }
            }
            Haptics.success()
        }
    }

    private func deletePhoto(_ photo: Photo) {
        PhotoPersistenceService().deletePhoto(photo, context: modelContext)
        Haptics.light()
    }
}
