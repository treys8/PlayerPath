//
//  StorageManager.swift
//  PlayerPath
//
//  Manages device storage checks and warnings
//

import Foundation
import os
import SwiftData

private nonisolated let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "RZR.DT3", category: "StorageManager")

struct StorageInfo {
    let availableBytes: Int64
    let totalBytes: Int64
    let availableGB: Double
    let percentageAvailable: Double
    let estimatedMinutesOfVideo: Int
    
    var formattedAvailableSpace: String {
        String(format: "%.1f GB", availableGB)
    }
    
    var isLowStorage: Bool {
        // Less than 500 MB is considered low
        availableBytes < StorageConstants.minimumFreeStorageBytes
    }
    
    var isCriticallyLowStorage: Bool {
        // Less than 100 MB is critical
        availableBytes < 100 * StorageConstants.bytesPerMB
    }
    
    var storageLevel: StorageLevel {
        if isCriticallyLowStorage {
            return .critical
        } else if isLowStorage {
            return .low
        } else if percentageAvailable > 0.5 {
            return .good
        } else {
            return .moderate
        }
    }
    
    enum StorageLevel {
        case good
        case moderate
        case low
        case critical
    }
}

struct StorageManager {
    
    // MARK: - Constants
    
    private static let mbPerMinuteVideo: Double = 150 // Average for high quality video
    
    // MARK: - Public Methods
    
    static func getStorageInfo() -> StorageInfo? {
        guard let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            logger.error("Could not access document directory")
            return nil
        }
        
        do {
            let values = try documentDirectory.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeTotalCapacityKey
            ])
            
            guard let available = values.volumeAvailableCapacityForImportantUsage,
                  let total = values.volumeTotalCapacity else {
                logger.error("Could not read storage values")
                return nil
            }
            
            let availableGB = Double(available) / StorageConstants.bytesPerGBDouble
            let percentageAvailable = Double(available) / Double(total)
            
            // Estimate recording time
            let availableMB = Double(available) / 1_048_576 // Convert to MB
            let estimatedMinutes = Int(availableMB / mbPerMinuteVideo)
            
            return StorageInfo(
                availableBytes: Int64(available),
                totalBytes: Int64(total),
                availableGB: availableGB,
                percentageAvailable: percentageAvailable,
                estimatedMinutesOfVideo: estimatedMinutes
            )
        } catch {
            logger.error("Failed to get storage info: \(error.localizedDescription)")
            return nil
        }
    }
    

    // MARK: - App Storage Usage

    /// Calculates total storage used by app videos and thumbnails
    /// - Returns: Tuple of (videos size, thumbnails size) in bytes
    static func calculateAppStorageUsage() async -> (videosSize: Int64, thumbnailsSize: Int64) {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return (0, 0)
        }

        let clipsDirectory = documentsURL.appendingPathComponent("Clips", isDirectory: true)
        let thumbnailsDirectory = documentsURL.appendingPathComponent("Thumbnails", isDirectory: true)

        let videosSize = await calculateDirectorySize(at: clipsDirectory)
        let thumbnailsSize = await calculateDirectorySize(at: thumbnailsDirectory)

        return (videosSize, thumbnailsSize)
    }

    private static func calculateDirectorySize(at url: URL) async -> Int64 {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return 0
        }

        // Use a deep enumerator so per-athlete / per-season subdirectories
        // are included. The previous contentsOfDirectory-based scan only
        // counted immediate children and silently undercounted nested files.
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let fileSize = values.fileSize else {
                continue
            }
            totalSize += Int64(fileSize)
        }
        return totalSize
    }

    // MARK: - Orphaned File Cleanup

    /// Finds videos with missing database entries (orphaned files)
    /// - Parameter context: SwiftData ModelContext
    /// - Returns: Array of file URLs that don't have corresponding database entries
    static func findOrphanedVideoFiles(context: ModelContext) async -> [URL] {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return []
        }

        let clipsDirectory = documentsURL.appendingPathComponent("Clips", isDirectory: true)

        guard FileManager.default.fileExists(atPath: clipsDirectory.path) else {
            return []
        }

        do {
            // Get all video files on disk
            let videoFiles = try FileManager.default.contentsOfDirectory(
                at: clipsDirectory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: .skipsHiddenFiles
            ).filter { url in
                // Keep in sync with OrphanedClipRecoveryService.findOrphanedVideoFiles
                // — both services must scan the same extension set so an orphan
                // visible in the recovery UI is also eligible for cleanup here.
                let ext = url.pathExtension.lowercased()
                return ext == "mov" || ext == "mp4" || ext == "m4v"
            }

            // Get all video filenames from database
            let descriptor = FetchDescriptor<VideoClip>()
            let allClips = try context.fetch(descriptor)
            let dbFileNames = Set(allClips.map { $0.fileName })

            // Find files not in database
            let orphanedFiles = videoFiles.filter { url in
                !dbFileNames.contains(url.lastPathComponent)
            }

            return orphanedFiles
        } catch {
            logger.error("Failed to find orphaned files: \(error.localizedDescription)")
            return []
        }
    }

    /// Deletes orphaned video files that don't have database entries
    /// - Parameter context: SwiftData ModelContext
    /// - Returns: Number of files deleted and total bytes freed
    static func cleanupOrphanedFiles(context: ModelContext) async -> (filesDeleted: Int, bytesFreed: Int64) {
        let orphanedFiles = await findOrphanedVideoFiles(context: context)

        var filesDeleted = 0
        var bytesFreed: Int64 = 0

        for fileURL in orphanedFiles {
            do {
                // Get file size before deletion
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                let fileSize = Int64(resourceValues.fileSize ?? 0)

                // Delete the file
                try FileManager.default.removeItem(at: fileURL)

                filesDeleted += 1
                bytesFreed += fileSize

                logger.info("Deleted orphaned file: \(fileURL.lastPathComponent) (\(formatBytes(fileSize)))")
            } catch {
                logger.error("Failed to delete orphaned file \(fileURL.lastPathComponent): \(error.localizedDescription)")
            }
        }

        return (filesDeleted, bytesFreed)
    }

    // MARK: - Startup Temp File Cleanup

    /// Removes orphaned `imported_*.mov` files left in the Documents directory
    /// when a video import succeeded but the subsequent save failed or was cancelled.
    nonisolated static func cleanupOrphanedImports() {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: documentsDir, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles) else { return }

        let importedFiles = contents.filter { $0.lastPathComponent.hasPrefix("imported_") }
        for file in importedFiles {
            // Only delete files older than 1 hour to avoid racing with an active import
            if let attrs = try? file.resourceValues(forKeys: [.creationDateKey]),
               let created = attrs.creationDate,
               Date().timeIntervalSince(created) > 3600 {
                try? fm.removeItem(at: file)
                logger.info("Cleaned up orphaned import: \(file.lastPathComponent)")
            }
        }
    }

    /// Removes stale export files (CSV, PDF, JSON) from the system temp directory.
    /// Called on app launch to prevent accumulation from prior share sessions.
    nonisolated static func cleanupStaleExports() {
        let tempDir = FileManager.default.temporaryDirectory
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles) else { return }

        let exportExtensions: Set<String> = ["csv", "pdf", "json"]
        let staleFiles = contents.filter { exportExtensions.contains($0.pathExtension.lowercased()) }
        for file in staleFiles {
            // Only delete files older than 1 hour to avoid racing with an
            // in-flight UIActivityViewController share that survived an
            // app relaunch. Matches cleanupOrphanedImports' policy.
            guard let attrs = try? file.resourceValues(forKeys: [.creationDateKey]),
                  let created = attrs.creationDate,
                  Date().timeIntervalSince(created) > 3600 else { continue }
            try? fm.removeItem(at: file)
            logger.info("Cleaned up stale export: \(file.lastPathComponent)")
        }
    }

    // MARK: - Formatting Helpers

    /// Formats bytes to human-readable string (e.g., "1.5 GB")
    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
