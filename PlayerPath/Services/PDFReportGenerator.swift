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
        if athlete.sport == .golf {
            return generateGolfReport(for: athlete)
        }
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
        let isGolf = season.map { $0.sport == .golf } ?? (athlete.sport == .golf)
        if isGolf {
            return generateGolfRoundLogReport(for: athlete, season: season)
        }
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
        if season.sport == .golf {
            return generateGolfSeasonSummaryReport(for: season)
        }
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
            yPosition = drawText("Sport: \((season.sport ?? .baseball).displayName)", at: yPosition, in: pageRect, fontSize: 12)
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

    private func drawHeading(_ text: String, fontSize: CGFloat, height: CGFloat, underline: Bool = false, underlineWidth: CGFloat = 1.0, spacing: CGFloat, at yPosition: CGFloat, in pageRect: CGRect) -> CGFloat {
        let font = UIFont.boldSystemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black
        ]
        let textRect = CGRect(x: margin, y: yPosition, width: pageRect.width - (margin * 2), height: height)
        NSAttributedString(string: text, attributes: attributes).draw(in: textRect)

        if underline {
            let linePath = UIBezierPath()
            linePath.move(to: CGPoint(x: margin, y: yPosition + height + 2))
            linePath.addLine(to: CGPoint(x: pageRect.width - margin, y: yPosition + height + 2))
            UIColor.gray.setStroke()
            linePath.lineWidth = underlineWidth
            linePath.stroke()
        }

        return yPosition + spacing
    }

    private func drawTitle(_ text: String, at yPosition: CGFloat, in pageRect: CGRect) -> CGFloat {
        drawHeading(text, fontSize: 20, height: 30, spacing: 35, at: yPosition, in: pageRect)
    }

    private func drawSectionHeader(_ text: String, at yPosition: CGFloat, in pageRect: CGRect) -> CGFloat {
        drawHeading(text, fontSize: 16, height: 20, underline: true, spacing: 30, at: yPosition, in: pageRect)
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

    private func drawTableHeader(headers: [String], columnWidths: [CGFloat]? = nil, at yPosition: CGFloat, in pageRect: CGRect) -> CGFloat {
        let headerFont = UIFont.boldSystemFont(ofSize: 10)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: headerFont,
            .foregroundColor: UIColor.black
        ]

        let equalWidth = (pageRect.width - (margin * 2)) / CGFloat(headers.count)
        var x = margin
        for (index, header) in headers.enumerated() {
            let width = columnWidths?[index] ?? equalWidth
            let textRect = CGRect(x: x, y: yPosition, width: width, height: 15)
            NSAttributedString(string: header, attributes: attributes).draw(in: textRect)
            x += width
        }

        let linePath = UIBezierPath()
        linePath.move(to: CGPoint(x: margin, y: yPosition + 17))
        linePath.addLine(to: CGPoint(x: pageRect.width - margin, y: yPosition + 17))
        UIColor.gray.setStroke()
        linePath.lineWidth = 0.5
        linePath.stroke()

        return yPosition + 22
    }

    private func drawGameLogHeader(at yPosition: CGFloat, in pageRect: CGRect) -> CGFloat {
        drawTableHeader(
            headers: ["Date", "Opponent", "AB", "H", "2B", "3B", "HR", "R", "RBI", "BB", "K", "AVG"],
            at: yPosition, in: pageRect
        )
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
        drawTableHeader(
            headers: ["Date", "Opponent", "Status", "AB", "H", "AVG"],
            columnWidths: [80, 150, 80, 50, 50, 60],
            at: yPosition, in: pageRect
        )
    }

    private func drawSeasonGameRow(game: Game, at yPosition: CGFloat, in pageRect: CGRect) -> CGFloat {
        let rowFont = UIFont.systemFont(ofSize: 9)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: rowFont,
            .foregroundColor: UIColor.black
        ]

        let dateStr = game.date?.formatted(date: .numeric, time: .omitted) ?? "Unknown"
        let opponent = String(game.opponent.prefix(20))
        let status: String = {
            switch game.displayStatus {
            case .live: return "Live"
            case .completed: return "Complete"
            case .scheduled: return "Scheduled"
            }
        }()

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

    // MARK: - Golf Reports

    func generateGolfReport(for athlete: Athlete) -> PDFDocument {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle: "PlayerPath Golf Scoring Report",
            kCGPDFContextAuthor: "PlayerPath",
            kCGPDFContextSubject: "\(athlete.name) Golf Scoring"
        ] as [String: Any]

        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let data = renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = margin
            y = drawTitle("Golf Scoring Report", at: y, in: pageRect)
            y += 10
            y = drawSectionHeader("Athlete Information", at: y, in: pageRect)
            y = drawText("Name: \(athlete.name)", at: y, in: pageRect, fontSize: 12)
            y = drawText("Generated: \(Date().formatted(date: .long, time: .standard))", at: y, in: pageRect, fontSize: 12)
            y += 20

            y = drawGolfSummary(GolfExportData.summary(for: athlete, season: nil), at: y, in: pageRect)

            let tournaments = GolfExportData.tournamentRounds(for: athlete, season: nil)
            if !tournaments.isEmpty {
                y = drawSectionHeader("Tournament Rounds", at: y, in: pageRect)
                y = drawGolfRoundsTable(tournaments, at: y, in: pageRect, context: context)
            }
            let practices = GolfExportData.practiceRounds(for: athlete, season: nil)
            if !practices.isEmpty {
                if y > pageHeight - 120 { context.beginPage(); y = margin }
                y = drawSectionHeader("Practice Rounds", at: y, in: pageRect)
                y = drawGolfRoundsTable(practices, at: y, in: pageRect, context: context)
            }
        }
        return PDFDocument(data: data) ?? PDFDocument()
    }

    func generateGolfRoundLogReport(for athlete: Athlete, season: Season?) -> PDFDocument {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle: "PlayerPath Golf Round Log",
            kCGPDFContextAuthor: "PlayerPath",
            kCGPDFContextSubject: "\(athlete.name) Golf Round Log"
        ] as [String: Any]
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        let data = renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = margin
            y = drawTitle("Golf Round Log", at: y, in: pageRect)
            y = drawText("Athlete: \(athlete.name)", at: y, in: pageRect, fontSize: 14, bold: true)
            if let season { y = drawText("Season: \(season.displayName)", at: y, in: pageRect, fontSize: 14, bold: true) }
            y += 20
            y = drawGolfRoundsTable(GolfExportData.tournamentRounds(for: athlete, season: season), at: y, in: pageRect, context: context)
        }
        return PDFDocument(data: data) ?? PDFDocument()
    }

    func generateGolfSeasonSummaryReport(for season: Season) -> PDFDocument {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle: "PlayerPath Golf Season Summary",
            kCGPDFContextAuthor: "PlayerPath",
            kCGPDFContextSubject: "\(season.displayName) Golf Summary"
        ] as [String: Any]
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        let data = renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = margin
            y = drawTitle("Golf Season Summary", at: y, in: pageRect)
            y += 10
            y = drawSectionHeader("Season Information", at: y, in: pageRect)
            y = drawText("Season: \(season.displayName)", at: y, in: pageRect, fontSize: 12)
            y = drawText("Status: \(season.isActive ? "Active" : "Completed")", at: y, in: pageRect, fontSize: 12)
            y += 20
            if let athlete = season.athlete {
                y = drawGolfSummary(GolfExportData.summary(for: athlete, season: season), at: y, in: pageRect)
                let tournaments = GolfExportData.tournamentRounds(for: athlete, season: season)
                if !tournaments.isEmpty {
                    y = drawSectionHeader("Tournament Rounds", at: y, in: pageRect)
                    y = drawGolfRoundsTable(tournaments, at: y, in: pageRect, context: context)
                }
            }
        }
        return PDFDocument(data: data) ?? PDFDocument()
    }

    private func drawGolfSummary(_ s: GolfExportSummary, at yPosition: CGFloat, in pageRect: CGRect) -> CGFloat {
        var y = drawSectionHeader("Scoring Summary", at: yPosition, in: pageRect)
        y = drawText("Total Rounds: \(s.totalRounds)", at: y, in: pageRect)
        y = drawText("Best: \(s.bestScore.map { "\($0)" } ?? "—")  |  Worst: \(s.worstScore.map { "\($0)" } ?? "—")", at: y, in: pageRect)
        y = drawText("Tournament Avg: \(s.tournamentAverage.map { String(format: "%.1f", $0) } ?? "—")  |  Practice Avg: \(s.practiceAverage.map { String(format: "%.1f", $0) } ?? "—")", at: y, in: pageRect)
        return y + 20
    }

    private func drawGolfRoundsHeader(at y: CGFloat, in pageRect: CGRect) -> CGFloat {
        drawTableHeader(
            headers: ["Date", "Course", "Holes", "Par", "Score", "+/-", "Putts"],
            columnWidths: [70, 140, 45, 45, 55, 45, 50],
            at: y, in: pageRect
        )
    }

    private func drawGolfRoundsTable(_ rounds: [GolfRoundRow], at yPosition: CGFloat, in pageRect: CGRect, context: UIGraphicsPDFRendererContext) -> CGFloat {
        var y = drawGolfRoundsHeader(at: yPosition, in: pageRect)
        let widths: [CGFloat] = [70, 140, 45, 45, 55, 45, 50]
        let font = UIFont.systemFont(ofSize: 9)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        for r in rounds {
            if y > pageHeight - 60 {
                context.beginPage()
                y = margin
                y = drawGolfRoundsHeader(at: y, in: pageRect)
            }
            let dateStr: String = r.date?.formatted(date: .numeric, time: .omitted) ?? "Unknown"
            let courseStr: String = String(r.course.prefix(20))
            let holesStr: String = "\(r.holes)"
            let parStr: String = r.par.map { "\($0)" } ?? "-"
            let scoreStr: String = r.score.map { "\($0)" } ?? "-"
            let puttsStr: String = r.putts.map { "\($0)" } ?? "-"
            let values: [String] = [dateStr, courseStr, holesStr, parStr, scoreStr, r.toParString, puttsStr]
            var x = margin
            for (i, v) in values.enumerated() {
                NSAttributedString(string: v, attributes: attrs)
                    .draw(in: CGRect(x: x, y: y, width: widths[i], height: 15))
                x += widths[i]
            }
            y += 18
        }
        return y + 10
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
