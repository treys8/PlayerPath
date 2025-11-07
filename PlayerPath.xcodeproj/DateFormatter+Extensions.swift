//
//  DateFormatter+Extensions.swift
//  PlayerPath
//
//  Created by Trey Schilling on 10/26/25.
//

import Foundation

// MARK: - DateFormatter Extensions
// Shared date formatters to prevent duplicate declarations
extension DateFormatter {
    
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter
    }()
    
    static let mediumDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    static let shortDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}