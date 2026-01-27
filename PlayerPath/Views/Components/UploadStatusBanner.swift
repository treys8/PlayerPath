//
//  UploadStatusBanner.swift
//  PlayerPath
//
//  Shows upload queue status to users
//

import SwiftUI
import SwiftData

struct UploadStatusBanner: View {
    @State private var uploadManager = UploadQueueManager.shared
    @State private var networkMonitor = ConnectivityMonitor.shared
    @Query private var preferences: [UserPreferences]

    var body: some View {
        if hasActiveUploads || hasPendingUploads || hasFailedUploads || showsNetworkWarning {
            VStack(spacing: 0) {
                // Network warning (when uploads paused)
                if showsNetworkWarning {
                    networkWarningView
                }

                // Active uploads
                if hasActiveUploads {
                    activeUploadsView
                }

                // Pending uploads
                if hasPendingUploads && !hasActiveUploads && !showsNetworkWarning {
                    pendingUploadsView
                }

                // Failed uploads
                if hasFailedUploads {
                    failedUploadsView
                }
            }
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Active Uploads View

    private var activeUploadsView: some View {
        VStack(spacing: 8) {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)

                Text("Uploading \(uploadManager.activeUploads.count) video\(uploadManager.activeUploads.count == 1 ? "" : "s")...")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Text("\(Int(averageProgress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Progress bar
            if let firstUpload = uploadManager.pendingUploads.first,
               let progress = uploadManager.activeUploads[firstUpload.clipId] {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 4)
                            .cornerRadius(2)

                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: geometry.size.width * progress, height: 4)
                            .cornerRadius(2)
                            .animation(.linear(duration: 0.3), value: progress)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding()
    }

    // MARK: - Network Warning View

    private var networkWarningView: some View {
        HStack {
            Image(systemName: networkMonitor.isConnected ? "wifi.exclamationmark" : "wifi.slash")
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 2) {
                if !networkMonitor.isConnected {
                    Text("Uploads paused - No internet")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Will resume when connection returns")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if networkMonitor.connectionType == .cellular {
                    Text("Uploads paused - On cellular")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Enable cellular uploads in settings or connect to WiFi")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Pending Uploads View

    private var pendingUploadsView: some View {
        HStack {
            Image(systemName: "icloud.and.arrow.up")
                .foregroundColor(.blue)

            Text("\(uploadManager.totalPendingCount) video\(uploadManager.totalPendingCount == 1 ? "" : "s") queued for upload")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Text("Uploading...")
                .font(.caption)
                .foregroundColor(.blue)
        }
        .padding()
    }

    // MARK: - Failed Uploads View

    private var failedUploadsView: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(uploadManager.failedUploads.count) upload\(uploadManager.failedUploads.count == 1 ? "" : "s") failed")
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let firstFailed = uploadManager.failedUploads.first {
                    Text("Retried \(firstFailed.retryCount) times")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Menu {
                Button {
                    retryAllFailed()
                } label: {
                    Label("Retry All", systemImage: "arrow.clockwise")
                }

                Button(role: .destructive) {
                    clearFailedUploads()
                } label: {
                    Label("Clear", systemImage: "xmark")
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .foregroundColor(.orange)
            }
        }
        .padding()
    }

    // MARK: - Computed Properties

    private var hasActiveUploads: Bool {
        !uploadManager.activeUploads.isEmpty
    }

    private var hasPendingUploads: Bool {
        !uploadManager.pendingUploads.isEmpty
    }

    private var hasFailedUploads: Bool {
        !uploadManager.failedUploads.isEmpty
    }

    private var averageProgress: Double {
        guard !uploadManager.activeUploads.isEmpty else { return 0 }
        let total = uploadManager.activeUploads.values.reduce(0, +)
        return total / Double(uploadManager.activeUploads.count)
    }

    private var showsNetworkWarning: Bool {
        // Only show warning if there are uploads waiting
        guard hasPendingOrActiveUploads else { return false }

        // Show warning if not connected
        if !networkMonitor.isConnected {
            return true
        }

        // Show warning if on cellular and cellular uploads not allowed
        if networkMonitor.connectionType == .cellular {
            let prefs = preferences.first
            return !(prefs?.allowCellularUploads ?? false)
        }

        return false
    }

    private var hasPendingOrActiveUploads: Bool {
        hasPendingUploads || hasActiveUploads
    }

    // MARK: - Actions

    private func retryAllFailed() {
        for upload in uploadManager.failedUploads {
            uploadManager.retryFailed(upload)
        }
        Haptics.success()
    }

    private func clearFailedUploads() {
        uploadManager.failedUploads.removeAll()
        Haptics.light()
    }
}

// MARK: - Compact Upload Badge

/// A compact upload badge for showing in tab bars or navigation bars
struct UploadBadge: View {
    @State private var uploadManager = UploadQueueManager.shared

    var body: some View {
        if totalUploadCount > 0 {
            HStack(spacing: 4) {
                if uploadManager.isProcessing {
                    ProgressView()
                        .scaleEffect(0.6)
                }

                Text("\(totalUploadCount)")
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(badgeColor)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
    }

    private var totalUploadCount: Int {
        uploadManager.pendingUploads.count + uploadManager.activeUploads.count
    }

    private var badgeColor: Color {
        if !uploadManager.failedUploads.isEmpty {
            return .orange
        } else if uploadManager.isProcessing {
            return .blue
        } else {
            return .gray
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        UploadStatusBanner()
        UploadBadge()
    }
    .padding()
}
