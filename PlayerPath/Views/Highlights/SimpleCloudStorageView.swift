//
//  SimpleCloudStorageView.swift
//  PlayerPath
//
//  Cloud storage management view for uploading pending videos.
//

import SwiftUI
import SwiftData

// MARK: - Simple Cloud Storage View
struct SimpleCloudStorageView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var pendingUploads: [VideoClip]

    @State private var uploadingClips = Set<UUID>()
    @State private var isBulkUploading = false
    @State private var uploadErrors: [UUID: String] = [:]

    init() {
        self._pendingUploads = Query(
            filter: #Predicate<VideoClip> { !$0.isUploaded && $0.cloudURL == nil },
            sort: [SortDescriptor(\VideoClip.createdAt, order: .reverse)]
        )
    }

    var body: some View {
        List {
            if pendingUploads.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.icloud")
                            .font(.system(size: 50))
                            .foregroundColor(.green)

                        Text("All videos are up to date")
                            .font(.title3)
                            .fontWeight(.medium)

                        Text("Your highlights and videos are synchronized with cloud storage.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .listRowBackground(Color.clear)
                } else {
                    Section("Videos Ready to Upload") {
                        ForEach(pendingUploads) { clip in
                            HStack {
                                // Thumbnail placeholder
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 50, height: 38)
                                    .overlay(
                                        Image(systemName: "video.fill")
                                            .foregroundColor(.gray)
                                    )

                                VStack(alignment: .leading, spacing: 4) {
                                    if let playResult = clip.playResult {
                                        Text(playResult.type.displayName)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                    } else {
                                        Text(clip.fileName)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                    }

                                    if let game = clip.game {
                                        Text("vs \(game.opponent)")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    } else {
                                        Text("Practice")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    }
                                }

                                Spacer()

                                if uploadingClips.contains(clip.id) {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Button("Upload") {
                                        Task {
                                            await uploadClip(clip)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }

                                if let error = uploadErrors[clip.id] {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                        .help(error)
                                }
                            }
                        }
                    }

                    Section {
                        Button {
                            Task {
                                await uploadAll()
                            }
                        } label: {
                            HStack {
                                if isBulkUploading {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Uploading...")
                                } else {
                                    Text("Upload All Videos (\(pendingUploads.count))")
                                }
                            }
                        }
                        .disabled(pendingUploads.isEmpty || isBulkUploading)
                    }
                }
            }
            .navigationTitle("Cloud Storage")
            .navigationBarTitleDisplayMode(.large)
    }

    private func uploadClip(_ clip: VideoClip) async {
        guard let athlete = clip.athlete else {
            uploadErrors[clip.id] = "No athlete associated with clip"
            return
        }

        uploadingClips.insert(clip.id)
        uploadErrors.removeValue(forKey: clip.id)

        do {
            let cloudURL = try await VideoCloudManager.shared.uploadVideo(clip, athlete: athlete)

            await MainActor.run {
                clip.cloudURL = cloudURL
                clip.isUploaded = true
                clip.lastSyncDate = Date()
                if let user = athlete.user {
                    let fileSize = (try? FileManager.default.attributesOfItem(atPath: clip.resolvedFilePath)[.size] as? Int64) ?? 0
                    user.cloudStorageUsedBytes += fileSize
                }

                do {
                    try modelContext.save()
                } catch {
                    uploadErrors[clip.id] = "Failed to save: \(error.localizedDescription)"
                }

                uploadingClips.remove(clip.id)
            }
        } catch {
            await MainActor.run {
                uploadErrors[clip.id] = error.localizedDescription
                uploadingClips.remove(clip.id)
            }
        }
    }

    private func uploadAll() async {
        isBulkUploading = true
        uploadErrors.removeAll()

        // Upload clips in parallel (max 3 concurrent uploads)
        await withTaskGroup(of: Void.self) { group in
            var activeUploads = 0
            var clipIndex = 0
            let maxConcurrent = 3

            // Start initial batch
            while clipIndex < pendingUploads.count && activeUploads < maxConcurrent {
                let clip = pendingUploads[clipIndex]
                group.addTask {
                    await uploadClip(clip)
                }
                activeUploads += 1
                clipIndex += 1
            }

            // As tasks complete, start new ones
            for await _ in group {
                if clipIndex < pendingUploads.count {
                    let clip = pendingUploads[clipIndex]
                    group.addTask {
                        await uploadClip(clip)
                    }
                    clipIndex += 1
                }
            }
        }

        await MainActor.run {
            isBulkUploading = false
        }
    }
}

// DateFormatter.shortDate is defined in DateFormatters.swift
