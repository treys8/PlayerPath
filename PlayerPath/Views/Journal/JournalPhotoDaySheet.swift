//
//  JournalPhotoDaySheet.swift
//  PlayerPath
//
//  The day-scoped photo grid opened when a Journal "Photos" group row is tapped.
//  Re-queries the athlete's photos (rather than holding the tapped snapshot) so
//  deletes made from a photo's detail screen update the grid live, and auto-
//  dismisses once the day has no standalone photos left. Lone photos never reach
//  here — the feed keeps those as direct-to-detail rows (see
//  JournalFeedBuilder.photoEntries).
//

import SwiftUI
import SwiftData

/// Sheet selection token for a day-scoped photo grid, identified by the day so
/// re-tapping the same group is idempotent.
struct JournalPhotoDay: Identifiable {
    let id: Date          // start of day
    var day: Date { id }
}

struct JournalPhotoDaySheet: View {
    let athlete: Athlete
    let day: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allPhotos: [Photo]

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 4)]

    init(athlete: Athlete, day: Date) {
        self.athlete = athlete
        self.day = day
        let id = athlete.id
        // Query is per-athlete only; orphan + same-day filtering happens in Swift
        // below (relationship `== nil` and date transforms are unsafe inside a
        // #Predicate). Reactive on delete so the grid and its empty-check update.
        _allPhotos = Query(
            filter: #Predicate<Photo> { $0.athlete?.id == id },
            sort: [SortDescriptor(\Photo.createdAt, order: .reverse)]
        )
    }

    /// This day's standalone photos, newest first (the @Query is already sorted).
    private var dayPhotos: [Photo] {
        let calendar = Calendar.current
        return allPhotos.filter {
            $0.game == nil && $0.practice == nil &&
            calendar.isDate($0.createdAt ?? .distantPast, inSameDayAs: day)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(dayPhotos) { photo in
                        NavigationLink {
                            PhotoDetailView(photo: photo) { delete(photo) }
                        } label: {
                            PhotoThumbnailCell(photo: photo, style: .dense) { delete(photo) }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
            }
            .background(Theme.surface)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // Deleting the last photo of the day empties the grid — close rather
            // than leave a blank sheet behind.
            .onChange(of: dayPhotos.isEmpty) { _, isEmpty in
                if isEmpty { dismiss() }
            }
        }
    }

    private func delete(_ photo: Photo) {
        PhotoPersistenceService().deletePhoto(photo, context: modelContext)
        Haptics.light()
    }

    private var title: String {
        day.formatted(.dateTime.month(.abbreviated).day().year())
    }
}
