//
//  JournalFeedSections.swift
//  PlayerPath
//
//  Buckets an already reverse-chron-sorted Journal feed slice into human date
//  sections ("This Week", "Last Week", "June 2026", …) for lightweight section
//  headers. Pure helper — mirrors JournalFeedBuilder's style (no querying, no
//  persistence). Operates on the WINDOWED slice, so a partially-loaded month
//  simply grows its section as more pages load.
//

import Foundation

/// One date bucket of the (already windowed) Journal feed.
struct JournalFeedSection: Identifiable {
    let title: String
    let entries: [JournalEntry]
    /// The input is sorted descending and the bucket function is monotonic over
    /// descending dates, so a title never repeats — making it a stable id.
    var id: String { title }
}

enum JournalFeedSections {
    /// Buckets an already reverse-chron-sorted slice in one forward pass. Because
    /// entries arrive newest-first and buckets are monotonic, sections emerge in
    /// order with no `Dictionary(grouping:)` + re-sort. `now`/`calendar` are
    /// injectable for tests/previews.
    static func build(
        from entries: [JournalEntry],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [JournalFeedSection] {
        guard !entries.isEmpty else { return [] }

        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)
        let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: now)
            .flatMap { calendar.dateInterval(of: .weekOfYear, for: $0) }

        var sections: [JournalFeedSection] = []
        var openBucket: Bucket?
        var openEntries: [JournalEntry] = []

        func closeOpenSection() {
            guard let bucket = openBucket, !openEntries.isEmpty else { return }
            sections.append(JournalFeedSection(title: bucket.title(calendar: calendar),
                                               entries: openEntries))
        }

        for entry in entries {
            let bucket = Self.bucket(for: entry.date,
                                     now: now,
                                     calendar: calendar,
                                     thisWeek: thisWeek,
                                     lastWeek: lastWeek)
            if bucket != openBucket {
                closeOpenSection()
                openBucket = bucket
                openEntries = [entry]
            } else {
                openEntries.append(entry)
            }
        }
        closeOpenSection()
        return sections
    }

    // MARK: - Bucketing

    private enum Bucket: Equatable {
        case upcoming
        case thisWeek
        case lastWeek
        case month(year: Int, month: Int)
        case undated

        func title(calendar: Calendar) -> String {
            switch self {
            case .upcoming: return "Upcoming"
            case .thisWeek: return "This Week"
            case .lastWeek: return "Last Week"
            case .undated:  return "Undated"
            case .month(let year, let month):
                var comps = DateComponents()
                comps.year = year
                comps.month = month
                comps.day = 1
                let date = calendar.date(from: comps) ?? .distantPast
                return Self.monthFormatter.string(from: date)
            }
        }

        /// "MMMM yyyy" → "June 2026". Built once, reused across section starts.
        private static let monthFormatter: DateFormatter = {
            let f = DateFormatter()
            f.setLocalizedDateFormatFromTemplate("MMMM yyyy")
            return f
        }()
    }

    private static func bucket(
        for date: Date,
        now: Date,
        calendar: Calendar,
        thisWeek: DateInterval?,
        lastWeek: DateInterval?
    ) -> Bucket {
        // Exact nil-date sentinel (JournalEntry.date fallbacks) — trailing bucket,
        // else it would render as a month/year in year 0001.
        if date == .distantPast { return .undated }
        if date > now, thisWeek?.contains(date) != true { return .upcoming }
        if thisWeek?.contains(date) == true { return .thisWeek }
        if lastWeek?.contains(date) == true { return .lastWeek }
        let comps = calendar.dateComponents([.year, .month], from: date)
        return .month(year: comps.year ?? 0, month: comps.month ?? 0)
    }
}
