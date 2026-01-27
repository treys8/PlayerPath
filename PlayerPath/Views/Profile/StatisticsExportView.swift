//
//  StatisticsExportView.swift
//  PlayerPath
//
//  Export statistics and reports in CSV/PDF format for sharing with coaches
//

import SwiftUI
import SwiftData
import PDFKit

struct StatisticsExportView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Athlete.name) private var athletes: [Athlete]

    @State private var selectedAthlete: Athlete?
    @State private var selectedReportType: ReportType = .athleteStatistics
    @State private var selectedFormat: ExportFormat = .csv
    @State private var selectedSeason: Season?
    @State private var isExporting = false
    @State private var showShareSheet = false
    @State private var exportURL: URL?
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        Form {
            // Athlete Selection
            Section("Select Athlete") {
                if athletes.isEmpty {
                    Text("No athletes found. Create an athlete first.")
                        .foregroundColor(.secondary)
                } else {
                    Picker("Athlete", selection: $selectedAthlete) {
                        Text("Select Athlete").tag(nil as Athlete?)
                        ForEach(athletes) { athlete in
                            Text(athlete.name).tag(athlete as Athlete?)
                        }
                    }
                }
            }

            if selectedAthlete != nil {
                // Report Type Selection
                Section("Report Type") {
                    Picker("Report", selection: $selectedReportType) {
                        ForEach(ReportType.allCases) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.inline)

                    Text(selectedReportType.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Season Filter (for applicable reports)
                if selectedReportType.needsSeasonFilter, let athlete = selectedAthlete {
                    let seasons = athlete.seasons ?? []
                    if !seasons.isEmpty {
                        Section("Season Filter (Optional)") {
                            Picker("Season", selection: $selectedSeason) {
                                Text("All Seasons").tag(nil as Season?)
                                ForEach(seasons.sorted(by: { ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast) })) { season in
                                    Text(season.displayName).tag(season as Season?)
                                }
                            }
                        }
                    }
                }

                // Format Selection
                Section("Export Format") {
                    Picker("Format", selection: $selectedFormat) {
                        ForEach(ExportFormat.allCases) { format in
                            Label(format.displayName, systemImage: format.icon)
                                .tag(format)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Image(systemName: selectedFormat.icon)
                            .foregroundColor(.blue)
                        Text(selectedFormat.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Export Preview
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Export Preview", systemImage: "doc.text.magnifyingglass")
                            .font(.headline)

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Athlete:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(selectedAthlete?.name ?? "")
                                    .font(.body)
                                    .fontWeight(.medium)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Report:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(selectedReportType.shortName)
                                    .font(.body)
                                    .fontWeight(.medium)
                            }
                        }

                        if let season = selectedSeason {
                            Divider()
                            HStack {
                                Text("Season:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(season.displayName)
                                    .font(.body)
                            }
                        }

                        Divider()

                        HStack {
                            Text("Format:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(selectedFormat.rawValue.uppercased())
                                .font(.body)
                                .fontWeight(.bold)
                                .foregroundColor(selectedFormat == .pdf ? .red : .green)
                        }
                    }
                    .padding(.vertical, 8)
                }

                // Export Button
                Section {
                    Button {
                        Task {
                            await generateExport()
                        }
                    } label: {
                        HStack {
                            if isExporting {
                                ProgressView()
                                    .padding(.trailing, 8)
                            } else {
                                Image(systemName: "square.and.arrow.up.fill")
                            }
                            Text(isExporting ? "Generating..." : "Generate & Share")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isExporting)
                }
            } else {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "chart.bar.doc.horizontal")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)

                        Text("Select an athlete to generate reports")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text("Export statistics to CSV or PDF format for sharing with coaches, scouts, or for your records.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
            }
        }
        .navigationTitle("Export Statistics")
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
        .alert("Export Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Export Logic

    private func generateExport() async {
        guard let athlete = selectedAthlete else { return }

        isExporting = true
        defer { isExporting = false }

        do {
            let url: URL

            switch selectedFormat {
            case .csv:
                let csvString = generateCSV(for: athlete)
                url = try CSVExportService.shared.saveCSVToTemporaryFile(
                    csvString,
                    filename: generateFilename(format: "csv")
                )

            case .pdf:
                let pdfDocument = generatePDF(for: athlete)
                url = try PDFReportGenerator.shared.savePDFToTemporaryFile(
                    pdfDocument,
                    filename: generateFilename(format: "pdf")
                )
            }

            exportURL = url
            showShareSheet = true

        } catch {
            errorMessage = "Failed to generate export: \(error.localizedDescription)"
            showError = true
        }
    }

    private func generateCSV(for athlete: Athlete) -> String {
        switch selectedReportType {
        case .athleteStatistics:
            return CSVExportService.shared.exportAthleteStatistics(for: athlete)

        case .gameLog:
            return CSVExportService.shared.exportGameLog(for: athlete, season: selectedSeason)

        case .playByPlay:
            return CSVExportService.shared.exportPlayByPlay(for: athlete, season: selectedSeason)

        case .seasonSummary:
            if let season = selectedSeason {
                return CSVExportService.shared.exportSeasonSummary(for: season)
            } else if let latestSeason = (athlete.seasons ?? []).sorted(by: { ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast) }).first {
                return CSVExportService.shared.exportSeasonSummary(for: latestSeason)
            } else {
                return "No season data available"
            }
        }
    }

    private func generatePDF(for athlete: Athlete) -> PDFDocument {
        switch selectedReportType {
        case .athleteStatistics:
            return PDFReportGenerator.shared.generateAthleteReport(for: athlete)

        case .gameLog:
            return PDFReportGenerator.shared.generateGameLogReport(for: athlete, season: selectedSeason)

        case .seasonSummary:
            if let season = selectedSeason {
                return PDFReportGenerator.shared.generateSeasonSummaryReport(for: season)
            } else if let latestSeason = (athlete.seasons ?? []).sorted(by: { ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast) }).first {
                return PDFReportGenerator.shared.generateSeasonSummaryReport(for: latestSeason)
            } else {
                return PDFDocument()
            }

        case .playByPlay:
            // PDF not supported for play-by-play (would be too long)
            // Fall back to athlete report
            return PDFReportGenerator.shared.generateAthleteReport(for: athlete)
        }
    }

    private func generateFilename(format: String) -> String {
        let athleteName = selectedAthlete?.name.replacingOccurrences(of: " ", with: "_") ?? "Athlete"
        let reportName = selectedReportType.shortName.replacingOccurrences(of: " ", with: "_")
        let dateString = Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")

        if let season = selectedSeason {
            let seasonName = season.displayName.replacingOccurrences(of: " ", with: "_")
            return "\(athleteName)_\(reportName)_\(seasonName)_\(dateString).\(format)"
        } else {
            return "\(athleteName)_\(reportName)_\(dateString).\(format)"
        }
    }
}

// MARK: - Supporting Types

enum ReportType: String, CaseIterable, Identifiable {
    case athleteStatistics = "athlete_stats"
    case gameLog = "game_log"
    case seasonSummary = "season_summary"
    case playByPlay = "play_by_play"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .athleteStatistics: return "Athlete Statistics Report"
        case .gameLog: return "Game-by-Game Log"
        case .seasonSummary: return "Season Summary"
        case .playByPlay: return "Play-by-Play Report"
        }
    }

    var shortName: String {
        switch self {
        case .athleteStatistics: return "Stats Report"
        case .gameLog: return "Game Log"
        case .seasonSummary: return "Season Summary"
        case .playByPlay: return "Play by Play"
        }
    }

    var icon: String {
        switch self {
        case .athleteStatistics: return "chart.bar.fill"
        case .gameLog: return "sportscourt.fill"
        case .seasonSummary: return "calendar.badge.checkmark"
        case .playByPlay: return "list.bullet.clipboard"
        }
    }

    var description: String {
        switch self {
        case .athleteStatistics:
            return "Complete career statistics with season-by-season breakdown"
        case .gameLog:
            return "Detailed game-by-game performance statistics"
        case .seasonSummary:
            return "Comprehensive season report with all games and statistics"
        case .playByPlay:
            return "Video clip results and play-by-play data"
        }
    }

    var needsSeasonFilter: Bool {
        switch self {
        case .gameLog, .playByPlay:
            return true
        case .athleteStatistics, .seasonSummary:
            return false
        }
    }
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case csv = "csv"
    case pdf = "pdf"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .csv: return "CSV"
        case .pdf: return "PDF"
        }
    }

    var icon: String {
        switch self {
        case .csv: return "tablecells"
        case .pdf: return "doc.fill"
        }
    }

    var description: String {
        switch self {
        case .csv:
            return "Spreadsheet format - open in Excel, Google Sheets, or Numbers"
        case .pdf:
            return "Professional report format - ready to print or email"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        StatisticsExportView()
    }
    .modelContainer(for: [User.self, Athlete.self, Season.self, Game.self], inMemory: true)
}
