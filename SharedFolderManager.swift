//
//  SharedFolderManager.swift
//  PlayerPath
//
//  Created by Assistant on 11/21/25.
//  Business logic layer for coach folder sharing feature
//

import Foundation
import FirebaseAuth
import Combine

/// High-level business logic for managing shared folders
/// Coordinates between Firestore, Storage, and app state
@MainActor
class SharedFolderManager: ObservableObject {
    
    static let shared = SharedFolderManager()
    
    private let firestore = FirestoreManager.shared
    
    // Published state for UI
    @Published var athleteFolders: [SharedFolder] = []
    @Published var coachFolders: [SharedFolder] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Observe Firestore loading state
        firestore.$isLoading
            .assign(to: &$isLoading)
        
        firestore.$errorMessage
            .assign(to: &$errorMessage)
    }
    
    // MARK: - Athlete Functions
    
    /// Creates a new shared folder for an athlete (Premium feature)
    /// - Parameters:
    ///   - name: Display name for the folder
    ///   - athleteID: Current user's athlete ID
    ///   - isPremium: Whether user has premium subscription
    /// - Returns: Created folder ID
    func createFolder(
        name: String,
        forAthlete athleteID: String,
        isPremium: Bool
    ) async throws -> String {
        guard isPremium else {
            throw SharedFolderError.premiumRequired
        }
        
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SharedFolderError.invalidName
        }
        
        let folderID = try await firestore.createSharedFolder(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            ownerAthleteID: athleteID,
            permissions: [:]
        )
        
        // Refresh folders list
        try await loadAthleteFolders(athleteID: athleteID)
        
        return folderID
    }
    
    /// Loads all folders owned by an athlete
    func loadAthleteFolders(athleteID: String) async throws {
        let folders = try await firestore.fetchSharedFolders(forAthlete: athleteID)
        athleteFolders = folders
    }
    
    /// Invites a coach to a shared folder via email
    /// - Parameters:
    ///   - coachEmail: Coach's email address
    ///   - folderID: Folder to share
    ///   - athleteID: Current athlete's ID
    ///   - athleteName: Current athlete's display name
    ///   - folderName: Name of the folder being shared
    ///   - permissions: What the coach can do
    func inviteCoachToFolder(
        coachEmail: String,
        folderID: String,
        athleteID: String,
        athleteName: String,
        folderName: String,
        permissions: FolderPermissions
    ) async throws {
        guard !coachEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SharedFolderError.invalidEmail
        }
        
        let cleanEmail = coachEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Create invitation
        let invitationID = try await firestore.createInvitation(
            athleteID: athleteID,
            athleteName: athleteName,
            coachEmail: cleanEmail,
            folderID: folderID,
            folderName: folderName
        )
        
        print("✅ Created invitation \(invitationID) for \(cleanEmail)")
        
        // TODO: Send email notification via Cloud Function or external service
        // For now, coach will see pending invitations when they sign up
    }
    
    /// Removes a coach from a shared folder
    func removeCoach(coachID: String, fromFolder folderID: String) async throws {
        try await firestore.removeCoachFromFolder(folderID: folderID, coachID: coachID)
        
        // Refresh folders list if needed
        if let currentUserID = Auth.auth().currentUser?.uid {
            try await loadAthleteFolders(athleteID: currentUserID)
        }
    }
    
    /// Deletes a shared folder and all its contents
    func deleteFolder(folderID: String) async throws {
        try await firestore.deleteSharedFolder(folderID: folderID)
        
        // Remove from local list
        athleteFolders.removeAll { $0.id == folderID }
    }
    
    // MARK: - Coach Functions
    
    /// Loads all folders shared with a coach
    func loadCoachFolders(coachID: String) async throws {
        let folders = try await firestore.fetchSharedFolders(forCoach: coachID)
        coachFolders = folders
    }
    
    /// Checks for pending invitations when coach signs up
    func checkPendingInvitations(forEmail email: String) async throws -> [CoachInvitation] {
        return try await firestore.fetchPendingInvitations(forEmail: email)
    }
    
    /// Accepts an invitation to join a shared folder
    func acceptInvitation(_ invitation: CoachInvitation) async throws {
        guard let invitationID = invitation.id,
              let coachID = Auth.auth().currentUser?.uid else {
            throw SharedFolderError.folderNotFound
        }
        
        let permissions = FolderPermissions.default
        
        try await firestore.acceptInvitation(
            invitationID: invitationID,
            coachID: coachID,
            permissions: permissions
        )
        
        // Refresh coach's folder list
        try await loadCoachFolders(coachID: coachID)
    }
    
    /// Declines an invitation
    func declineInvitation(_ invitation: CoachInvitation) async throws {
        guard let invitationID = invitation.id else {
            throw SharedFolderError.folderNotFound
        }
        try await firestore.declineInvitation(invitationID: invitationID)
    }
    
    // MARK: - Video Management
    
    /// Uploads a video to a shared folder
    /// - Parameters:
    ///   - videoURL: Local file URL of the video
    ///   - fileName: Display name for the video
    ///   - folderID: Target shared folder
    ///   - uploadedBy: User ID of uploader
    ///   - uploadedByName: Display name of uploader
    /// - Returns: Video metadata ID
    func uploadVideo(
        from videoURL: URL,
        fileName: String,
        toFolder folderID: String,
        uploadedBy: String,
        uploadedByName: String
    ) async throws -> String {
        // First, upload to Firebase Storage using the REAL implementation
        let storageURL = try await VideoCloudManager.shared.uploadVideo(
            localURL: videoURL,
            fileName: fileName,
            folderID: folderID,
            progressHandler: { progress in
                // Progress is already published by VideoCloudManager
                print("Upload progress: \(Int(progress * 100))%")
            }
        )
        
        // Get file size
        let fileSize: Int64
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: videoURL.path)
            fileSize = attributes[.size] as? Int64 ?? 0
        } catch {
            print("⚠️ Failed to get file size: \(error)")
            fileSize = 0
        }
        
        // TODO: Get video duration from AVAsset
        
        // Generate thumbnail (TODO: Implement thumbnail generation)
        let thumbnail: ThumbnailMetadata? = nil
        
        // Upload metadata to Firestore
        let videoID = try await firestore.uploadVideoMetadata(
            fileName: fileName,
            storageURL: storageURL,
            thumbnail: thumbnail,
            folderID: folderID,
            uploadedBy: uploadedBy,
            uploadedByName: uploadedByName,
            fileSize: fileSize,
            duration: nil
        )
        
        return videoID
    }
    
    /// Loads all videos in a folder
    func loadVideos(forFolder folderID: String) async throws -> [FirestoreVideoMetadata] {
        return try await firestore.fetchVideos(forFolder: folderID)
    }
    
    /// Deletes a video from a shared folder
    func deleteVideo(videoID: String, fromFolder folderID: String) async throws {
        // TODO: Delete from Firebase Storage as well
        try await firestore.deleteVideo(videoID: videoID, folderID: folderID)
    }
    
    // MARK: - Annotations
    
    /// Adds a comment to a video
    func addComment(
        to videoID: String,
        text: String,
        atTimestamp timestamp: Double,
        byUser userID: String,
        userName: String,
        isCoach: Bool
    ) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SharedFolderError.emptyComment
        }
        
        return try await firestore.addAnnotation(
            videoID: videoID,
            userID: userID,
            userName: userName,
            timestamp: timestamp,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            isCoachComment: isCoach
        )
    }
    
    /// Loads all comments for a video
    func loadComments(forVideo videoID: String) async throws -> [VideoAnnotation] {
        return try await firestore.fetchAnnotations(forVideo: videoID)
    }
    
    /// Deletes a comment (user can only delete their own)
    func deleteComment(videoID: String, annotationID: String, userID: String) async throws {
        // TODO: Add server-side validation that userID matches annotation owner
        try await firestore.deleteAnnotation(videoID: videoID, annotationID: annotationID)
    }
    
    // MARK: - Permissions Helper
    
    /// Checks if a user can perform an action on a folder
    func checkPermission(
        userID: String,
        action: FolderAction,
        onFolder folder: SharedFolder
    ) -> Bool {
        // Owner can do everything
        if folder.ownerAthleteID == userID {
            return true
        }
        
        // Check coach permissions
        guard let permissions = folder.getPermissions(for: userID) else {
            return false
        }
        
        switch action {
        case .upload:
            return permissions.canUpload
        case .comment:
            return permissions.canComment
        case .delete:
            return permissions.canDelete
        case .view:
            return true // If they have access to the folder, they can view
        }
    }
}

// MARK: - Supporting Types

enum FolderAction {
    case view
    case upload
    case comment
    case delete
}

enum SharedFolderError: LocalizedError {
    case premiumRequired
    case invalidName
    case invalidEmail
    case emptyComment
    case insufficientPermissions
    case folderNotFound
    
    var errorDescription: String? {
        switch self {
        case .premiumRequired:
            return "Premium subscription required to create shared folders"
        case .invalidName:
            return "Please enter a valid folder name"
        case .invalidEmail:
            return "Please enter a valid email address"
        case .emptyComment:
            return "Comment cannot be empty"
        case .insufficientPermissions:
            return "You don't have permission to perform this action"
        case .folderNotFound:
            return "Shared folder not found"
        }
    }
}

// NOTE: VideoCloudManager.uploadVideo() is now the single source of truth for uploads
