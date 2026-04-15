//
//  StorageConstants.swift
//  PlayerPath
//
//  Centralized storage and byte-size constants
//

import Foundation

enum StorageConstants {
    // MARK: - Byte Conversions

    /// 1 GB in bytes (1,073,741,824)
    static let bytesPerGB: Int64 = 1_073_741_824
    static let bytesPerGBDouble: Double = 1_073_741_824.0

    /// 1 MB in bytes (1,048,576)
    static let bytesPerMB: Int64 = 1_048_576

    // MARK: - Cache Limits

    /// URL cache size (100 MB)
    static let urlCacheSizeBytes = 100 * 1024 * 1024

    /// Thumbnail memory cache size (50 MB)
    static let thumbnailCacheSizeBytes = 50 * 1024 * 1024

    // MARK: - File Limits

    /// Maximum video file size for upload (500 MB)
    static let maxVideoFileSizeBytes: Int64 = 500 * 1024 * 1024

    // MARK: - Storage Thresholds

    /// Minimum free device storage before warning (500 MB, binary — matches bytesPerMB)
    static let minimumFreeStorageBytes: Int64 = 500 * bytesPerMB
}
