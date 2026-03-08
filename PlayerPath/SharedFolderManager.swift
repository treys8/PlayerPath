//
//  SharedFolderManager.swift
//  PlayerPath
//
//  Created by Assistant on 11/21/25.
//  Business logic layer for coach folder sharing feature
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
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
    private var coachFoldersListener: ListenerRegistration?

    private init() {
        // Observe Firestore loading state
        firestore.$isLoading
            .assign(to: &$isLoading)
        
        firestore.$errorMessage
            .assign(to: &$errorMessage)
    }
    
    // MARK: - Athlete Functions
    
    /// Creates a new shared folder for an athlete (Coaching Add-On feature)
    /// - Parameters:
    ///   - name: Display name for the folder
    ///   - athleteID: Current user's athlete ID
    ///   - hasCoachingAccess: Whether user has coaching add-on + at least Plus tier
    /// - Returns: Created folder ID
    func createFolder(
        name: String,
        forAthlete athleteID: String,
        hasCoachingAccess: Bool
    ) async throws -> String {
        guard hasCoachingAccess else {
            throw SharedFolderError.coachingRequired
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

        // Fix P: Validate email format
        let emailRegex = "[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}"
        guard NSPredicate(format: "SELF MATCHES %@", emailRegex).evaluate(with: cleanEmail) else {
            throw SharedFolderError.invalidEmail
        }

        // Fix N: Guard against duplicate invitations for the same (folder, coach) pair
        let existingInvitations = try await firestore.fetchPendingInvitations(forEmail: cleanEmail)
        if existingInvitations.contains(where: { $0.folderID == folderID }) {
            throw SharedFolderError.duplicateInvitation
        }

        // Create invitation
        let invitationID = try await firestore.createInvitation(
            athleteID: athleteID,
            athleteName: athleteName,
            coachEmail: cleanEmail,
            folderID: folderID,
            folderName: folderName
        )
        
        print("✅ Created invitation \(invitationID) for \(cleanEmail)")

        // Notify the coach in-app if they already have an account
        if let coachUserID = await ActivityNotificationService.shared.lookupUserID(byEmail: cleanEmail) {
            await ActivityNotificationService.shared.postInvitationReceivedNotification(
                invitationID: invitationID,
                athleteID: athleteID,
                athleteName: athleteName,
                folderName: folderName,
                coachUserID: coachUserID
            )
        }
    }
    
    /// Removes a coach from a shared folder WITH NOTIFICATION
    /// - Parameters:
    ///   - coachID: Firebase user ID of the coach to remove
    ///   - coachEmail: Email of the coach (for local Coach model lookup)
    ///   - folderID: Folder to remove access from
    ///   - folderName: Display name of the folder (for notification)
    ///   - athleteID: Current athlete's ID (to update local coaches)
    func removeCoachAccess(
        coachID: String,
        coachEmail: String,
        fromFolder folderID: String,
        folderName: String,
        athleteID: String
    ) async throws {
        print("🚫 Removing coach \(coachID) from folder \(folderID)")

        // 1. Revoke permissions in Firestore — pass known values to skip 2 redundant reads
        try await firestore.removeCoachFromFolder(
            folderID: folderID,
            coachID: coachID,
            folderName: folderName,
            coachEmail: coachEmail,
            athleteID: athleteID
        )
        print("✅ Permissions revoked in Firestore")

        // 2. Send notification to coach (TODO: Implement push notification)
        await notifyCoachAccessRevoked(
            coachID: coachID,
            coachEmail: coachEmail,
            folderName: folderName,
            athleteID: athleteID
        )

        // 3. Refresh folders list
        if let currentUserID = Auth.auth().currentUser?.uid {
            try await loadAthleteFolders(athleteID: currentUserID)
        }

        print("✅ Coach removal completed")
    }

    /// Legacy method for backward compatibility
    func removeCoach(coachID: String, fromFolder folderID: String) async throws {
        try await firestore.removeCoachFromFolder(folderID: folderID, coachID: coachID)

        // Refresh folders list if needed
        if let currentUserID = Auth.auth().currentUser?.uid {
            try await loadAthleteFolders(athleteID: currentUserID)
        }
    }

    /// Sends notification to coach that their access was revoked
    private func notifyCoachAccessRevoked(
        coachID: String,
        coachEmail: String,
        folderName: String,
        athleteID: String
    ) async {
        // Notify coach in-app if they have an account
        // Fix O: Derive a readable name from email (UserProfile has no separate displayName field)
        let athleteName: String
        if let profile = try? await firestore.fetchUserProfile(userID: athleteID) {
            athleteName = profile.email.components(separatedBy: "@").first ?? profile.email
        } else {
            athleteName = "An athlete"
        }

        await ActivityNotificationService.shared.postAccessRevokedNotification(
            folderName: folderName,
            athleteID: athleteID,
            athleteName: athleteName,
            coachUserID: coachID
        )
    }
    
    /// Deletes a shared folder and all its contents WITH CASCADE
    /// - This will:
    ///   1. Revoke all coach permissions
    ///   2. Delete all videos and their storage files
    ///   3. Send notifications to affected coaches
    ///   4. Delete the folder document
    func deleteFolder(folderID: String, athleteID: String) async throws {
        print("🗑️ Starting cascade deletion for folder: \(folderID)")

        // 1. Get folder details before deletion
        guard let folder = athleteFolders.first(where: { $0.id == folderID }) else {
            throw SharedFolderError.folderNotFound
        }

        // 2. Revoke all coach permissions and notify them
        let affectedCoaches = folder.sharedWithCoachIDs
        for coachID in affectedCoaches {
            do {
                try await firestore.removeCoachFromFolder(folderID: folderID, coachID: coachID)
                // TODO: Send push notification to coach about folder deletion
                print("✅ Revoked access for coach: \(coachID)")
            } catch {
                print("⚠️ Failed to revoke access for coach \(coachID): \(error)")
            }
        }

        // 3. Delete all videos and their storage files
        do {
            let videos = try await firestore.fetchVideos(forFolder: folderID)
            print("📹 Found \(videos.count) videos to delete")

            for video in videos {
                // Delete from Firebase Storage using fileName, folderID
                do {
                    try await VideoCloudManager.shared.deleteVideo(fileName: video.fileName, folderID: folderID)
                    print("✅ Deleted storage file: \(video.fileName)")
                } catch {
                    print("⚠️ Failed to delete storage file \(video.fileName): \(error)")
                }

                // Delete metadata from Firestore
                if let videoID = video.id {
                    try await firestore.deleteVideo(videoID: videoID, folderID: folderID)
                }
            }
        } catch {
            print("⚠️ Error deleting videos: \(error)")
            // Continue with folder deletion even if video deletion fails
        }

        // 4. Delete the folder document
        try await firestore.deleteSharedFolder(folderID: folderID)

        // 5. Update local athlete's coaches if linked
        // This helps keep Coach model in sync
        await updateLocalCoaches(removingFolderID: folderID, forAthleteID: athleteID)

        // 6. Remove from local list
        athleteFolders.removeAll { $0.id == folderID }

        print("✅ Folder deletion cascade completed")
    }

    /// Updates local SwiftData coaches to remove folder access
    private func updateLocalCoaches(removingFolderID folderID: String, forAthleteID athleteID: String) async {
        // This would require access to SwiftData ModelContext
        // For now, we'll rely on the athlete's view to update local coaches
        print("💡 Reminder: Update local Coach models to remove folder \(folderID)")
    }
    
    /// Revokes all coach access from every folder owned by an athlete.
    /// Called when the 7-day coaching add-on grace period expires.
    func revokeAllCoachAccess(forAthleteID athleteID: String) async throws {
        print("⏰ Grace period expired — revoking all coach access for athlete: \(athleteID)")

        let folders = try await firestore.fetchSharedFolders(forAthlete: athleteID)

        for folder in folders {
            guard let folderID = folder.id, !folder.sharedWithCoachIDs.isEmpty else { continue }

            for coachID in folder.sharedWithCoachIDs {
                do {
                    try await firestore.removeCoachFromFolder(folderID: folderID, coachID: coachID)
                    await notifyCoachAccessRevoked(
                        coachID: coachID,
                        coachEmail: "",
                        folderName: folder.name,
                        athleteID: athleteID
                    )
                    print("✅ Revoked access for coach \(coachID) from folder \(folder.name)")
                } catch {
                    print("⚠️ Failed to revoke coach \(coachID) from folder \(folderID): \(error)")
                }
            }
        }

        // Refresh local folders list
        try await loadAthleteFolders(athleteID: athleteID)
        print("✅ All coach access revoked — grace period enforcement complete")
    }

    // MARK: - Coach Functions

    /// Starts a real-time Firestore listener for all folders shared with this coach.
    /// Replaces the one-shot loadCoachFolders fetch — UI auto-updates when folders change.
    func startCoachFoldersListener(coachID: String) {
        stopCoachFoldersListener()
        isLoading = true

        let db = Firestore.firestore()
        coachFoldersListener = db.collection("sharedFolders")
            .whereField("sharedWithCoachIDs", arrayContains: coachID)
            .order(by: "updatedAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                self.isLoading = false
                if let error {
                    print("❌ Coach folders listener error: \(error)")
                    return
                }
                guard let docs = snapshot?.documents else { return }
                let folders = docs.compactMap { doc -> SharedFolder? in
                    var folder = try? doc.data(as: SharedFolder.self)
                    folder?.id = doc.documentID
                    return folder
                }
                self.coachFolders = folders
            }
    }

    func stopCoachFoldersListener() {
        coachFoldersListener?.remove()
        coachFoldersListener = nil
    }

    /// Loads all folders shared with a coach (one-shot fetch, kept for backward compatibility)
    func loadCoachFolders(coachID: String) async throws {
        let folders = try await firestore.fetchSharedFolders(forCoach: coachID)
        coachFolders = folders
    }

    /// Verifies and refreshes permissions for a specific folder
    /// Returns updated folder with fresh permissions from Firestore
    /// Throws error if coach no longer has access
    func verifyFolderAccess(folderID: String, coachID: String) async throws -> SharedFolder {
        // Fetch latest folder data from Firestore
        guard let updatedFolder = try await firestore.fetchSharedFolder(folderID: folderID) else {
            throw SharedFolderError.folderNotFound
        }

        // Verify coach still has access
        guard updatedFolder.sharedWithCoachIDs.contains(coachID) else {
            throw SharedFolderError.accessRevoked
        }

        // Update local cache
        if let index = coachFolders.firstIndex(where: { $0.id == folderID }) {
            coachFolders[index] = updatedFolder
        }

        return updatedFolder
    }

    /// Checks for pending invitations when coach signs up
    func checkPendingInvitations(forEmail email: String) async throws -> [CoachInvitation] {
        return try await firestore.fetchPendingInvitations(forEmail: email)
    }
    
    /// Accepts an invitation to join a shared folder
    func acceptInvitation(_ invitation: CoachInvitation, authManager: ComprehensiveAuthManager? = nil) async throws {
        guard let invitationID = invitation.id,
              let coachID = Auth.auth().currentUser?.uid else {
            throw SharedFolderError.folderNotFound
        }

        // Enforce coach athlete limit before accepting
        let currentAthleteCount = Set(coachFolders.map { $0.ownerAthleteID }).count
        let limit = authManager?.coachAthleteLimit ?? Int.max
        if currentAthleteCount >= limit {
            throw SharedFolderError.coachAthleteLimitReached
        }

        // Use the permissions the athlete specified in the invitation, falling back to default.
        let permissions = invitation.permissions ?? .default

        try await firestore.acceptInvitation(
            invitationID: invitationID,
            coachID: coachID,
            permissions: permissions
        )

        // Refresh coach's folder list
        try await loadCoachFolders(coachID: coachID)

        // Notify the athlete that their coach accepted
        let coachName = Auth.auth().currentUser?.displayName
            ?? Auth.auth().currentUser?.email
            ?? "Your coach"
        await ActivityNotificationService.shared.postInvitationAcceptedNotification(
            folderName: invitation.folderName,
            coachID: coachID,
            coachName: coachName,
            athleteID: invitation.athleteID,
            folderID: invitation.folderID
        )
    }
    
    /// Declines an invitation
    func declineInvitation(_ invitation: CoachInvitation) async throws {
        guard let invitationID = invitation.id else {
            throw SharedFolderError.folderNotFound
        }
        try await firestore.declineInvitation(invitationID: invitationID)
    }
    
    /// Allows a coach to voluntarily leave a shared folder they have access to.
    /// Removes the coach from the folder's sharedWithCoachIDs and permissions,
    /// then removes the folder from the local coachFolders cache.
    func leaveFolder(folderID: String, coachID: String) async throws {
        try await firestore.removeCoachFromFolder(folderID: folderID, coachID: coachID)
        await MainActor.run {
            coachFolders.removeAll { $0.id == folderID }
        }
        print("✅ Coach \(coachID) left folder \(folderID)")
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
        uploadedByName: String,
        videoType: String = "game",
        gameContext: GameContext? = nil,
        practiceContext: PracticeContext? = nil
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
            duration: nil,
            videoType: videoType,
            gameContext: gameContext,
            practiceContext: practiceContext
        )

        // Notify all coaches with access to this folder
        if let folder = try? await firestore.fetchSharedFolder(folderID: folderID),
           !folder.sharedWithCoachIDs.isEmpty {
            await ActivityNotificationService.shared.postNewVideoNotification(
                folderID: folderID,
                folderName: folder.name,
                uploaderID: uploadedBy,
                uploaderName: uploadedByName,
                coachIDs: folder.sharedWithCoachIDs,
                videoFileName: fileName
            )
        }

        return videoID
    }
    
    /// Loads all videos in a folder
    func loadVideos(forFolder folderID: String) async throws -> [FirestoreVideoMetadata] {
        return try await firestore.fetchVideos(forFolder: folderID)
    }
    
    /// Deletes a video from a shared folder
    func deleteVideo(videoID: String, fromFolder folderID: String) async throws {
        // Point-read for single video metadata (1 read) instead of fetching the whole folder
        do {
            if let meta = try await firestore.fetchVideo(videoID: videoID) {
                if let _ = Auth.auth().currentUser?.uid {
                    try await VideoCloudManager.shared.deleteVideo(fileName: meta.fileName, folderID: folderID)
                } else {
                    print("⚠️ No authenticated user found; skipping storage deletion for video \(videoID)")
                }
            } else {
                print("⚠️ Could not find metadata for video \(videoID); skipping storage deletion")
            }
        } catch {
            print("⚠️ Error while attempting storage deletion for video \(videoID): \(error)")
        }

        // Then delete metadata from Firestore
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
    case premiumRequired      // legacy, keep for any existing references
    case coachingRequired
    case invalidName
    case invalidEmail
    case duplicateInvitation
    case emptyComment
    case insufficientPermissions
    case folderNotFound
    case accessRevoked
    case coachAthleteLimitReached

    var errorDescription: String? {
        switch self {
        case .premiumRequired:
            return "Plus or Pro subscription required to use coaching features"
        case .coachingRequired:
            return "Pro subscription required to create shared folders and invite coaches."
        case .invalidName:
            return "Please enter a valid folder name"
        case .invalidEmail:
            return "Please enter a valid email address"
        case .duplicateInvitation:
            return "This coach already has a pending invitation for this folder"
        case .emptyComment:
            return "Comment cannot be empty"
        case .insufficientPermissions:
            return "You don't have permission to perform this action"
        case .folderNotFound:
            return "Shared folder not found"
        case .accessRevoked:
            return "Your access to this folder has been revoked"
        case .coachAthleteLimitReached:
            return "You've reached your athlete limit. Upgrade your plan to add more athletes."
        }
    }
}

// NOTE: VideoCloudManager.uploadVideo() is now the single source of truth for uploads


