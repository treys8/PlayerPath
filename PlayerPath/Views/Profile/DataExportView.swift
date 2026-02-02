//
//  DataExportView.swift
//  PlayerPath
//
//  GDPR-compliant data export functionality
//  Allows users to download all their data as JSON
//

import SwiftUI
import SwiftData

struct DataExportView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authManager: ComprehensiveAuthManager

    @State private var isExporting = false
    @State private var exportedData: String?
    @State private var showShareSheet = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.largeTitle)
                        .foregroundColor(.blue)

                    Text("Export Your Data")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Download a complete copy of all your PlayerPath data in JSON format. This includes athletes, seasons, games, statistics, and video metadata.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section("What's Included") {
                ExportDataRow(icon: "person.fill", title: "Athlete Profiles", description: "Names and profile information")
                ExportDataRow(icon: "calendar", title: "Seasons", description: "All season data and settings")
                ExportDataRow(icon: "sportscourt.fill", title: "Games", description: "Game details and results")
                ExportDataRow(icon: "chart.bar.fill", title: "Statistics", description: "All calculated statistics")
                ExportDataRow(icon: "video", title: "Video Metadata", description: "Video tags and timestamps (files not included)")
                ExportDataRow(icon: "figure.run", title: "Practice Sessions", description: "Practice logs and notes")
            }

            Section {
                Text("Video files are not included in the export due to their large size. To backup videos, save them to your Photos app individually.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Button {
                    Task {
                        await exportData()
                    }
                } label: {
                    HStack {
                        if isExporting {
                            ProgressView()
                                .padding(.trailing, 8)
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                        }
                        Text(isExporting ? "Generating Export..." : "Export My Data")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExporting)
            }
        }
        .navigationTitle("Export Data")
        .sheet(isPresented: $showShareSheet) {
            if let data = exportedData {
                ShareSheet(items: [createExportFile(data: data)])
            }
        }
        .alert("Export Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Export Logic

    private func exportData() async {
        isExporting = true
        defer { isExporting = false }

        do {
            // Track export request
            if let userID = authManager.userID {
                AnalyticsService.shared.trackDataExportRequested(userID: userID)
            }

            let exportDict = try await gatherAllData()
            let jsonData = try JSONSerialization.data(withJSONObject: exportDict, options: .prettyPrinted)
            exportedData = String(data: jsonData, encoding: .utf8)

            // Track export completion
            AnalyticsService.shared.trackDataExportCompleted(fileSize: jsonData.count)

            showShareSheet = true
        } catch {
            errorMessage = "Failed to export data: \(error.localizedDescription)"
            showError = true
        }
    }

    private func gatherAllData() async throws -> [String: Any] {
        // Fetch all data from SwiftData
        let descriptor = FetchDescriptor<User>()
        let users = try modelContext.fetch(descriptor)

        guard let currentUser = authManager.localUser ?? users.first else {
            throw ExportError.exportFailed("User not found")
        }

        var exportData: [String: Any] = [:]

        // User Info
        exportData["user"] = [
            "id": currentUser.id.uuidString,
            "email": authManager.userEmail ?? currentUser.email,
            "createdAt": ISO8601DateFormatter().string(from: currentUser.createdAt ?? Date())
        ]

        // Athletes
        let athletes = currentUser.athletes ?? []
        exportData["athletes"] = athletes.map { athlete in
            return [
                "id": athlete.id.uuidString,
                "name": athlete.name,
                "createdAt": ISO8601DateFormatter().string(from: athlete.createdAt ?? Date()),
                "firestoreId": athlete.firestoreId ?? ""
            ]
        }

        // Seasons
        var allSeasons: [[String: Any]] = []
        for athlete in athletes {
            let seasons = athlete.seasons ?? []
            allSeasons.append(contentsOf: seasons.map { season in
                return [
                    "id": season.id.uuidString,
                    "athleteId": athlete.id.uuidString,
                    "name": season.name,
                    "startDate": ISO8601DateFormatter().string(from: season.startDate ?? Date()),
                    "endDate": season.endDate.map { ISO8601DateFormatter().string(from: $0) } ?? "",
                    "isActive": season.isActive,
                    "sport": season.sport.rawValue,
                    "notes": season.notes
                ]
            })
        }
        exportData["seasons"] = allSeasons

        // Games
        var allGames: [[String: Any]] = []
        for athlete in athletes {
            let games = athlete.games ?? []
            allGames.append(contentsOf: games.map { game in
                return [
                    "id": game.id.uuidString,
                    "athleteId": athlete.id.uuidString,
                    "seasonId": game.season?.id.uuidString ?? "",
                    "opponent": game.opponent,
                    "date": ISO8601DateFormatter().string(from: game.date ?? Date()),
                    "isLive": game.isLive,
                    "isComplete": game.isComplete
                ]
            })
        }
        exportData["games"] = allGames

        // Statistics
        var allStats: [[String: Any]] = []
        for athlete in athletes {
            if let stats = athlete.statistics {
                allStats.append([
                    "athleteId": athlete.id.uuidString,
                    "type": "overall",
                    "totalGames": stats.totalGames,
                    "atBats": stats.atBats,
                    "hits": stats.hits,
                    "singles": stats.singles,
                    "doubles": stats.doubles,
                    "triples": stats.triples,
                    "homeRuns": stats.homeRuns,
                    "walks": stats.walks,
                    "strikeouts": stats.strikeouts,
                    "battingAverage": stats.battingAverage,
                    "onBasePercentage": stats.onBasePercentage,
                    "sluggingPercentage": stats.sluggingPercentage,
                    "ops": stats.onBasePercentage + stats.sluggingPercentage
                ])
            }
        }
        exportData["statistics"] = allStats

        // Practices
        var allPractices: [[String: Any]] = []
        for athlete in athletes {
            let practices = athlete.practices ?? []
            allPractices.append(contentsOf: practices.map { practice in
                var practiceDict: [String: Any] = [
                    "id": practice.id.uuidString,
                    "athleteId": athlete.id.uuidString,
                    "seasonId": practice.season?.id.uuidString ?? "",
                    "date": ISO8601DateFormatter().string(from: practice.date ?? Date())
                ]

                // Include practice notes
                let notes = practice.notes ?? []
                practiceDict["notes"] = notes.map { note in
                    return [
                        "id": note.id.uuidString,
                        "content": note.content,
                        "createdAt": ISO8601DateFormatter().string(from: note.createdAt ?? Date())
                    ]
                }

                return practiceDict
            })
        }
        exportData["practices"] = allPractices

        // Video Metadata (not actual files)
        let videoDescriptor = FetchDescriptor<VideoClip>()
        let allVideos = try modelContext.fetch(videoDescriptor)
        exportData["videos"] = allVideos.map { video in
            return [
                "id": video.id.uuidString,
                "createdAt": ISO8601DateFormatter().string(from: video.createdAt ?? Date()),
                "filePath": video.filePath,
                "thumbnailPath": video.thumbnailPath,
                "playResult": video.playResult?.type.displayName ?? ""
            ]
        }

        // Export Metadata
        exportData["exportMetadata"] = [
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "appVersion": "1.0.0",
            "format": "PlayerPath JSON v1"
        ]

        return exportData
    }

    private func createExportFile(data: String) -> URL {
        let fileName = "PlayerPath_Export_\(dateFormatter.string(from: Date())).json"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try data.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            print("❌ Failed to write export file: \(error)")
            return tempURL
        }
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        return formatter
    }
}

// MARK: - Supporting Views

struct ExportDataRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        DataExportView()
            .environmentObject(ComprehensiveAuthManager())
    }
}
