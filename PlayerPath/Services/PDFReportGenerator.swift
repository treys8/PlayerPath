//
//  PDFReportGenerator.swift
//  PlayerPath
//
//  Service for generating professional PDF reports of statistics and data
//

import UIKit
import PDFKit

@MainActor
final class PDFReportGenerator {
    static let shared = PDFReportGenerator()

    private init() {}

    // MARK: - Page Configuration

    private let pageWidth: CGFloat = 612  // 8.5 inches at 72 DPI
    private let pageHeight: CGFloat = 792  // 11 inches at 72 DPI
    private let margin: CGFloat = 50

    // MARK: - Athlete Statistics Report

    /// Generate comprehensive athlete statistics report
    /// - Parameter athlete: The athlete to generate report for
    /// - Returns: PDF document ready for sharing
    func generateAthleteReport(for athlete: Athlete) -> PDFDocument {
        let pdfMetaData = [
            kCGPDFContextTitle: "PlayerPath Statistics Report",
            kCGPDFContextAuthor: "PlayerPath",
            kCGPDFContextSubject: "\(athlete.name) Statistics"
        ]

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]

        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let data = renderer.pdfData { context in
            // Page 1: Overall Statistics
            context.beginPage()
            var yPosition: CGFloat = margin

            // Title
            yPosition = drawTitle("PlayerPath Statistics Report", at: yPosition, in: pageRect)
            yPosition += 10

            // Athlete Info Section
            yPosition = drawSectionHeader("Athlete Information", at: yPosition, in: pageRect)
            yPosition = drawText("Name: \(athlete.name)", at: yPosition, in: pageRect, fontSize: 12)
            if let createdAt = athlete.createdAt {
                yPosition = drawText("Profile Created: \(createdAt.formatted(date: .abbreviated, time: .omitted))", at: yPosition, in: pageRect, fontSize: 12)
            }
            yPosition = drawText("Generated: \(Date().formatted(date: .long, time: .standard))", at: yPosition, in: pageRect, fontSize: 12)
            yPosition += 20

            // Overall Statistics
            if let stats = athlete.statistics {
                yPosition = drawSectionHeader("Overall Career Statistics", at: yPosition, in: pageRect)
                yPosition = drawStatisticsTable(stats: stats, at: yPosition, in: pageRect)
                yPosition += 20
            }

            // Season-by-Season
            let seasons = athlete.seasons ?? []
            if !seasons.isEmpty {
                yPosition = drawSectionHeader("Season-by-Season Performance", at: yPosition, in: pageRect)

                for season in seasons.sorted(by: { ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast) }) {
                    // Check if we need a new page
                    if yPosition > pageHeight - 150 {
                        context.beginPage()
                        yPosition = margin
                    }

                    if let seasonStats = season.seasonStatistics {
                        yPosition = drawSeasonRow(season: season, stats: seasonStats, at: yPosition, in: pageRect)
                    }
                }
            }
        }

        return PDFDocument(data: data) ?? PDFDocument()
    }

    // MARK: - Game Log Report

    /// Generate game-by-game log report
    /// - Parameters:
    ///   - athlete: The athlete whose games to export
    ///   - season: Optional season filter (nil = all games)
    /// - Returns: PDF document ready for sharing
    func generateGameLogReport(for athlete: Athlete, season: Season? = nil) -> PDFDocument {
        let pdfMetaData = [
            kCGPDFContextTitle: "PlayerPath Game Log",
            kCGPDFContextAuthor: "PlayerPath",
            kCGPDFContextSubject: "\(athlete.name) Game Log"
        ]

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]

        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let data = renderer.pdfData { context in
            context.beginPage()
            var yPosition: CGFloat = margin

            // Title
            yPosition = drawTitle("Game Log", at: yPosition, in: pageRect)
            yPosition = drawText("Athlete: \(athlete.name)", at: yPosition, in: pageRect, fontSize: 14, bold: true)
            if let season = season {
                yPosition = drawText("Season: \(season.displayName)", at: yPosition, in: pageRect, fontSize: 14, bold: true)
            }
            yPosition += 20

            // Get games
            var games = athlete.games ?? []
            if let season = season {
                games = games.filter { $0.season?.id == season.id }
            }
            games.sort { ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast) }

            // Table header
            yPosition = drawGameLogHeader(at: yPosition, in: pageRect)

            // Games
            for game in games {
                guard game.isComplete, let gameStats = game.gameStats else { continue }

                // Check if we need a new page
                if yPosition > pageHeight - 60 {
                    context.beginPage()
                    yPosition = margin
                    yPosition = drawGameLogHeader(at: yPosition, in: pageRect)
                }

                yPosition = drawGameLogRow(game: game, stats: gameStats, at: yPosition, in: pageRect)
            }
        }

        return PDFDocument(data: data) ?? PDFDocument()
    }

    // MARK: - Season Summary Report

    /// Generate comprehensive season summary report
    /// - Parameter season: The season to export
    /// - Returns: PDF document ready for sharing
    func generateSeasonSummaryReport(for season: Season) -> PDFDocument {
        let pdfMetaData = [
            kCGPDFContextTitle: "PlayerPath Season Summary",
            kCGPDFContextAuthor: "PlayerPath",
            kCGPDFContextSubject: "\(season.displayName) Summary"
        ]

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]

        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let data = renderer.pdfData { context in
            context.beginPage()
            var yPosition: CGFloat = margin

            // Title
            yPosition = drawTitle("Season Summary", at: yPosition, in: pageRect)
            yPosition += 10

            // Season Info
            yPosition = drawSectionHeader("Season Information", at: yPosition, in: pageRect)
            yPosition = drawText("Season: \(season.displayName)", at: yPosition, in: pageRect, fontSize: 12)
            if let startDate = season.startDate {
                yPosition = drawText("Start Date: \(startDate.formatted(date: .abbreviated, time: .omitted))", at: yPosition, in: pageRect, fontSize: 12)
            }
            if let endDate = season.endDate {
                yPosition = drawText("End Date: \(endDate.formatted(date: .abbreviated, time: .omitted))", at: yPosition, in: pageRect, fontSize: 12)
            }
            yPosition = drawText("Status: \(season.isActive ? "Active" : "Completed")", at: yPosition, in: pageRect, fontSize: 12)
            yPosition = drawText("Sport: \(season.sport.displayName)", at: yPosition, in: pageRect, fontSize: 12)
            yPosition += 20

            // Season Statistics
            if let stats = season.seasonStatistics {
                yPosition = drawSectionHeader("Season Statistics", at: yPosition, in: pageRect)
                yPosition = drawStatisticsTable(stats: stats, at: yPosition, in: pageRect)
                yPosition += 20
            }

            // Games List
            let games = season.games ?? []
            if !games.isEmpty {
                yPosition = drawSectionHeader("Games in Season", at: yPosition, in: pageRect)

                // Table header
                yPosition = drawSeasonGamesHeader(at: yPosition, in: pageRect)

                for game in games.sorted(by: { ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast) }) {
                    // Check if we need a new page
                    if yPosition > pageHeight - 60 {
                        context.beginPage()
                        yPosition = margin
                        yPosition = drawSeasonGamesHeader(at: yPosition, in: pageRect)
                    }

                    yPosition = drawSeasonGameRow(game: game, at: yPosition, in: pageRect)
                }
            }
        }

        return PDFDocument(data: data) ?? PDFDocument()
    }

    // MARK: - Drawing Helpers

    private func drawTitle(_ text: String, at yPosition: CGFloat, in pageRect: CGRect) -> CGFloat {
        let font = UIFont.boldSystemFont(ofSize: 20)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textRect = CGRect(x: margin, y: yPosition, width: pageRect.width - (margin * 2), height: 30)
        attributedString.draw(in: textRect)

        return yPosition + 35
    }

    private func drawSectionHeader(_ text: String, at yPosition: CGFloat, in pageRect: CGRect) -> CGFloat {
        let font = UIFont.boldSystemFont(ofSize: 16)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textRect = CGRect(x: margin, y: yPosition, width: pageRect.width - (margin * 2), height: 20)
        attributedString.draw(in: textRect)

        // Draw underline
        let underlinePath = UIBezierPath()
        underlinePath.move(to: CGPoint(x: margin, y: yPosition + 22))
        underlinePath.addLine(to: CGPoint(x: pageRect.width - margin, y: yPosition + 22))
        UIColor.gray.setStroke()
        underlinePath.lineWidth = 1.0
        underlinePath.stroke()

        return yPosition + 30
    }

    private func drawText(_ text: String, at yPosition: CGFloat, in pageRect: CGRect, fontSize: CGFloat = 12, bold: Bool = false) -> CGFloat {
        let font = bold ? UIFont.boldSystemFont(ofSize: fontSize) : UIFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textRect = CGRect(x: margin, y: yPosition, width: pageRect.width - (margin * 2), height: 20)
        attributedString.draw(in: textRect)

        return yPosition + 18
    }

    private func drawStatisticsTable(stats: AthleteStatistics, at yPosition: CGFloat, in pageRect: CGRect) -> CGFloat {
        var currentY = yPosition
        let columnWidth = (pageRect.width - (margin * 2)) / 2

        // Left column
        currentY = drawText("Total Games: \(stats.totalGames)", at: currentY, in: pageRect)
        currentY = drawText("At Bats: \(stats.atBats)", at: currentY, in: pageRect)
        currentY = drawText("Hits: \(stats.hits)", at: currentY, in: pageRect)
        currentY = drawText("Singles: \(stats.singles)", at: currentY, in: pageRect)
        currentY = drawText("Doubles: \(stats.doubles)", at: currentY, in: pageRect)
        currentY = drawText("Triples: \(stats.triples)", at: currentY, in: pageRect)
        currentY = drawText("Home Runs: \(stats.homeRuns)", at: currentY, in: pageRect)

        // Reset for right column
        var rightY = yPosition
        let rightX = margin + columnWidth

        // Right column stats
        rightY = drawTextAt("Runs: \(stats.runs)", x: rightX, y: rightY, width: columnWidth)
        rightY = drawTextAt("RBIs: \(stats.rbis)", x: rightX, y: rightY, width: columnWidth)
        rightY = drawTextAt("Walks: \(stats.walks)", x: rightX, y: rightY, width: columnWidth)
        rightY = drawTextAt("Strikeouts: \(stats.strikeouts)", x: rightX, y: rightY, width: columnWidth)
        rightY = drawTextAt("AVG: \(StatisticsService.shared.formatBattingAverage(stats.battingAverage))", x: rightX, y: rightY, width: columnWidth, bold: true)
        rightY = drawTextAt("OBP: \(StatisticsService.shared.formatPercentage(stats.onBasePercentage))", x: rightX, y: rightY, width: columnWidth, bold: true)
        rightY = drawTextAt("SLG: \(StatisticsService.shared.formatPercentage(stats.sluggingPercentage))", x: rightX, y: rightY, width: columnWidth, bold: true)
        rightY = drawTextAt("OPS: \(StatisticsService.shared.formatOPS(stats.ops))", x: rightX, y: rightY, width: columnWidth, bold: true)

        return max(currentY, rightY)
    }

    private func drawTextAt(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, bold: Bool = false) -> CGFloat {
        let font = bold ? UIFont.boldSystemFont(ofSize: 12) : UIFont.systemFont(ofSize: 12)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textRect = CGRect(x: x, y: y, width: width, height: 20)
        attributedString.draw(in: textRect)

        return y + 18
    }

    private func drawSeasonRow(season: Season, stats: AthleteStatistics, at yPosition: CGFloat, in pageRect: CGRect) -> CGFloat {
        var currentY = yPosition

        currentY = drawText("▸ \(season.displayName)", at: currentY, in: pageRect, fontSize: 14, bold: true)
        currentY = drawText("  Games: \(stats.totalGames) | AB: \(stats.atBats) | H: \(stats.hits) | AVG: \(StatisticsService.shared.formatBattingAverage(stats.battingAverage))", at: currentY, in: pageRect, fontSize: 11)
        currentY = drawText("  HR: \(stats.homeRuns) | R: \(stats.runs) | RBI: \(stats.rbis) | OPS: \(StatisticsService.shared.formatOPS(stats.ops))", at: currentY, in: pageRect, fontSize: 11)
        currentY += 5

        return currentY
    }

    private func drawGameLogHeader(at yPosition: CGFloat, in pageRect: CGRect) -> CGFloat {
        let headerFont = UIFont.boldSystemFont(ofSize: 10)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: headerFont,
            .foregroundColor: UIColor.black
        ]

        let headers = ["Date", "Opponent", "AB", "H", "2B", "3B", "HR", "R", "RBI", "BB", "K", "AVG"]
        let columnWidth = (pageRect.width - (margin * 2)) / CGFloat(headers.count)

        for (index, header) in headers.enumerated() {
            let x = margin + (CGFloat(index) * columnWidth)
            let textRect = CGRect(x: x, y: yPosition, width: columnWidth, height: 15)
            let attributedString = NSAttributedString(string: header, attributes: attributes)
            attributedString.draw(in: textRect)
        }

        // Draw line under header
        let linePath = UIBezierPath()
        linePath.move(to: CGPoint(x: margin, y: yPosition + 17))
        linePath.addLine(to: CGPoint(x: pageRect.width - margin, y: yPosition + 17))
        UIColor.gray.setStroke()
        linePath.lineWidth = 0.5
        linePath.stroke()

        return yPosition + 22
    }

    private func drawGameLogRow(game: Game, stats: GameStatistics, at yPosition: CGFloat, in pageRect: CGRect) -> CGFloat {
        let rowFont = UIFont.systemFont(ofSize: 9)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: rowFont,
            .foregroundColor: UIColor.black
        ]

        let dateStr = game.date?.formatted(date: .numeric, time: .omitted) ?? "Unknown"
        let opponent = String(game.opponent.prefix(10))  // Truncate long names

        let values = [
            dateStr,
            opponent,
            "\(stats.atBats)",
            "\(stats.hits)",
            "\(stats.doubles)",
            "\(stats.triples)",
            "\(stats.homeRuns)",
            "\(stats.runs)",
            "\(stats.rbis)",
            "\(stats.walks)",
            "\(stats.strikeouts)",
            StatisticsService.shared.formatBattingAverage(stats.battingAverage)
        ]

        let columnWidth = (pageRect.width - (margin * 2)) / CGFloat(values.count)

        for (index, value) in values.enumerated() {
            let x = margin + (CGFloat(index) * columnWidth)
            let textRect = CGRect(x: x, y: yPosition, width: columnWidth, height: 15)
            let attributedString = NSAttributedString(string: value, attributes: attributes)
            attributedString.draw(in: textRect)
        }

        return yPosition + 18
    }

    private func drawSeasonGamesHeader(at yPosition: CGFloat, in pageRect: CGRect) -> CGFloat {
        let headerFont = UIFont.boldSystemFont(ofSize: 10)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: headerFont,
            .foregroundColor: UIColor.black
        ]

        let headers = ["Date", "Opponent", "Status", "AB", "H", "AVG"]
        let columnWidths: [CGFloat] = [80, 150, 80, 50, 50, 60]
        var x = margin

        for (index, header) in headers.enumerated() {
            let textRect = CGRect(x: x, y: yPosition, width: columnWidths[index], height: 15)
            let attributedString = NSAttributedString(string: header, attributes: attributes)
            attributedString.draw(in: textRect)
            x += columnWidths[index]
        }

        // Draw line under header
        let linePath = UIBezierPath()
        linePath.move(to: CGPoint(x: margin, y: yPosition + 17))
        linePath.addLine(to: CGPoint(x: pageRect.width - margin, y: yPosition + 17))
        UIColor.gray.setStroke()
        linePath.lineWidth = 0.5
        linePath.stroke()

        return yPosition + 22
    }

    private func drawSeasonGameRow(game: Game, at yPosition: CGFloat, in pageRect: CGRect) -> CGFloat {
        let rowFont = UIFont.systemFont(ofSize: 9)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: rowFont,
            .foregroundColor: UIColor.black
        ]

        let dateStr = game.date?.formatted(date: .numeric, time: .omitted) ?? "Unknown"
        let opponent = String(game.opponent.prefix(20))
        let status = game.isComplete ? "Complete" : (game.isLive ? "Live" : "Scheduled")

        var values = [dateStr, opponent, status]

        if let gameStats = game.gameStats {
            values.append("\(gameStats.atBats)")
            values.append("\(gameStats.hits)")
            values.append(StatisticsService.shared.formatBattingAverage(gameStats.battingAverage))
        } else {
            values.append(contentsOf: ["-", "-", "-"])
        }

        let columnWidths: [CGFloat] = [80, 150, 80, 50, 50, 60]
        var x = margin

        for (index, value) in values.enumerated() {
            let textRect = CGRect(x: x, y: yPosition, width: columnWidths[index], height: 15)
            let attributedString = NSAttributedString(string: value, attributes: attributes)
            attributedString.draw(in: textRect)
            x += columnWidths[index]
        }

        return yPosition + 18
    }

    // MARK: - File Saving

    /// Save PDF to temporary file and return URL
    func savePDFToTemporaryFile(_ pdf: PDFDocument, filename: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(filename)

        pdf.write(to: fileURL)

        return fileURL
    }
}
