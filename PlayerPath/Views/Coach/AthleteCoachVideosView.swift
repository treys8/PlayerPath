//
//  AthleteCoachVideosView.swift
//  PlayerPath
//
//  Shows shared coach folder videos front-and-center for athletes.
//  Presented from the dashboard coach card.
//

import SwiftUI

struct AthleteCoachVideosView: View {
    let athlete: Athlete

    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    private var folderManager: SharedFolderManager { .shared }
    @State private var isLoading = true
    @State private var showingManageCoaches = false

    private var folders: [SharedFolder] { folderManager.athleteFolders }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading folders...")
            } else if folders.isEmpty {
                emptyState
            } else if folders.count == 1, let folder = folders.first {
                singleFolderView(folder)
            } else {
                multiFolderList
            }
        }
        .navigationTitle("Coach Videos")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingManageCoaches = true
                } label: {
                    Image(systemName: "person.2.fill")
                }
            }
        }
        .sheet(isPresented: $showingManageCoaches) {
            NavigationStack {
                CoachesView(athlete: athlete)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showingManageCoaches = false }
                        }
                    }
            }
        }
        .task {
            await loadFolders()
            markNotificationsRead()
        }
    }

    // MARK: - Single Folder (inline detail)

    @ViewBuilder
    private func singleFolderView(_ folder: SharedFolder) -> some View {
        if let athleteID = authManager.userID {
            AthleteFolderDetailContent(folder: folder, athleteID: athleteID)
        } else {
            ProgressView("Loading...")
        }
    }

    // MARK: - Multi Folder List

    private var multiFolderList: some View {
        List {
            ForEach(folders) { folder in
                NavigationLink(destination: AthleteFolderDetailView(folder: folder)) {
                    FolderRow(folder: folder)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await loadFolders()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "folder.badge.person.crop")
                .font(.system(size: 72))
                .foregroundColor(.brandNavy)

            Text("No Shared Folders Yet")
                .font(.title2)
                .fontWeight(.bold)

            Text("Connect with your coach to share game and lesson videos.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                showingManageCoaches = true
            } label: {
                Label("Manage Coaches", systemImage: "person.badge.plus")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Actions

    private func loadFolders() async {
        guard let athleteID = authManager.userID else { return }
        do {
            try await folderManager.loadAthleteFolders(athleteID: athleteID)
        } catch {
            ErrorHandlerService.shared.handle(error, context: "AthleteCoachVideosView.loadFolders", showAlert: false)
        }
        isLoading = false
    }

    private func markNotificationsRead() {
        guard let userID = authManager.userID else { return }
        Task {
            await ActivityNotificationService.shared.markFolderNotificationsRead(forUserID: userID)
        }
    }
}

