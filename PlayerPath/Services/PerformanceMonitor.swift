//
//  PerformanceMonitor.swift
//  PlayerPath
//
//  Monitors app performance metrics including memory usage and thumbnail cache efficiency
//

import Foundation
import UIKit

@MainActor
@Observable
final class PerformanceMonitor {
    static let shared = PerformanceMonitor()

    // MARK: - Published State

    var currentMemoryUsage: UInt64 = 0
    var memoryWarningCount: Int = 0
    var thumbnailCacheHitRate: Double = 0
    var isMonitoring: Bool = false

    // MARK: - Private State

    private var memoryWarningObserver: NSObjectProtocol?
    private var monitoringTimer: Timer?
    private var cacheHits: Int = 0
    private var cacheMisses: Int = 0

    private init() {}

    // MARK: - Monitoring Control

    /// Start monitoring performance metrics
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // Monitor memory warnings
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleMemoryWarning()
            }
        }

        // Update memory usage periodically
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateMemoryUsage()
            }
        }

        print("PerformanceMonitor: Started monitoring")
    }

    /// Stop monitoring performance metrics
    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false

        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
            memoryWarningObserver = nil
        }

        monitoringTimer?.invalidate()
        monitoringTimer = nil

        print("PerformanceMonitor: Stopped monitoring")
    }

    // MARK: - Memory Monitoring

    private func updateMemoryUsage() {
        var taskInfo = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            currentMemoryUsage = taskInfo.phys_footprint
        }
    }

    private func handleMemoryWarning() {
        memoryWarningCount += 1
        print("⚠️ PerformanceMonitor: Memory warning received (total: \(memoryWarningCount))")

        // Clear thumbnail cache to free memory
        ThumbnailCache.shared.clearCache()

        updateMemoryUsage()
    }

    // MARK: - Cache Metrics

    /// Record a cache hit (thumbnail found in cache)
    func recordCacheHit() {
        cacheHits += 1
        updateCacheHitRate()
    }

    /// Record a cache miss (thumbnail loaded from disk)
    func recordCacheMiss() {
        cacheMisses += 1
        updateCacheHitRate()
    }

    private func updateCacheHitRate() {
        let total = cacheHits + cacheMisses
        thumbnailCacheHitRate = total > 0 ? Double(cacheHits) / Double(total) : 0
    }

    /// Reset cache metrics
    func resetCacheMetrics() {
        cacheHits = 0
        cacheMisses = 0
        thumbnailCacheHitRate = 0
    }

    // MARK: - Formatted Output

    /// Get current memory usage in human-readable format
    var formattedMemoryUsage: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(currentMemoryUsage))
    }

    /// Get cache hit rate as percentage
    var formattedCacheHitRate: String {
        return String(format: "%.1f%%", thumbnailCacheHitRate * 100)
    }

    /// Generate performance summary
    func generatePerformanceSummary() -> String {
        return """
        Performance Metrics:
        - Memory Usage: \(formattedMemoryUsage)
        - Memory Warnings: \(memoryWarningCount)
        - Thumbnail Cache Hit Rate: \(formattedCacheHitRate)
        - Cache Stats: \(cacheHits) hits, \(cacheMisses) misses
        """
    }

    // MARK: - Performance Recommendations

    /// Get performance recommendations based on metrics
    func getPerformanceRecommendations() -> [String] {
        var recommendations: [String] = []

        // High memory usage
        if currentMemoryUsage > 200_000_000 { // 200 MB
            recommendations.append("Memory usage is high. Consider reducing video quality or clearing unused data.")
        }

        // Frequent memory warnings
        if memoryWarningCount > 3 {
            recommendations.append("Multiple memory warnings detected. The app may need optimization.")
        }

        // Low cache hit rate
        if thumbnailCacheHitRate < 0.5 && (cacheHits + cacheMisses) > 20 {
            recommendations.append("Low cache hit rate. Thumbnails may need preloading optimization.")
        }

        if recommendations.isEmpty {
            recommendations.append("Performance is good!")
        }

        return recommendations
    }
}
