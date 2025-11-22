//
//  AthleteFoldersListView.swift
//  PlayerPath
//
//  Created by Assistant on 11/22/25.
//  Main view for athletes to see and manage their shared coach folders
//

import SwiftUI

/// Athlete's view of all their shared folders
struct AthleteFoldersListView: View {
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @StateObject private var folderManager = SharedFolderManager.shared
    
    @State private var showingCreateFolder = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        Group {
            if folderManager.isLoading {
                ProgressView("Loading folders...")
            } else if folderManager.athleteFolders.isEmpty {
                emptyState
            } else {
                foldersList
            }
        }
        .navigationTitle("Shared Folders")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCreateFolder = true
                    Haptics.light()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
        .sheet(isPresented: $showingCreateFolder) {
            CreateFolderView()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .task {
            await loadFolders()
        }
        .refreshable {
            await loadFolders()
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "folder.badge.person.crop")
                .font(.system(size: 72))
                .foregroundColor(.blue)
            
            Text("No Shared Folders Yet")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Create a folder to share videos with your coach. They'll be able to upload videos and provide feedback.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button {
                showingCreateFolder = true
                Haptics.light()
            } label: {
                Label("Create Folder", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    // MARK: - Folders List
    
    private var foldersList: some View {
        List {
            Section {
                ForEach(folderManager.athleteFolders) { folder in
                    NavigationLink(destination: AthleteFolderDetailView(folder: folder)) {
                        FolderRow(folder: folder)
                    }
                }
                .onDelete(perform: deleteFolders)
            } header: {
                Text("Your folders")
            } footer: {
                Text("Folders are shared with your coaches. They can view and upload videos based on the permissions you set.")
                    .font(.caption)
            }
        }
    }
    
    // MARK: - Actions
    
    private func loadFolders() async {
        guard let athleteID = authManager.userID else {
            errorMessage = "Not authenticated"
            showingError = true
            return
        }
        
        do {
            try await folderManager.loadAthleteFolders(athleteID: athleteID)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
    
    private func deleteFolders(at offsets: IndexSet) {
        for index in offsets {
            let folder = folderManager.athleteFolders[index]
            
            Task {
                do {
                    if let folderID = folder.id {
                        try await folderManager.deleteFolder(folderID: folderID)
                        Haptics.success()
                    }
                } catch {
                    errorMessage = "Failed to delete folder: \(error.localizedDescription)"
                    showingError = true
                    Haptics.error()
                }
            }
        }
    }
}

// MARK: - Folder Row

struct FolderRow: View {
    let folder: SharedFolder
    
    var body: some View {
        HStack(spacing: 16) {
            // Folder icon
            Image(systemName: "folder.fill")
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 44, height: 44)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Folder info
            VStack(alignment: .leading, spacing: 4) {
                Text(folder.name)
                    .font(.headline)
                
                HStack(spacing: 12) {
                    // Video count
                    Label("\(folder.videoCount ?? 0)", systemImage: "video.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Coach count
                    if !folder.sharedWithCoachIDs.isEmpty {
                        Label("\(folder.sharedWithCoachIDs.count)", systemImage: "person.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Last updated
                    if let updated = folder.updatedAt {
                        Text(updated, style: .relative)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Athlete Folder Detail View
// This view shows the same Games/Practices structure as the coach view

/// Detail view for athlete to manage their folder and see videos
struct AthleteFolderDetailView: View {
    let folder: SharedFolder
    
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @StateObject private var viewModel: CoachFolderViewModel
    @StateObject private var folderManager = SharedFolderManager.shared
    
    @State private var showingInviteCoach = false
    @State private var showingManageCoaches = false
    @State private var showingUploadSheet = false
    @State private var selectedTab: CoachFolderDetailView.FolderTab = .all
    
    init(folder: SharedFolder) {
        self.folder = folder
        _viewModel = StateObject(wrappedValue: CoachFolderViewModel(folder: folder))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with folder info
            folderHeader
            
            // Tab picker for Games / Practices / All
            Picker("View", selection: $selectedTab) {
                ForEach(CoachFolderDetailView.FolderTab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Content organized by category
            Group {
                switch selectedTab {
                case .games:
                    GamesTabView(folder: folder, videos: viewModel.gameVideos)
                case .practices:
                    PracticesTabView(folder: folder, videos: viewModel.practiceVideos)
                case .all:
                    AllVideosTabView(folder: folder, videos: viewModel.videos)
                }
            }
        }
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showingUploadSheet = true
                    } label: {
                        Label("Upload Video", systemImage: "plus.circle")
                    }
                    
                    Button {
                        showingInviteCoach = true
                    } label: {
                        Label("Invite Coach", systemImage: "person.badge.plus")
                    }
                    
                    Button {
                        showingManageCoaches = true
                    } label: {
                        Label("Manage Coaches", systemImage: "person.2.fill")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingInviteCoach) {
            InviteCoachView(folder: folder)
        }
        .sheet(isPresented: $showingManageCoaches) {
            ManageCoachesView(folder: folder)
        }
        .sheet(isPresented: $showingUploadSheet) {
            CoachVideoUploadView(folder: folder, selectedTab: selectedTab)
        }
        .task {
            await viewModel.loadVideos()
        }
        .refreshable {
            await viewModel.loadVideos()
        }
    }
    
    private var folderHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Image(systemName: "folder.fill")
                    .font(.title)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(folder.name)
                        .font(.headline)
                    
                    HStack(spacing: 12) {
                        Label("\(viewModel.videos.count) videos", systemImage: "video.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Label("\(folder.sharedWithCoachIDs.count) coaches", systemImage: "person.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding()
        }
        .background(Color(.secondarySystemBackground))
    }
}

// MARK: - Manage Coaches View

struct ManageCoachesView: View {
    let folder: SharedFolder
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: ComprehensiveAuthManager
    @StateObject private var folderManager = SharedFolderManager.shared
    
    @State private var showingRemoveConfirmation = false
    @State private var coachToRemove: String?
    
    var body: some View {
        NavigationStack {
            List {
                if folder.sharedWithCoachIDs.isEmpty {
                    ContentUnavailableView(
                        "No Coaches Yet",
                        systemImage: "person.2.slash",
                        description: Text("Invite coaches to share this folder with them.")
                    )
                } else {
                    Section {
                        ForEach(folder.sharedWithCoachIDs, id: \.self) { coachID in
                            CoachPermissionRow(
                                coachID: coachID,
                                permissions: folder.getPermissions(for: coachID) ?? .default,
                                onRemove: {
                                    coachToRemove = coachID
                                    showingRemoveConfirmation = true
                                }
                            )
                        }
                    } header: {
                        Text("Shared with")
                    } footer: {
                        Text("Coaches can view and interact with videos based on their permissions.")
                    }
                }
            }
            .navigationTitle("Manage Coaches")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Remove Coach", isPresented: $showingRemoveConfirmation) {
                Button("Cancel", role: .cancel) {
                    coachToRemove = nil
                }
                Button("Remove", role: .destructive) {
                    if let coachID = coachToRemove,
                       let folderID = folder.id {
                        Task {
                            try? await folderManager.removeCoach(
                                coachID: coachID,
                                fromFolder: folderID
                            )
                        }
                    }
                    coachToRemove = nil
                }
            } message: {
                Text("This coach will no longer have access to this folder and its videos.")
            }
        }
    }
}

// MARK: - Coach Permission Row

struct CoachPermissionRow: View {
    let coachID: String
    let permissions: FolderPermissions
    let onRemove: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "person.circle.fill")
                    .font(.title3)
                    .foregroundColor(.purple)
                
                Text("Coach") // TODO: Load actual coach name
                    .font(.headline)
                
                Spacer()
                
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.red)
                }
            }
            
            // Permissions
            HStack(spacing: 16) {
                PermissionBadge(
                    icon: "arrow.up.circle.fill",
                    title: "Upload",
                    enabled: permissions.canUpload
                )
                
                PermissionBadge(
                    icon: "text.bubble.fill",
                    title: "Comment",
                    enabled: permissions.canComment
                )
                
                PermissionBadge(
                    icon: "trash.fill",
                    title: "Delete",
                    enabled: permissions.canDelete
                )
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

struct PermissionBadge: View {
    let icon: String
    let title: String
    let enabled: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(title)
        }
        .foregroundColor(enabled ? .green : .secondary)
        .opacity(enabled ? 1.0 : 0.5)
    }
}

// MARK: - Preview

#Preview("Athlete Folders List") {
    NavigationStack {
        AthleteFoldersListView()
            .environmentObject(ComprehensiveAuthManager())
    }
}
