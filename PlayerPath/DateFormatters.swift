//
//  DateFormatters.swift
//  PlayerPath
//
//  Centralized DateFormatter instances to avoid duplication and ensure caching
//

import Foundation

extension DateFormatter {
    /// Medium date, no time (e.g., "Jan 15, 2026")
    static let mediumDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    /// Short date, no time (e.g., "1/15/26")
    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()

    /// Short time, no date (e.g., "3:30 PM")
    static let shortTime: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    /// Full date, no time (e.g., "Wednesday, January 15, 2026")
    static let fullDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        return f
    }()

    /// Short date + short time (e.g., "1/15/26, 3:30 PM")
    static let shortDateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    /// Month and day only (e.g., "Jan 15")
    static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    /// Compact short date (e.g., "1/15/26")
    static let compactDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d/yy"
        return f
    }()
}
