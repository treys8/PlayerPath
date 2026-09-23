//
//  PhotoMonthSections.swift
//  PlayerPath
//
//  Groups the Photos grid into calendar-month sections ("April 2026"). The
//  builder preserves the incoming order, so the swipe viewer — which pages over
//  the same flat array — always matches what the grid shows.
//

import Foundation

struct PhotoMonthSection: Identifiable {
    /// Start of the month, or `.distantPast` for the trailing "Undated" section.
    let id: Date
    let title: String
    let photos: [Photo]

    private static let titleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return f
    }()

    /// Buckets `photos` (already sorted newest-first) by month. Photos with no
    /// `createdAt` go in a final "Undated" section.
    static func build(from photos: [Photo]) -> [PhotoMonthSection] {
        let calendar = Calendar.current
        var sections: [PhotoMonthSection] = []
        var currentKey: Date?
        var currentPhotos: [Photo] = []
        var undated: [Photo] = []

        func flush() {
            guard let key = currentKey, !currentPhotos.isEmpty else { return }
            sections.append(PhotoMonthSection(id: key, title: titleFormatter.string(from: key), photos: currentPhotos))
        }

        for photo in photos {
            guard let date = photo.createdAt,
                  let monthStart = calendar.dateInterval(of: .month, for: date)?.start else {
                undated.append(photo)
                continue
            }
            if monthStart != currentKey {
                flush()
                currentKey = monthStart
                currentPhotos = []
            }
            currentPhotos.append(photo)
        }
        flush()

        if !undated.isEmpty {
            sections.append(PhotoMonthSection(id: .distantPast, title: "Undated", photos: undated))
        }
        return sections
    }

    /// Copy of `sections` without `photoID`, dropping any section left empty.
    /// Used to pull the hero photo out of the grid below it.
    static func removing(_ photoID: UUID, from sections: [PhotoMonthSection]) -> [PhotoMonthSection] {
        sections.compactMap { section in
            guard section.photos.contains(where: { $0.id == photoID }) else { return section }
            let remaining = section.photos.filter { $0.id != photoID }
            return remaining.isEmpty ? nil : PhotoMonthSection(id: section.id, title: section.title, photos: remaining)
        }
    }
}
