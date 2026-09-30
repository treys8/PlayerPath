//
//  StorageSettingsView.swift
//  PlayerPath
//
//  Device, app and cloud storage, plus recovery/cleanup of video files that
//  lost their library record.
//

import SwiftUI
import SwiftData

// MARK: - Storage Settings View
struct StorageSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.ppAccent) private var ppAccent
    @State private var storageInfo: StorageInfo?
    @State private var appUsage: AppStorageUsage?
    @State private var orphanedFilesCount: Int = 0
    @State private var isLoadingStorage = true
    @State private var isCleaningUp = false
    @State private var showDeleteConfirmation = false
    @State private var cleanupMessage: String?
    @Query private var users: [User]

    private var user: User? { users.first }
    /// Coach uploads never touch `cloudStorageUsedBytes` and the limit below is the
    /// athlete tier's, so the card is only meaningful for athletes. Hidden while
    /// `users` is still empty so it doesn't flash in for coaches.
    private var showsCloudStorage: Bool { user.map { $0.role != "coach" } ?? false }
    /// Same pick `OrphanedClipRecoveryService` makes — most recently created athlete.
    private var recoveryAthletes: [Athlete] {
        (user?.athletes ?? []).sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }
    private var cloudUsedBytes: Int64 { user?.cloudStorageUsedBytes ?? 0 }
    private var cloudLimitBytes: Int64 {
        Int64(SubscriptionGate.effectiveAthleteTier.storageLimitGB) * StorageConstants.bytesPerGB
    }
    /// Cloud limits are defined in binary GB (`StorageConstants.bytesPerGB`), so
    /// format with `.binary` — `.file` style divides by 1000³ and shows a 100 GB
    /// plan as "107.37 GB".
    private static func cloudBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .binary
        formatter.allowsNonnumericFormatting = false // "0 KB", not "Zero KB"
        return formatter.string(fromByteCount: bytes)
    }
    private var cloudFraction: Double {
        cloudLimitBytes > 0 ? min(1.0, Double(cloudUsedBytes) / Double(cloudLimitBytes)) : 0
    }
    private var cloudBarColor: Color {
        if cloudFraction >= 0.9 { return .red }
        if cloudFraction >= 0.75 { return Theme.warning }
        return ppAccent
    }

    var body: some View {
        Form {
            if showsCloudStorage {
                cloudSection
            }
            deviceSection
            appSection
            if orphanedFilesCount > 0 || cleanupMessage != nil {
                maintenanceSection
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.surface)
        .tint(ppAccent)
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete \(orphanedFilesCount) video\(orphanedFilesCount == 1 ? "" : "s")?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) {
                Task { await performCleanup() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These videos aren't in your library and can't be recovered after deleting.")
        }
        .task {
            await loadStorageInfo()
        }
    }

    // MARK: - Sections

    // Cloud usage drives upload gating in SyncCoordinator, so it leads — surface
    // it before the user hits the wall.
    private var cloudSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: cloudFraction >= 0.9 ? "exclamationmark.icloud.fill" : "icloud.fill")
                        .foregroundStyle(cloudBarColor)
                    Text(cloudFraction >= 0.9 ? "Cloud Almost Full" : "Cloud Backup")
                        .font(.ppHeadline)
                        .foregroundStyle(cloudBarColor)
                }

                UsageBar(fraction: cloudFraction, color: cloudBarColor)

                HStack {
                    Text("Used")
                    Spacer()
                    Text("\(Self.cloudBytes(cloudUsedBytes)) of \(Self.cloudBytes(cloudLimitBytes))")
                        .foregroundStyle(Theme.textSecondary)
                }
                .font(.ppBody)

                if cloudFraction >= 0.9 {
                    Text("You're near your plan's cloud limit — new videos and photos may stop uploading. Free up space or upgrade your plan.")
                        .font(.ppFootnote)
                        .foregroundStyle(Theme.warning)
                }
            }
        } header: {
            Text("Cloud Storage")
        } footer: {
            Text("Cloud storage holds your uploaded videos and photos so they back up and sync across devices. Your limit is set by your plan.")
                .font(.ppFootnote)
        }
    }

    private var deviceSection: some View {
        Section("Device Storage") {
            if let info = storageInfo {
                let usedFraction = 1.0 - info.percentageAvailable
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: storageIcon(for: info.storageLevel))
                            .foregroundStyle(storageColor(for: info.storageLevel))
                        Text(storageLabel(for: info.storageLevel, usedFraction: usedFraction))
                            .font(.ppHeadline)
                            .foregroundStyle(storageLabelColor(for: info.storageLevel))
                    }

                    UsageBar(fraction: usedFraction, color: storageColor(for: info.storageLevel))

                    VStack(alignment: .leading, spacing: 4) {
                        valueRow("Free", StorageManager.formatBytes(info.availableBytes))
                        valueRow("Total", StorageManager.formatBytes(info.totalBytes))
                        valueRow("Recording Time Left", recordingTimeText(minutes: info.estimatedMinutesOfVideo))
                    }
                    .font(.ppBody)
                }
            } else {
                HStack {
                    ProgressView()
                    Text("Loading storage information...")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private var appSection: some View {
        Section("PlayerPath Storage") {
            appRow("Videos", appUsage?.videos)
            appRow("Photos", appUsage?.photos)
            appRow("Thumbnails", appUsage?.thumbnails)
            appRow("Cache", appUsage?.cache)

            HStack {
                Text("Total App Storage")
                Spacer()
                if let usage = appUsage, !isLoadingStorage {
                    Text(StorageManager.formatBytes(usage.total))
                        .font(.ppHeadline)
                        .foregroundStyle(ppAccent)
                } else {
                    ProgressView()
                }
            }
        }
    }

    private var maintenanceSection: some View {
        Section {
            if orphanedFilesCount > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.warning)
                        Text("\(orphanedFilesCount) video\(orphanedFilesCount == 1 ? "" : "s") not in your library")
                            .font(.ppBody)
                    }

                    Text("These videos are on this device but aren't linked to your library.")
                        .font(.ppFootnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.vertical, 4)

                if !recoveryAthletes.isEmpty {
                    Button {
                        Task { await performRecovery() }
                    } label: {
                        Label("Recover to Videos", systemImage: "arrow.uturn.backward.circle")
                    }
                    .disabled(isCleaningUp)
                }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    HStack {
                        if isCleaningUp {
                            ProgressView()
                        } else {
                            Image(systemName: "trash")
                        }
                        Text("Delete Permanently")
                    }
                }
                .disabled(isCleaningUp)
            }

            if let message = cleanupMessage {
                Text(message)
                    .font(.ppFootnote)
                    .foregroundStyle(Theme.success)
                    .padding(.vertical, 4)
            }
        } header: {
            Text("Maintenance")
        } footer: {
            Text("Usually left behind by an interrupted save or a restore from backup.")
                .font(.ppFootnote)
        }
    }

    // MARK: - Rows

    private func valueRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func appRow(_ title: String, _ bytes: Int64?) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let bytes, !isLoadingStorage {
                Text(StorageManager.formatBytes(bytes))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ProgressView()
            }
        }
    }

    // MARK: - Actions

    private func loadStorageInfo() async {
        isLoadingStorage = true

        storageInfo = StorageManager.getStorageInfo()
        appUsage = await StorageManager.calculateAppStorageUsage()

        let orphanedFiles = await StorageManager.findOrphanedVideoFiles(context: modelContext)
        orphanedFilesCount = orphanedFiles.count

        isLoadingStorage = false
    }

    private func performRecovery() async {
        isCleaningUp = true
        cleanupMessage = nil

        let athletes = recoveryAthletes
        let athleteName = athletes.first?.name ?? ""
        let recovered = await OrphanedClipRecoveryService.shared.recoverIfNeeded(
            context: modelContext,
            athletes: athletes,
            minimumFileAge: StorageManager.orphanMinimumFileAge
        )

        if recovered > 0 {
            cleanupMessage = "Recovered \(recovered) clip\(recovered == 1 ? "" : "s") to \(athleteName)'s videos as untagged"
            Haptics.success()
        } else {
            cleanupMessage = "Couldn't recover these videos — they may be damaged"
        }
        await loadStorageInfo()

        isCleaningUp = false
    }

    private func performCleanup() async {
        isCleaningUp = true
        cleanupMessage = nil

        let (filesDeleted, bytesFreed) = await StorageManager.cleanupOrphanedFiles(context: modelContext)

        if filesDeleted > 0 {
            cleanupMessage = "Deleted \(filesDeleted) file\(filesDeleted == 1 ? "" : "s"), freed \(StorageManager.formatBytes(bytesFreed))"
            Haptics.success()
            await loadStorageInfo()
        } else {
            cleanupMessage = "No files to clean up"
        }

        isCleaningUp = false
    }

    // MARK: - Formatting

    private func recordingTimeText(minutes: Int) -> String {
        if minutes >= 120 {
            return "~\(Int((Double(minutes) / 60).rounded())) hr"
        } else if minutes >= 60 {
            let remainder = minutes % 60
            return remainder == 0 ? "~1 hr" : "~1 hr \(remainder) min"
        }
        return "~\(minutes) min"
    }

    private func storageIcon(for level: StorageInfo.StorageLevel) -> String {
        switch level {
        case .good: return "internaldrive"
        case .moderate: return "internaldrive.fill"
        case .low: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }

    /// Bar + icon color. Healthy levels use the accent; only real problems get
    /// warning colors.
    private func storageColor(for level: StorageInfo.StorageLevel) -> Color {
        switch level {
        case .good, .moderate: return ppAccent
        case .low: return Theme.warning
        case .critical: return .red
        }
    }

    private func storageLabelColor(for level: StorageInfo.StorageLevel) -> Color {
        switch level {
        case .good, .moderate: return Theme.textPrimary
        case .low, .critical: return storageColor(for: level)
        }
    }

    private func storageLabel(for level: StorageInfo.StorageLevel, usedFraction: Double) -> String {
        switch level {
        case .good, .moderate: return "\(Int((usedFraction * 100).rounded()))% Full"
        case .low: return "Storage Low"
        case .critical: return "Storage Critical"
        }
    }
}

// MARK: - Usage Bar

private struct UsageBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.divider)
                Capsule()
                    .fill(color)
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 8)
    }
}
