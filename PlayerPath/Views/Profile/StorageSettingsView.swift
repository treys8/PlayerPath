//
//  StorageSettingsView.swift
//  PlayerPath
//
//  Device and app storage management with orphaned file cleanup.
//

import SwiftUI
import SwiftData

// MARK: - Storage Settings View
struct StorageSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var storageInfo: StorageInfo?
    @State private var appVideosSize: Int64 = 0
    @State private var appThumbnailsSize: Int64 = 0
    @State private var orphanedFilesCount: Int = 0
    @State private var isLoadingStorage = true
    @State private var isCleaningUp = false
    @State private var cleanupMessage: String?

    var body: some View {
        Form {
            // Device Storage Section
            Section("Device Storage") {
                if let info = storageInfo {
                    VStack(alignment: .leading, spacing: 12) {
                        // Storage level indicator
                        HStack {
                            Image(systemName: storageIcon(for: info.storageLevel))
                                .foregroundColor(storageColor(for: info.storageLevel))
                            Text(storageLabel(for: info.storageLevel))
                                .font(.headingMedium)
                                .foregroundColor(storageColor(for: info.storageLevel))
                        }

                        // Progress bar
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(height: 8)
                                    .cornerRadius(4)

                                Rectangle()
                                    .fill(storageColor(for: info.storageLevel))
                                    .frame(width: geometry.size.width * (1.0 - info.percentageAvailable), height: 8)
                                    .cornerRadius(4)
                            }
                        }
                        .frame(height: 8)

                        // Storage details
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Available:")
                                Spacer()
                                Text(info.formattedAvailableSpace)
                                    .foregroundColor(.secondary)
                            }

                            HStack {
                                Text("Total:")
                                Spacer()
                                Text(StorageManager.formatBytes(info.totalBytes))
                                    .foregroundColor(.secondary)
                            }

                            HStack {
                                Text("Estimated Recording Time:")
                                Spacer()
                                Text("\(info.estimatedMinutesOfVideo) min")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .font(.bodySmall)
                    }
                } else {
                    HStack {
                        ProgressView()
                        Text("Loading storage information...")
                            .foregroundColor(.secondary)
                    }
                }
            }

            // App Storage Section
            Section("PlayerPath Storage") {
                HStack {
                    Text("Videos")
                    Spacer()
                    if isLoadingStorage {
                        ProgressView()
                    } else {
                        Text(StorageManager.formatBytes(appVideosSize))
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Text("Thumbnails")
                    Spacer()
                    if isLoadingStorage {
                        ProgressView()
                    } else {
                        Text(StorageManager.formatBytes(appThumbnailsSize))
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Text("Total App Storage")
                    Spacer()
                    if isLoadingStorage {
                        ProgressView()
                    } else {
                        Text(StorageManager.formatBytes(appVideosSize + appThumbnailsSize))
                            .foregroundColor(.brandNavy)
                            .font(.headingMedium)
                    }
                }
            }

            // Cleanup Section
            Section {
                if orphanedFilesCount > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("\(orphanedFilesCount) orphaned file\(orphanedFilesCount == 1 ? "" : "s") found")
                                .font(.bodyMedium)
                        }

                        Text("These files are taking up space but are not linked to any videos in your library.")
                            .font(.bodySmall)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)

                    Button {
                        Task {
                            await performCleanup()
                        }
                    } label: {
                        HStack {
                            if isCleaningUp {
                                ProgressView()
                            } else {
                                Image(systemName: "trash")
                            }
                            Text("Clean Up Orphaned Files")
                        }
                    }
                    .disabled(isCleaningUp)
                } else if !isLoadingStorage {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("No orphaned files found")
                            .foregroundColor(.secondary)
                    }
                }

                if let message = cleanupMessage {
                    Text(message)
                        .font(.bodySmall)
                        .foregroundColor(.green)
                        .padding(.vertical, 4)
                }
            } header: {
                Text("Maintenance")
            } footer: {
                Text("Orphaned files are videos that exist on disk but have no database entry. This can happen if app data is restored from backup.")
                    .font(.bodySmall)
            }
        }
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadStorageInfo()
        }
    }

    private func loadStorageInfo() async {
        isLoadingStorage = true

        // Load device storage info
        storageInfo = StorageManager.getStorageInfo()

        // Load app storage usage
        let (videos, thumbnails) = await StorageManager.calculateAppStorageUsage()
        appVideosSize = videos
        appThumbnailsSize = thumbnails

        // Find orphaned files
        let orphanedFiles = await StorageManager.findOrphanedVideoFiles(context: modelContext)
        orphanedFilesCount = orphanedFiles.count

        isLoadingStorage = false
    }

    private func performCleanup() async {
        isCleaningUp = true
        cleanupMessage = nil

        let (filesDeleted, bytesFreed) = await StorageManager.cleanupOrphanedFiles(context: modelContext)

        if filesDeleted > 0 {
            cleanupMessage = "Deleted \(filesDeleted) file\(filesDeleted == 1 ? "" : "s"), freed \(StorageManager.formatBytes(bytesFreed))"
            Haptics.success()

            // Reload storage info
            await loadStorageInfo()
        } else {
            cleanupMessage = "No files to clean up"
        }

        isCleaningUp = false
    }

    private func storageIcon(for level: StorageInfo.StorageLevel) -> String {
        switch level {
        case .good: return "internaldrive"
        case .moderate: return "internaldrive.fill"
        case .low: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }

    private func storageColor(for level: StorageInfo.StorageLevel) -> Color {
        switch level {
        case .good: return .green
        case .moderate: return .brandNavy
        case .low: return .orange
        case .critical: return .red
        }
    }

    private func storageLabel(for level: StorageInfo.StorageLevel) -> String {
        switch level {
        case .good: return "Storage Healthy"
        case .moderate: return "Storage Moderate"
        case .low: return "Storage Low"
        case .critical: return "Storage Critical"
        }
    }
}
