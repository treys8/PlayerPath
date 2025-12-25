//
//  StatisticsExportService.swift
//  PlayerPath
//
//  Service for exporting athlete statistics to CSV and PDF formats
//

import Foundation
import SwiftUI
import PDFKit
import UniformTypeIdentifiers

/// Service to export athlete statistics to various formats
@MainActor
final class StatisticsExportService {

    // MARK: - Public Export Methods

    /// Export statistics to CSV format
    static func exportToCSV(athlete: Athlete, stats: AthleteStatistics) -> Result<URL, ExportError> {
        let csvContent = generateCSVContent(athlete: athlete, stats: stats)

        do {
            let fileName = "\(athlete.name.replacingOccurrences(of: " ", with: "_"))_Stats_\(dateString()).csv"
            let fileURL = try saveToTemporaryFile(content: csvContent, fileName: fileName)
            return .success(fileURL)
        } catch {
            return .failure(.fileCreationFailed(error.localizedDescription))
        }
    }

    /// Export statistics to PDF format with formatted layout
    static func exportToPDF(athlete: Athlete, stats: AthleteStatistics, season: Season? = nil) -> Result<URL, ExportError> {
        let pdfData = generatePDFData(athlete: athlete, stats: stats, season: season)

        do {
            let fileName = "\(athlete.name.replacingOccurrences(of: " ", with: "_"))_Stats_\(dateString()).pdf"
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try pdfData.write(to: fileURL)
            return .success(fileURL)
        } catch {
            return .failure(.fileCreationFailed(error.localizedDescription))
        }
    }

    // MARK: - CSV Generation

    private static func generateCSVContent(athlete: Athlete, stats: AthleteStatistics) -> String {
        var csv = ""

        // Header
        csv += "PlayerPath Statistics Export\n"
        csv += "Generated: \(Date().formatted(date: .long, time: .shortened))\n"
        csv += "\n"

        // Athlete Info
        csv += "Athlete Information\n"
        csv += "Name,\(athlete.name)\n"
        csv += "Created,\(athlete.createdAt?.formatted(date: .long, time: .omitted) ?? "N/A")\n"
        csv += "\n"

        // Season Info (if active season)
        if let season = athlete.activeSeason {
            csv += "Active Season\n"
            csv += "Season Name,\(season.displayName)\n"
            csv += "Sport,\(season.sport.displayName)\n"
            csv += "Start Date,\(season.startDate?.formatted(date: .long, time: .omitted) ?? "N/A")\n"
            csv += "\n"
        }

        // Key Statistics
        csv += "Key Statistics\n"
        csv += "Metric,Value\n"
        csv += "Total Games,\(stats.totalGames)\n"
        csv += "At Bats,\(stats.atBats)\n"
        csv += "Hits,\(stats.hits)\n"
        csv += "Batting Average,\(String(format: "%.3f", stats.battingAverage))\n"
        csv += "On-Base Percentage,\(String(format: "%.3f", stats.onBasePercentage))\n"
        csv += "Slugging Percentage,\(String(format: "%.3f", stats.sluggingPercentage))\n"
        csv += "OPS,\(String(format: "%.3f", stats.onBasePercentage + stats.sluggingPercentage))\n"
        csv += "\n"

        // Hitting Breakdown
        csv += "Hitting Breakdown\n"
        csv += "Type,Count\n"
        csv += "Singles,\(stats.singles)\n"
        csv += "Doubles,\(stats.doubles)\n"
        csv += "Triples,\(stats.triples)\n"
        csv += "Home Runs,\(stats.homeRuns)\n"
        csv += "Walks,\(stats.walks)\n"
        csv += "\n"

        // Other Stats
        csv += "Other Statistics\n"
        csv += "Metric,Value\n"
        csv += "Runs,\(stats.runs)\n"
        csv += "RBIs,\(stats.rbis)\n"
        csv += "Strikeouts,\(stats.strikeouts)\n"
        csv += "Ground Outs,\(stats.groundOuts)\n"
        csv += "Fly Outs,\(stats.flyOuts)\n"
        csv += "\n"

        // Games Breakdown (if available)
        if let games = athlete.games?.filter({ $0.isComplete }), !games.isEmpty {
            csv += "Recent Games\n"
            csv += "Date,Opponent,Result\n"

            for game in games.prefix(10).sorted(by: { ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast) }) {
                let dateStr = game.date?.formatted(date: .abbreviated, time: .omitted) ?? "N/A"
                let opponent = game.opponent.isEmpty ? "Unknown" : game.opponent
                csv += "\(dateStr),\(opponent),Completed\n"
            }
        }

        return csv
    }

    // MARK: - PDF Generation

    private static func generatePDFData(athlete: Athlete, stats: AthleteStatistics, season: Season?) -> Data {
        let pageWidth: CGFloat = 612 // 8.5 inches
        let pageHeight: CGFloat = 792 // 11 inches
        let margin: CGFloat = 50

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        let data = renderer.pdfData { context in
            context.beginPage()

            var yPosition: CGFloat = margin
            let contentWidth = pageWidth - (2 * margin)

            // Title
            let titleFont = UIFont.boldSystemFont(ofSize: 24)
            let titleText = "PlayerPath Statistics Report"
            let titleRect = CGRect(x: margin, y: yPosition, width: contentWidth, height: 30)
            titleText.draw(in: titleRect, withAttributes: [
                .font: titleFont,
                .foregroundColor: UIColor.black
            ])
            yPosition += 40

            // Athlete Name
            let nameFont = UIFont.systemFont(ofSize: 20, weight: .semibold)
            let nameText = athlete.name
            let nameRect = CGRect(x: margin, y: yPosition, width: contentWidth, height: 25)
            nameText.draw(in: nameRect, withAttributes: [
                .font: nameFont,
                .foregroundColor: UIColor.darkGray
            ])
            yPosition += 35

            // Generated Date
            let dateFont = UIFont.systemFont(ofSize: 10)
            let dateText = "Generated: \(Date().formatted(date: .long, time: .shortened))"
            let dateRect = CGRect(x: margin, y: yPosition, width: contentWidth, height: 15)
            dateText.draw(in: dateRect, withAttributes: [
                .font: dateFont,
                .foregroundColor: UIColor.gray
            ])
            yPosition += 25

            // Separator line
            let path = UIBezierPath()
            path.move(to: CGPoint(x: margin, y: yPosition))
            path.addLine(to: CGPoint(x: pageWidth - margin, y: yPosition))
            UIColor.lightGray.setStroke()
            path.lineWidth = 1
            path.stroke()
            yPosition += 20

            // Season Info (if available)
            if let season = season ?? athlete.activeSeason {
                yPosition = drawSection(
                    title: "Season Information",
                    items: [
                        ("Season", season.displayName),
                        ("Sport", season.sport.displayName),
                        ("Start Date", season.startDate?.formatted(date: .long, time: .omitted) ?? "N/A"),
                        ("Games", "\(season.totalGames)")
                    ],
                    yPosition: yPosition,
                    margin: margin,
                    contentWidth: contentWidth
                )
            }

            // Key Statistics Section
            yPosition = drawSection(
                title: "Key Statistics",
                items: [
                    ("Total Games", "\(stats.totalGames)"),
                    ("At Bats", "\(stats.atBats)"),
                    ("Hits", "\(stats.hits)"),
                    ("Batting Average", String(format: "%.3f", stats.battingAverage)),
                    ("On-Base %", String(format: "%.3f", stats.onBasePercentage)),
                    ("Slugging %", String(format: "%.3f", stats.sluggingPercentage)),
                    ("OPS", String(format: "%.3f", stats.onBasePercentage + stats.sluggingPercentage))
                ],
                yPosition: yPosition,
                margin: margin,
                contentWidth: contentWidth
            )

            // Hitting Breakdown
            yPosition = drawSection(
                title: "Hitting Breakdown",
                items: [
                    ("Singles", "\(stats.singles)"),
                    ("Doubles", "\(stats.doubles)"),
                    ("Triples", "\(stats.triples)"),
                    ("Home Runs", "\(stats.homeRuns)"),
                    ("Walks", "\(stats.walks)")
                ],
                yPosition: yPosition,
                margin: margin,
                contentWidth: contentWidth
            )

            // Other Statistics
            yPosition = drawSection(
                title: "Other Statistics",
                items: [
                    ("Runs", "\(stats.runs)"),
                    ("RBIs", "\(stats.rbis)"),
                    ("Strikeouts", "\(stats.strikeouts)"),
                    ("Ground Outs", "\(stats.groundOuts)"),
                    ("Fly Outs", "\(stats.flyOuts)")
                ],
                yPosition: yPosition,
                margin: margin,
                contentWidth: contentWidth
            )

            // Footer
            let footerFont = UIFont.systemFont(ofSize: 9)
            let footerText = "Generated with PlayerPath • playerpath.app"
            let footerRect = CGRect(x: margin, y: pageHeight - margin, width: contentWidth, height: 15)
            footerText.draw(in: footerRect, withAttributes: [
                .font: footerFont,
                .foregroundColor: UIColor.lightGray
            ])
        }

        return data
    }

    @discardableResult
    private static func drawSection(title: String, items: [(String, String)], yPosition: CGFloat, margin: CGFloat, contentWidth: CGFloat) -> CGFloat {
        var y = yPosition

        // Section title
        let titleFont = UIFont.boldSystemFont(ofSize: 16)
        let titleRect = CGRect(x: margin, y: y, width: contentWidth, height: 20)
        title.draw(in: titleRect, withAttributes: [
            .font: titleFont,
            .foregroundColor: UIColor.black
        ])
        y += 25

        // Items
        let itemFont = UIFont.systemFont(ofSize: 12)
        let labelWidth = contentWidth * 0.5
        let valueWidth = contentWidth * 0.5

        for (label, value) in items {
            let labelRect = CGRect(x: margin, y: y, width: labelWidth, height: 18)
            label.draw(in: labelRect, withAttributes: [
                .font: itemFont,
                .foregroundColor: UIColor.darkGray
            ])

            let valueRect = CGRect(x: margin + labelWidth, y: y, width: valueWidth, height: 18)
            value.draw(in: valueRect, withAttributes: [
                .font: UIFont.boldSystemFont(ofSize: 12),
                .foregroundColor: UIColor.black
            ])

            y += 20
        }

        y += 10
        return y
    }

    // MARK: - Helper Methods

    private static func saveToTemporaryFile(content: String, fileName: String) throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private static func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

// MARK: - Export Error

enum ExportError: LocalizedError {
    case noStatistics
    case fileCreationFailed(String)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noStatistics:
            return "No statistics available to export"
        case .fileCreationFailed(let reason):
            return "Failed to create export file: \(reason)"
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .noStatistics:
            return "Record some games first to generate statistics."
        case .fileCreationFailed:
            return "Try again or check your device storage."
        case .exportFailed:
            return "Try exporting again."
        }
    }
}
