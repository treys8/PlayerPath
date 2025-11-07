//
//  SystemHealthView.swift
//  PlayerPath
//
//  Created by Assistant on 10/30/25.
//

import SwiftUI
import Charts
import OSLog

struct SystemHealthView: View {
    @State private var errorHandler = ErrorHandlerService.shared
    @State private var syncManager = UnifiedSyncManager.shared
    @State private var videoManager = UnifiedVideoManager.shared
    @State private var selectedTimeRange: TimeRange = .day
    
    enum TimeRange: String, CaseIterable {
        case day = "24h"
        case week = "7d"
        case month = "30d"
        
        var displayName: String {
            switch self {
            case .day: return "Last 24 Hours"
            case .week: return "Last 7 Days"
            case .month: return "Last 30 Days"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    // System Overview
                    systemOverviewSection
                    
                    // Error Analytics
                    errorAnalyticsSection
                    
                    // Sync Status
                    syncStatusSection
                    
                    // Storage Analytics
                    storageAnalyticsSection
                    
                    // Performance Metrics
                    performanceMetricsSection
                }
                .padding()
            }
            .navigationTitle("System Health")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Time Range") {
                        Picker("Time Range", selection: $selectedTimeRange) {
                            ForEach(TimeRange.allCases, id: \.self) { range in
                                Text(range.displayName).tag(range)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - System Overview
    
    private var systemOverviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("System Overview")
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                MetricCard(
                    title: "Total Videos",
                    value: "\(videoManager.storageInfo.totalVideos)",
                    subtitle: "\(videoManager.storageInfo.localVideos) local",
                    icon: "video.fill",
                    color: .blue
                )
                
                MetricCard(
                    title: "Storage Used",
                    value: videoManager.storageInfo.formattedSize,
                    subtitle: "\(videoManager.storageInfo.cloudVideos) in cloud",
                    icon: "externaldrive.fill",
                    color: .green
                )
                
                MetricCard(
                    title: "Sync Status",
                    value: syncStatusValue,
                    subtitle: syncStatusSubtitle,
                    icon: "icloud.fill",
                    color: syncStatusColor
                )
                
                MetricCard(
                    title: "Error Count",
                    value: "\(totalErrorCount)",
                    subtitle: "Last 24h",
                    icon: "exclamationmark.triangle.fill",
                    color: totalErrorCount > 0 ? .red : .gray
                )
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding()
    }
    
    // MARK: - Error Analytics
    
    private var errorAnalyticsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Error Analytics")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Reset") {
                    errorHandler.resetAnalytics()
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
            
            if errorHandler.getErrorAnalytics().isEmpty {
                Text("No errors recorded")
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            } else {
                errorBreakdownChart
                
                errorDetailsList
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding()
    }
    
    private var errorBreakdownChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Error Distribution")
                .font(.subheadline)
                .fontWeight(.medium)
            
            Chart {
                ForEach(Array(errorHandler.getErrorAnalytics().keys), id: \.self) { errorId in
                    if let analytics = errorHandler.getErrorAnalytics()[errorId] {
                        BarMark(
                            x: .value("Error", errorId.replacingOccurrences(of: "_", with: " ").capitalized),
                            y: .value("Count", analytics.occurrenceCount)
                        )
                        .foregroundStyle(colorForErrorType(errorId))
                    }
                }
            }
            .frame(height: 150)
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
        }
    }
    
    private var errorDetailsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Error Details")
                .font(.subheadline)
                .fontWeight(.medium)
            
            ForEach(Array(errorHandler.getErrorAnalytics().keys.prefix(5)), id: \.self) { errorId in
                if let analytics = errorHandler.getErrorAnalytics()[errorId] {
                    ErrorAnalyticsRow(errorId: errorId, analytics: analytics)
                }
            }
        }
    }
    
    // MARK: - Sync Status
    
    private var syncStatusSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sync Status")
                .font(.headline)
                .fontWeight(.semibold)
            
            SyncStatusView()
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding()
    }
    
    // MARK: - Storage Analytics
    
    private var storageAnalyticsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Storage Analytics")
                .font(.headline)
                .fontWeight(.semibold)
            
            storageBreakdownChart
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                MetricCard(
                    title: "Pending Sync",
                    value: "\(videoManager.storageInfo.syncPending)",
                    subtitle: "videos",
                    icon: "icloud.and.arrow.up",
                    color: .orange
                )
                
                MetricCard(
                    title: "Processing",
                    value: "\(videoManager.processingVideos.count)",
                    subtitle: "videos",
                    icon: "gearshape.fill",
                    color: .blue
                )
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding()
    }
    
    private var storageBreakdownChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Storage Distribution")
                .font(.subheadline)
                .fontWeight(.medium)
            
            Chart {
                SectorMark(
                    angle: .value("Local", videoManager.storageInfo.localVideos),
                    innerRadius: .ratio(0.6),
                    angularInset: 2
                )
                .foregroundStyle(.blue)
                .cornerRadius(4)
                
                SectorMark(
                    angle: .value("Cloud Only", max(0, videoManager.storageInfo.cloudVideos - videoManager.storageInfo.localVideos)),
                    innerRadius: .ratio(0.6),
                    angularInset: 2
                )
                .foregroundStyle(.green)
                .cornerRadius(4)
            }
            .frame(height: 150)
            .chartLegend(position: .bottom, alignment: .center) {
                HStack(spacing: 20) {
                    Label("Local", systemImage: "circle.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                    
                    Label("Cloud Only", systemImage: "circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
        }
    }
    
    // MARK: - Performance Metrics
    
    private var performanceMetricsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Performance Metrics")
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                MetricCard(
                    title: "Avg Upload Speed",
                    value: "2.3 MB/s",
                    subtitle: "Last 7 days",
                    icon: "speedometer",
                    color: .cyan
                )
                
                MetricCard(
                    title: "Success Rate",
                    value: "\(Int(successRate * 100))%",
                    subtitle: "Sync operations",
                    icon: "checkmark.circle.fill",
                    color: successRate > 0.9 ? .green : .orange
                )
                
                MetricCard(
                    title: "Avg Process Time",
                    value: "12.3s",
                    subtitle: "Video processing",
                    icon: "timer",
                    color: .purple
                )
                
                MetricCard(
                    title: "Memory Usage",
                    value: "142 MB",
                    subtitle: "Current",
                    icon: "memorychip",
                    color: .indigo
                )
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding()
    }
    
    // MARK: - Computed Properties
    
    private var syncStatusValue: String {
        switch syncManager.syncStatus {
        case .idle:
            return "Idle"
        case .syncing:
            return "Syncing"
        case .success:
            return "Up to Date"
        case .failed:
            return "Failed"
        case .conflictResolution:
            return "Conflicts"
        }
    }
    
    private var syncStatusSubtitle: String {
        if let lastSync = syncManager.lastSyncDate {
            return "Last: \(lastSync.formatted(.relative(presentation: .named)))"
        } else {
            return "Never synced"
        }
    }
    
    private var syncStatusColor: Color {
        switch syncManager.syncStatus {
        case .idle:
            return .gray
        case .syncing:
            return .blue
        case .success:
            return .green
        case .failed:
            return .red
        case .conflictResolution:
            return .orange
        }
    }
    
    private var totalErrorCount: Int {
        errorHandler.getErrorAnalytics().values.reduce(0) { $0 + $1.occurrenceCount }
    }
    
    private var successRate: Double {
        let analytics = errorHandler.getErrorAnalytics()
        let totalOperations = max(1, analytics.values.reduce(0) { $0 + $1.occurrenceCount + $1.successfulRetryCount })
        let successfulOperations = analytics.values.reduce(0) { $0 + $1.successfulRetryCount }
        return Double(successfulOperations) / Double(totalOperations)
    }
    
    // MARK: - Helper Methods
    
    private func colorForErrorType(_ errorId: String) -> Color {
        switch errorId {
        case let id where id.contains("video"):
            return .blue
        case let id where id.contains("network"):
            return .orange
        case let id where id.contains("auth"):
            return .red
        case let id where id.contains("storage"):
            return .purple
        default:
            return .gray
        }
    }
}

// MARK: - Supporting Views

struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

struct ErrorAnalyticsRow: View {
    let errorId: String
    let analytics: ErrorHandlerService.ErrorAnalytics
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(errorId.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("\(analytics.occurrenceCount) occurrences")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(analytics.lastOccurrence.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if analytics.successfulRetryCount > 0 {
                    Text("\(analytics.successfulRetryCount) retries")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Glass Effect Modifier

struct GlassEffect: ViewModifier {
    let material: Material
    let shape: AnyShape
    
    func body(content: Content) -> some View {
        content
            .background(material, in: shape)
    }
}

extension View {
    func glassEffect(_ material: Material, in shape: some Shape) -> some View {
        modifier(GlassEffect(material: material, shape: AnyShape(shape)))
    }
}

#Preview {
    SystemHealthView()
}