//
//  CoachRecordingsTab.swift
//  PlayerPath
//
//  Dedicated Recordings tab for coaches. Shows all private recordings
//  across all athletes/folders, grouped by date.
//

import SwiftUI

struct CoachRecordingsTab: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @EnvironmentObject private var sharedFolderManager: SharedFolderManager
    @StateObject private var viewModel = CoachRecordingsViewModel()
    @State private var showingQuickRecord = false
    @State private var videoToDelete: CoachRecordingItem?
    @State private var showingDeleteConfirmation = false
    @State private var videoToMove: CoachRecordingItem?
    @State private var showingMoveAndTag = false

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.groupedRecordings.isEmpty {
                VStack {
                    Spacer()
                    ProgressView("Loading recordings...")
                    Spacer()
                }
            } else if viewModel.groupedRecordings.isEmpty {
                emptyState
            } else {
                recordingsList
            }
        }
        .navigationTitle("Recordings")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Haptics.medium()
                    showingQuickRecord = true
                } label: {
                    Image(systemName: "video.fill.badge.plus")
                        .foregroundColor(.green)
                }
            }
        }
        .task {
            guard let coachID = authManager.userID else { return }
            await viewModel.loadAllRecordings(coachID: coachID, folders: sharedFolderManager.coachFolders)
        }
        .onChange(of: sharedFolderManager.coachFolders) { _, folders in
            guard let coachID = authManager.userID else { return }
            Task {
                await viewModel.loadAllRecordings(coachID: coachID, folders: folders)
            }
        }
        .refreshable {
            guard let coachID = authManager.userID else { return }
            await viewModel.loadAllRecordings(coachID: coachID, folders: sharedFolderManager.coachFolders)
        }
        .fullScreenCover(isPresented: $showingQuickRecord) {
            CoachQuickRecordFlow()
        }
        .alert("Delete Recording", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let item = videoToDelete {
                    Task { await viewModel.deleteVideo(item) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This recording will be permanently deleted.")
        }
        .sheet(isPresented: $showingMoveAndTag) {
            if let item = videoToMove {
                MoveAndTagSheet(item: item) { tags, drillType in
                    Task { await viewModel.moveToSharedFolder(item, tags: tags, drillType: drillType) }
                }
            }
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onAppear {
            AnalyticsService.shared.trackScreenView(screenName: "Coach Recordings", screenClass: "CoachRecordingsTab")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "video.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))

            Text("No Recordings Yet")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Record practice videos for your athletes. Review them here before sharing.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                Haptics.medium()
                showingQuickRecord = true
            } label: {
                Label("Record Video", systemImage: "video.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .padding()
    }

    // MARK: - Recordings List

    private var recordingsList: some View {
        List {
            ForEach(viewModel.groupedRecordings, id: \.date) { group in
                Section {
                    ForEach(group.recordings) { item in
                        if let folder = sharedFolderManager.coachFolders.first(where: { $0.id == item.sharedFolderID }) {
                            NavigationLink(destination: CoachVideoPlayerView(
                                folder: folder,
                                video: CoachVideoItem(from: item.video, sharedFolderID: item.sharedFolderID)
                            )) {
                                CoachRecordingRow(
                                    item: item,
                                    onMove: {
                                        videoToMove = item
                                        showingMoveAndTag = true
                                    },
                                    onDelete: {
                                        videoToDelete = item
                                        showingDeleteConfirmation = true
                                    }
                                )
                            }
                            .buttonStyle(.plain)
                        } else {
                            CoachRecordingRow(
                                item: item,
                                onMove: {
                                    videoToMove = item
                                    showingMoveAndTag = true
                                },
                                onDelete: {
                                    videoToDelete = item
                                    showingDeleteConfirmation = true
                                }
                            )
                        }
                    }
                } header: {
                    Text(group.date, style: .date)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}
