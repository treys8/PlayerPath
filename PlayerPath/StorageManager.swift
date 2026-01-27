//
//  StorageManager.swift
//  PlayerPath
//
//  Manages device storage checks and warnings
//

import Foundation
import os
import SwiftData

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.app", category: "StorageManager")

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
        availableBytes < 500_000_000
    }
    
    var isCriticallyLowStorage: Bool {
        // Less than 100 MB is critical
        availableBytes < 100_000_000
    }
    
    var storageLevel: StorageLevel {
        if isCriticallyLowStorage {
            return .critical
        } else if isLowStorage {
            return .low
        } else if percentageAvailable > 0.5 {
            return .good
        } else if percentageAvailable > 0.2 {
            return .moderate
        } else {
            return .low
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
    
    private static let minimumStorageBytes: Int64 = 500_000_000 // 500 MB
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
            
            let availableGB = Double(available) / 1_073_741_824 // Convert to GB
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
    
    static func shouldWarnAboutLowStorage() -> Bool {
        guard let info = getStorageInfo() else {
            return false
        }
        return info.isLowStorage
    }
    
    static func shouldBlockRecordingDueToStorage() -> Bool {
        guard let info = getStorageInfo() else {
            return false
        }
        return info.isCriticallyLowStorage
    }
    
    static func getLowStorageMessage() -> String {
        guard let info = getStorageInfo() else {
            return "Unable to determine available storage space."
        }

        if info.isCriticallyLowStorage {
            return "Your device has critically low storage (\(info.formattedAvailableSpace) remaining). Please free up space before recording."
        } else if info.isLowStorage {
            return "Your device is running low on storage space (\(info.formattedAvailableSpace) remaining). Recording may fail or produce poor quality video. Consider freeing up space before recording."
        } else {
            return "You have \(info.formattedAvailableSpace) of storage available."
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

        var totalSize: Int64 = 0

        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: .skipsHiddenFiles
            )

            for fileURL in files {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])

                guard let isRegularFile = resourceValues.isRegularFile, isRegularFile else {
                    continue
                }

                if let fileSize = resourceValues.fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        } catch {
            logger.error("Failed to calculate directory size: \(error.localizedDescription)")
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
                let ext = url.pathExtension.lowercased()
                return ext == "mov" || ext == "mp4"
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

    // MARK: - Formatting Helpers

    /// Formats bytes to human-readable string (e.g., "1.5 GB")
    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
