//
//  UploadStatisticsView.swift
//  PlayerPath
//
//  Upload statistics dashboard showing storage usage, upload activity, and recent history
//

import SwiftUI
import SwiftData

struct UploadStatisticsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var uploadManager = UploadQueueManager.shared
    @State private var networkMonitor = ConnectivityMonitor.shared

    @Query private var allVideos: [VideoClip]
    @Query private var preferences: [UserPreferences]

    var body: some View {
        NavigationStack {
            List {
                storageSection
                activitySection
                networkSection
                recentHistorySection
            }
            .navigationTitle("Upload Statistics")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Storage Section

    private var storageSection: some View {
        Section {
            VStack(spacing: 16) {
                // Total Storage Circle
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 12)
                        .frame(width: 120, height: 120)

                    Circle()
                        .trim(from: 0, to: uploadPercentage)
                        .stroke(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.6), value: uploadPercentage)

                    VStack(spacing: 4) {
                        Text("\(uploadedCount)")
                            .font(.system(size: 32, weight: .bold))
                        Text("uploaded")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)

                // Storage Stats
                HStack(spacing: 32) {
                    StatColumn(
                        title: "Total Size",
                        value: formatBytes(totalUploadedSize),
                        icon: "externaldrive.fill",
                        color: .blue
                    )

                    StatColumn(
                        title: "Avg Size",
                        value: formatBytes(averageVideoSize),
                        icon: "chart.bar.fill",
                        color: .green
                    )

                    StatColumn(
                        title: "Success Rate",
                        value: "\(successRate)%",
                        icon: "checkmark.circle.fill",
                        color: successRate >= 95 ? .green : .orange
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        } header: {
            Text("Storage Overview")
        }
    }

    // MARK: - Activity Section

    private var activitySection: some View {
        Section {
            ActivityRow(
                label: "Uploaded",
                count: uploadedCount,
                icon: "checkmark.icloud.fill",
                color: .green
            )

            if uploadManager.activeUploads.count > 0 {
                ActivityRow(
                    label: "Uploading",
                    count: uploadManager.activeUploads.count,
                    icon: "arrow.up.circle.fill",
                    color: .blue,
                    isAnimated: true
                )
            }

            if uploadManager.pendingUploads.count > 0 {
                ActivityRow(
                    label: "Queued",
                    count: uploadManager.pendingUploads.count,
                    icon: "clock.fill",
                    color: .orange
                )
            }

            if uploadManager.failedUploads.count > 0 {
                HStack {
                    ActivityRow(
                        label: "Failed",
                        count: uploadManager.failedUploads.count,
                        icon: "exclamationmark.triangle.fill",
                        color: .red
                    )

                    Spacer()

                    Button("Retry All") {
                        retryAllFailed()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }

            ActivityRow(
                label: "Local Only",
                count: localOnlyCount,
                icon: "iphone",
                color: .gray
            )
        } header: {
            Text("Upload Activity")
        }
    }

    // MARK: - Network Section

    private var networkSection: some View {
        Section {
            HStack {
                Image(systemName: networkMonitor.connectionType.icon)
                    .foregroundColor(networkIconColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Connection")
                        .font(.subheadline)
                    Text(networkMonitor.networkStatusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if networkMonitor.isConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }

            if let prefs = preferences.first {
                HStack {
                    Image(systemName: prefs.allowCellularUploads ? "antenna.radiowaves.left.and.right" : "wifi")
                        .foregroundColor(prefs.allowCellularUploads ? .orange : .blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Upload Policy")
                            .font(.subheadline)
                        Text(prefs.allowCellularUploads ? "WiFi & Cellular" : "WiFi Only")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if prefs.allowCellularUploads {
                        Text("⚠️")
                            .font(.title3)
                    }
                }
            }
        } header: {
            Text("Network")
        } footer: {
            if let prefs = preferences.first, prefs.allowCellularUploads {
                Text("Cellular uploads may use significant mobile data.")
                    .font(.caption)
            }
        }
    }

    // MARK: - Recent History Section

    private var recentHistorySection: some View {
        Section {
            ForEach(recentUploads.prefix(5)) { video in
                HStack {
                    // Thumbnail
                    if let thumbnail = loadThumbnail(for: video) {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 60, height: 40)
                            .overlay {
                                Image(systemName: "video")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(video.fileName)
                            .font(.subheadline)
                            .lineLimit(1)

                        if let syncDate = video.lastSyncDate {
                            Text(formatRelativeDate(syncDate))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Image(systemName: "checkmark.icloud.fill")
                            .foregroundColor(.green)
                            .font(.caption)

                        Text(formatBytes(FileManager.default.fileSize(atPath: video.filePath)))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if recentUploads.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                        Text("No recent uploads")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 32)
                    Spacer()
                }
            }
        } header: {
            Text("Recent Uploads")
        }
    }

    // MARK: - Computed Properties

    private var uploadedVideos: [VideoClip] {
        allVideos.filter { $0.isUploaded }
    }

    private var uploadedCount: Int {
        uploadedVideos.count
    }

    private var localOnlyCount: Int {
        allVideos.count - uploadedCount - uploadManager.pendingUploads.count - uploadManager.activeUploads.count
    }

    private var totalUploadedSize: Int64 {
        uploadedVideos.reduce(0) { sum, video in
            sum + FileManager.default.fileSize(atPath: video.filePath)
        }
    }

    private var averageVideoSize: Int64 {
        guard uploadedCount > 0 else { return 0 }
        return totalUploadedSize / Int64(uploadedCount)
    }

    private var uploadPercentage: Double {
        guard allVideos.count > 0 else { return 0 }
        return Double(uploadedCount) / Double(allVideos.count)
    }

    private var successRate: Int {
        let totalAttempts = uploadedCount + uploadManager.failedUploads.count
        guard totalAttempts > 0 else { return 100 }
        return Int((Double(uploadedCount) / Double(totalAttempts)) * 100)
    }

    private var recentUploads: [VideoClip] {
        uploadedVideos
            .sorted { ($0.lastSyncDate ?? Date.distantPast) > ($1.lastSyncDate ?? Date.distantPast) }
    }

    private var networkIconColor: Color {
        if !networkMonitor.isConnected {
            return .red
        } else if networkMonitor.connectionType == .cellular {
            return .orange
        } else {
            return .green
        }
    }

    // MARK: - Helper Methods

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }

    private func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func loadThumbnail(for video: VideoClip) -> UIImage? {
        guard let thumbnailPath = video.thumbnailPath,
              !thumbnailPath.isEmpty,
              FileManager.default.fileExists(atPath: thumbnailPath) else {
            return nil
        }
        return UIImage(contentsOfFile: thumbnailPath)
    }

    private func retryAllFailed() {
        for upload in uploadManager.failedUploads {
            uploadManager.retryFailed(upload)
        }
        Haptics.success()
    }
}

// MARK: - Supporting Views

struct StatColumn: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            Text(value)
                .font(.headline)
                .fontWeight(.semibold)

            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct ActivityRow: View {
    let label: String
    let count: Int
    let icon: String
    let color: Color
    var isAnimated: Bool = false

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .symbolEffect(.bounce, options: .repeating, value: isAnimated)

            Text(label)
                .font(.subheadline)

            Spacer()

            Text("\(count)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
    }
}

#Preview {
    UploadStatisticsView()
        .modelContainer(for: [VideoClip.self, UserPreferences.self])
}
