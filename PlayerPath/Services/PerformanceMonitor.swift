//
//  PerformanceMonitor.swift
//  PlayerPath
//
//  Tracks thumbnail cache efficiency metrics.
//

import Foundation

@MainActor
@Observable
final class PerformanceMonitor {
    static let shared = PerformanceMonitor()

    private(set) var thumbnailCacheHitRate: Double = 0
    private var cacheHits: Int = 0
    private var cacheMisses: Int = 0

    private init() {}

    func recordCacheHit() {
        cacheHits += 1
        updateCacheHitRate()
    }

    func recordCacheMiss() {
        cacheMisses += 1
        updateCacheHitRate()
    }

    private func updateCacheHitRate() {
        let total = cacheHits + cacheMisses
        thumbnailCacheHitRate = total > 0 ? Double(cacheHits) / Double(total) : 0
    }
}
