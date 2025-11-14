//
//  StorageManager.swift
//  PlayerPath
//
//  Manages device storage checks and warnings
//

import Foundation
import os

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
                availableBytes: available,
                totalBytes: total,
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
}
