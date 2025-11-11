//
//  CloudProgressIndicatorView.swift
//  PlayerPath
//
//  Created by Assistant on 10/31/25.
//

import SwiftUI
import SwiftData
import Foundation

struct CloudProgressIndicatorView: View {
    let clip: VideoClip
    @StateObject private var cloudManager = VideoCloudManager()
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Main progress indicator
            Button(action: { 
                withAnimation(.spring()) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 12) {
                    cloudStatusIcon
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(cloudStatusText)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        if let progress = cloudManager.uploadProgress[clip.id] {
                            ProgressView(value: progress, total: 1.0)
                                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                                .frame(height: 4)
                            
                            Text("\(Int(progress * 100))% uploaded")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else if clip.isUploaded {
                            Text("Synced to cloud")
                                .font(.caption2)
                                .foregroundColor(.green)
                        } else if clip.needsUpload {
                            Text("Tap to upload")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        } else {
                            Text("Local only")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    if cloudManager.isUploading[clip.id] == true {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(cloudManager.isUploading[clip.id] == true)
            
            // Expanded details
            if isExpanded {
                VStack(spacing: 12) {
                    Divider()
                    
                    // Cloud actions
                    VStack(spacing: 8) {
                        if clip.needsUpload {
                            CloudActionButton(
                                title: "Upload to Cloud",
                                systemImage: "arrow.up.circle.fill",
                                color: .blue,
                                action: {
                                    Task {
                                        await uploadToCloud()
                                    }
                                }
                            )
                        }
                        
                        if clip.isUploaded && !clip.isAvailableOffline {
                            CloudActionButton(
                                title: "Download to Device",
                                systemImage: "arrow.down.circle.fill", 
                                color: .green,
                                action: {
                                    Task {
                                        await downloadFromCloud()
                                    }
                                }
                            )
                        }
                        
                        if clip.isUploaded && clip.isAvailableOffline {
                            CloudActionButton(
                                title: "Remove Local Copy",
                                systemImage: "trash.circle.fill",
                                color: .orange,
                                action: {
                                    removeLocalCopy()
                                }
                            )
                        }
                    }
                    
                    // Sync status details
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                                .font(.caption)
                            
                            Text("Sync Details")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            syncDetailRow("File Size", value: formatFileSize())
                            syncDetailRow("Local Storage", value: clip.isAvailableOffline ? "Available" : "Not Available")
                            syncDetailRow("Cloud Storage", value: clip.isUploaded ? "Uploaded" : "Not Uploaded")
                            
                            if let lastSync = clip.lastSyncDate {
                                syncDetailRow("Last Sync", value: formatLastSync(lastSync))
                            }
                        }
                        .padding(.leading, 20)
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 12)
                .background(Color(.systemGray6).opacity(0.5))
                .cornerRadius(12)
                .padding(.top, 2)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isExpanded)
    }
    
    private var cloudStatusIcon: some View {
        Group {
            if let progress = cloudManager.uploadProgress[clip.id] {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 3)
                        .frame(width: 24, height: 24)
                    
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.blue, lineWidth: 3)
                        .frame(width: 24, height: 24)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear, value: progress)
                }
            } else if clip.isUploaded && clip.isAvailableOffline {
                Image(systemName: "icloud.and.arrow.down.fill")
                    .foregroundColor(.green)
                    .font(.title3)
            } else if clip.isUploaded {
                Image(systemName: "icloud.fill")
                    .foregroundColor(.blue)
                    .font(.title3)
            } else if clip.needsUpload {
                Image(systemName: "icloud.and.arrow.up")
                    .foregroundColor(.orange)
                    .font(.title3)
            } else {
                Image(systemName: "externaldrive.fill")
                    .foregroundColor(.gray)
                    .font(.title3)
            }
        }
    }
    
    private var cloudStatusText: String {
        if cloudManager.isUploading[clip.id] == true {
            return "Uploading..."
        } else if clip.isUploaded && clip.isAvailableOffline {
            return "Available Offline"
        } else if clip.isUploaded {
            return "In Cloud"
        } else if clip.needsUpload {
            return "Ready to Upload"
        } else {
            return "Local Only"
        }
    }
    
    private func syncDetailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.caption2)
                .foregroundColor(.primary)
        }
    }
    
    private func uploadToCloud() async {
        guard let athlete = clip.athlete else { return }
        
        do {
            cloudManager.isUploading[clip.id] = true
            let cloudURL = try await cloudManager.uploadVideo(clip, athlete: athlete)
            
            await MainActor.run {
                clip.cloudURL = cloudURL
                clip.isUploaded = true
                clip.lastSyncDate = Date()
                cloudManager.isUploading[clip.id] = false
                cloudManager.uploadProgress[clip.id] = nil
            }
            
        } catch {
            await MainActor.run {
                cloudManager.isUploading[clip.id] = false
                cloudManager.uploadProgress[clip.id] = nil
            }
            print("Failed to upload video: \(error)")
        }
    }
    
    private func downloadFromCloud() async {
        guard let cloudURL = clip.cloudURL else { return }
        
        do {
            try await cloudManager.downloadVideo(from: cloudURL, to: clip.filePath)
            
            await MainActor.run {
                clip.lastSyncDate = Date()
            }
            
        } catch {
            print("Failed to download video: \(error)")
        }
    }
    
    private func removeLocalCopy() {
        if FileManager.default.fileExists(atPath: clip.filePath) {
            try? FileManager.default.removeItem(atPath: clip.filePath)
        }
    }
    
    private func formatFileSize() -> String {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: clip.filePath)
            if let fileSize = attributes[.size] as? Int64 {
                return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
            }
        } catch {
            // File doesn't exist locally
        }
        
        return "Unknown"
    }
    
    private func formatLastSync(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct CloudActionButton: View {
    let title: String
    let systemImage: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundColor(color)
                
                Text(title)
                    .fontWeight(.medium)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(color.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Cloud Progress List View

struct CloudProgressListView: View {
    @StateObject private var cloudManager = VideoCloudManager()
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<VideoClip> { !$0.isUploaded }, sort: \VideoClip.createdAt, order: .reverse)
    private var pendingUploads: [VideoClip]
    
    var body: some View {
        NavigationStack {
            List {
                if !pendingUploads.isEmpty {
                    Section("Pending Uploads") {
                        ForEach(pendingUploads) { clip in
                            CloudProgressRow(clip: clip, cloudManager: cloudManager)
                        }
                    }
                }
                
                Section("Upload Options") {
                    Button("Upload All Highlights") {
                        Task {
                            await uploadAllHighlights()
                        }
                    }
                    .disabled(pendingHighlights.isEmpty)
                    
                    Button("Upload All Videos") {
                        Task {
                            await uploadAllVideos()
                        }
                    }
                    .disabled(pendingUploads.isEmpty)
                }
            }
            .navigationTitle("Cloud Storage")
            .refreshable {
                // Refresh cloud status
            }
        }
    }
    
    private var pendingHighlights: [VideoClip] {
        pendingUploads.filter { $0.isHighlight }
    }
    
    private func uploadAllHighlights() async {
        for clip in pendingHighlights {
            guard let athlete = clip.athlete else { continue }
            
            do {
                cloudManager.isUploading[clip.id] = true
                let cloudURL = try await cloudManager.uploadVideo(clip, athlete: athlete)
                
                await MainActor.run {
                    clip.cloudURL = cloudURL
                    clip.isUploaded = true
                    clip.lastSyncDate = Date()
                    cloudManager.isUploading[clip.id] = false
                }
            } catch {
                await MainActor.run {
                    cloudManager.isUploading[clip.id] = false
                }
                print("Failed to upload highlight: \(error)")
            }
        }
        
        // Save changes
        do {
            try modelContext.save()
        } catch {
            print("Failed to save upload changes: \(error)")
        }
    }
    
    private func uploadAllVideos() async {
        for clip in pendingUploads {
            guard let athlete = clip.athlete else { continue }
            
            do {
                cloudManager.isUploading[clip.id] = true
                let cloudURL = try await cloudManager.uploadVideo(clip, athlete: athlete)
                
                await MainActor.run {
                    clip.cloudURL = cloudURL
                    clip.isUploaded = true
                    clip.lastSyncDate = Date()
                    cloudManager.isUploading[clip.id] = false
                }
            } catch {
                await MainActor.run {
                    cloudManager.isUploading[clip.id] = false
                }
                print("Failed to upload video: \(error)")
            }
        }
        
        // Save changes
        do {
            try modelContext.save()
        } catch {
            print("Failed to save upload changes: \(error)")
        }
    }
}

struct CloudProgressRow: View {
    let clip: VideoClip
    @ObservedObject var cloudManager: VideoCloudManager
    
    var body: some View {
        HStack {
            // Thumbnail
            AsyncImage(url: clip.thumbnailPath.map { URL(fileURLWithPath: $0) }) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 50, height: 38)
                    .clipped()
                    .cornerRadius(6)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 38)
                    .cornerRadius(6)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                if let playResult = clip.playResult {
                    Text(playResult.type.rawValue)
                        .font(.subheadline)
                        .fontWeight(.medium)
                } else {
                    Text("Practice Clip")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                if let progress = cloudManager.uploadProgress[clip.id] {
                    HStack(spacing: 8) {
                        ProgressView(value: progress, total: 1.0)
                            .frame(height: 4)
                        
                        Text("\(Int(progress * 100))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 35, alignment: .trailing)
                    }
                } else if cloudManager.isUploading[clip.id] == true {
                    HStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                            .scaleEffect(0.6)
                        
                        Text("Starting upload...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Ready to upload")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            Spacer()
            
            if cloudManager.isUploading[clip.id] != true {
                Button("Upload") {
                    Task {
                        await uploadClip()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .opacity(cloudManager.isUploading[clip.id] == true ? 0.6 : 1.0)
    }
    
    private func uploadClip() async {
        guard let athlete = clip.athlete else { return }
        
        do {
            cloudManager.isUploading[clip.id] = true
            let cloudURL = try await cloudManager.uploadVideo(clip, athlete: athlete)
            
            await MainActor.run {
                clip.cloudURL = cloudURL
                clip.isUploaded = true
                clip.lastSyncDate = Date()
                cloudManager.isUploading[clip.id] = false
                cloudManager.uploadProgress[clip.id] = nil
            }
            
        } catch {
            await MainActor.run {
                cloudManager.isUploading[clip.id] = false
                cloudManager.uploadProgress[clip.id] = nil
            }
            print("Failed to upload video: \(error)")
        }
    }
}

#Preview {
    CloudProgressListView()
}