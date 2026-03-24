//
//  SharedFolderManager.swift
//  PlayerPath
//
//  Created by Assistant on 11/21/25.
//  Business logic layer for coach folder sharing feature
//

import Foundation
import AVFoundation
import CoreMedia
import FirebaseAuth
import FirebaseFirestore
import os

private let folderLog = Logger(subsystem: "com.playerpath.app", category: "SharedFolder")

/// High-level business logic for managing shared folders
/// Coordinates between Firestore, Storage, and app state
@MainActor
@Observable
class SharedFolderManager {

    static let shared = SharedFolderManager()

    private let firestore = FirestoreManager.shared

    var athleteFolders: [SharedFolder] = []
    var coachFolders: [SharedFolder] = []
    var isLoading = false
    var errorMessage: String?
    /// Set when a real-time listener encounters an error (e.g. offline, permissions).
    /// Views can display a "data may be stale" indicator when this is non-nil.
    var listenerError: String?

    private var coachFoldersListener: ListenerRegistration?

    private init() {}
    
    // MARK: - Athlete Functions
    
    /// Creates a new shared folder for an athlete (Coaching Add-On feature)
    /// - Parameters:
    ///   - name: Display name for the folder
    ///   - athleteID: Current user's athlete ID
    ///   - athleteName: Display name of the athlete (shown to coaches)
    ///   - hasCoachingAccess: Whether user has coaching add-on + at least Plus tier
    /// - Returns: Created folder ID
    func createFolder(
        name: String,
        forAthlete athleteID: String,
        athleteName: String? = nil,
        hasCoachingAccess: Bool
    ) async throws -> String {
        // Verify tier server-side rather than trusting the caller's boolean alone
        guard hasCoachingAccess, StoreKitManager.shared.currentTier >= .pro else {
            throw SharedFolderError.coachingRequired
        }

        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SharedFolderError.invalidName
        }

        folderLog.debug("createFolder: ownerAthleteID=\(athleteID), authUID=\(Auth.auth().currentUser?.uid ?? "nil")")
        let folderID = try await firestore.createSharedFolder(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            ownerAthleteID: athleteID,
            ownerAthleteName: athleteName,
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

        guard cleanEmail.isValidEmail else {
            throw SharedFolderError.invalidEmail
        }

        // Fix N: Guard against duplicate invitations for the same (folder, coach) pair
        if try await firestore.hasPendingInvitation(athleteID: athleteID, coachEmail: cleanEmail) {
            throw SharedFolderError.duplicateInvitation
        }

        // Create invitation
        let invitationID = try await firestore.createInvitation(
            athleteID: athleteID,
            athleteName: athleteName,
            coachEmail: cleanEmail,
            folderID: folderID,
            folderName: folderName,
            permissions: permissions
        )
        

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

        // 1. Revoke permissions in Firestore — pass known values to skip 2 redundant reads
        try await firestore.removeCoachFromFolder(
            folderID: folderID,
            coachID: coachID,
            folderName: folderName,
            coachEmail: coachEmail,
            athleteID: athleteID
        )

        // 2. Send notification to coach (TODO: Implement push notification)
        await notifyCoachAccessRevoked(
            coachID: coachID,
            coachEmail: coachEmail,
            folderID: folderID,
            folderName: folderName,
            athleteID: athleteID
        )

        // 3. End any active coach session for this folder
        await CoachSessionManager.shared.endSessionIfActive(forFolderID: folderID)

        // 4. Refresh folders list
        if let currentUserID = Auth.auth().currentUser?.uid {
            try await loadAthleteFolders(athleteID: currentUserID)
        }

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
        folderID: String,
        folderName: String,
        athleteID: String,
        athleteName: String? = nil
    ) async {
        // Use provided name, or fetch display name from user profile
        let resolvedAthleteName: String
        if let athleteName, !athleteName.isEmpty {
            resolvedAthleteName = athleteName
        } else if let profile = try? await firestore.fetchUserProfile(userID: athleteID) { // Best-effort: fall through to default name on failure
            // UserProfile doesn't have a separate displayName field —
            // use Firebase Auth displayName or derive from email
            let name = Auth.auth().currentUser?.displayName
                ?? profile.email.components(separatedBy: "@").first
                ?? profile.email
            resolvedAthleteName = name
        } else {
            resolvedAthleteName = "An athlete"
        }

        await ActivityNotificationService.shared.postAccessRevokedNotification(
            folderID: folderID,
            folderName: folderName,
            athleteID: athleteID,
            athleteName: resolvedAthleteName,
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

        // 0. End any active coach sessions for this folder
        await CoachSessionManager.shared.endSessionIfActive(forFolderID: folderID)

        // 1. Get folder details before deletion
        guard let folder = athleteFolders.first(where: { $0.id == folderID }) else {
            throw SharedFolderError.folderNotFound
        }

        var cleanupErrors: [String] = []

        // 2. Revoke all coach permissions
        for coachID in folder.sharedWithCoachIDs {
            do {
                try await firestore.removeCoachFromFolder(folderID: folderID, coachID: coachID)
            } catch {
                cleanupErrors.append("Coach \(coachID) revocation: \(error.localizedDescription)")
                folderLog.error("Failed to revoke coach \(coachID) access during folder deletion: \(error.localizedDescription)")
            }
        }

        // 2b. Notify revoked coaches in-app
        for coachID in folder.sharedWithCoachIDs {
            await notifyCoachAccessRevoked(
                coachID: coachID,
                coachEmail: "",
                folderID: folderID,
                folderName: folder.name,
                athleteID: athleteID
            )
        }

        // 3. Delete all videos and their storage files
        do {
            let videos = try await firestore.fetchVideos(forFolder: folderID)

            for video in videos {
                do {
                    try await VideoCloudManager.shared.deleteVideo(fileName: video.fileName, folderID: folderID)
                } catch {
                    cleanupErrors.append("Storage file \(video.fileName): \(error.localizedDescription)")
                    folderLog.warning("Failed to delete video storage file \(video.fileName): \(error.localizedDescription)")
                }

                if let videoID = video.id {
                    do {
                        try await firestore.deleteVideo(videoID: videoID, folderID: folderID)
                    } catch {
                        cleanupErrors.append("Video metadata \(videoID): \(error.localizedDescription)")
                        folderLog.warning("Failed to delete video metadata \(videoID): \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            cleanupErrors.append("Video fetch: \(error.localizedDescription)")
            folderLog.warning("Failed to fetch folder videos during cleanup: \(error.localizedDescription)")
        }

        // 4. Delete the folder document (skip video cleanup — already handled above)
        try await firestore.deleteSharedFolder(folderID: folderID, skipVideoCleanup: true)

        // 5. Remove from local list
        athleteFolders.removeAll { $0.id == folderID }

        // 6. Report partial cleanup failure if any
        if !cleanupErrors.isEmpty {
            folderLog.warning("Folder \(folderID) deleted with \(cleanupErrors.count) cleanup errors")
            ErrorHandlerService.shared.handle(
                NSError(domain: "SharedFolderManager", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Folder deleted but \(cleanupErrors.count) resource(s) could not be cleaned up."]),
                context: "SharedFolderManager.deleteFolder",
                showAlert: false
            )
        }
    }

    /// Revokes all coach access from every folder owned by an athlete.
    /// Called when the 7-day coaching add-on grace period expires.
    func revokeAllCoachAccess(forAthleteID athleteID: String) async throws {

        let folders = try await firestore.fetchSharedFolders(forAthlete: athleteID)

        for folder in folders {
            guard let folderID = folder.id, !folder.sharedWithCoachIDs.isEmpty else { continue }

            for coachID in folder.sharedWithCoachIDs {
                do {
                    try await firestore.removeCoachFromFolder(folderID: folderID, coachID: coachID)
                    await notifyCoachAccessRevoked(
                        coachID: coachID,
                        coachEmail: "",
                        folderID: folderID,
                        folderName: folder.name,
                        athleteID: athleteID
                    )
                } catch {
                    folderLog.error("Failed to remove coach \(coachID) from folder \(folderID): \(error.localizedDescription)")
                }
            }
        }

        // Refresh local folders list
        try await loadAthleteFolders(athleteID: athleteID)
    }

    // MARK: - Coach Functions

    /// Starts a real-time Firestore listener for all folders shared with this coach.
    /// Replaces the one-shot loadCoachFolders fetch — UI auto-updates when folders change.
    func startCoachFoldersListener(coachID: String) {
        // Skip if listener is already active for this coach
        guard coachFoldersListener == nil else { return }
        isLoading = true

        let db = firestore.db
        coachFoldersListener = db.collection(FC.sharedFolders)
            .whereField("sharedWithCoachIDs", arrayContains: coachID)
            .order(by: "updatedAt", descending: true)
            .limit(to: 100)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }

                if let error = error as NSError? {
                    Task { @MainActor in
                        self.isLoading = false
                        // Permission denied (code 7) means coach access was revoked
                        if error.code == 7 {
                            self.coachFolders = []
                            self.stopCoachFoldersListener()
                            self.listenerError = "Your access to shared folders has been revoked."
                        } else {
                            // Transient error — keep cached data visible
                            self.listenerError = "Unable to refresh folders. Showing cached data."
                        }
                    }
                    return
                }

                guard let docs = snapshot?.documents else { return }

                let folders = docs.compactMap { doc -> SharedFolder? in
                    do {
                        var folder = try doc.data(as: SharedFolder.self)
                        folder.id = doc.documentID
                        return folder
                    } catch {
                        folderLog.warning("Failed to decode SharedFolder \(doc.documentID): \(error.localizedDescription)")
                        return nil
                    }
                }
                Task { @MainActor in
                    self.isLoading = false
                    self.listenerError = nil
                    self.coachFolders = folders
                }
            }
    }

    func stopCoachFoldersListener() {
        coachFoldersListener?.remove()
        coachFoldersListener = nil
        listenerError = nil
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
    
    /// Accepts an invitation to join a shared folder.
    /// Coach athlete limit and folder creation are handled server-side by the Cloud Function.
    func acceptInvitation(_ invitation: CoachInvitation, authManager: ComprehensiveAuthManager? = nil) async throws {
        guard let invitationID = invitation.id,
              let coachID = Auth.auth().currentUser?.uid else {
            folderLog.error("acceptInvitation: missing invitationID or coachID")
            throw SharedFolderError.folderNotFound
        }

        // Client-side expiration check — fail fast before making network calls
        if let expiresAt = invitation.expiresAt, expiresAt < Date() {
            folderLog.warning("acceptInvitation: invitation \(invitationID) has expired")
            throw NSError(domain: "FirestoreManager", code: InvitationErrorCode.expired.rawValue,
                          userInfo: [NSLocalizedDescriptionKey: "This invitation has expired."])
        }

        // Server-side: Cloud Function validates limit, accepts invitation, and creates folders
        let permissions = invitation.permissions ?? .default
        folderLog.debug("acceptInvitation: calling firestore.acceptInvitation for \(invitationID)")
        try await firestore.acceptInvitation(
            invitationID: invitationID,
            coachID: coachID,
            permissions: permissions
        )
        folderLog.info("acceptInvitation: Cloud Function succeeded for \(invitationID)")

        // The real-time listener (startCoachFoldersListener) will automatically
        // pick up the new folder — no one-shot fetch needed here.

        // Notify the athlete that their coach accepted
        let coachName = Auth.auth().currentUser?.displayName
            ?? Auth.auth().currentUser?.email
            ?? "Your coach"
        let folderName = invitation.folderName ?? "\(invitation.athleteName)'s Videos"
        await ActivityNotificationService.shared.postInvitationAcceptedNotification(
            folderName: folderName,
            coachID: coachID,
            coachName: coachName,
            athleteID: invitation.athleteID,
            folderID: invitation.folderID ?? ""
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
        // End any active recording sessions for this folder before leaving
        await CoachSessionManager.shared.endSessionIfActive(forFolderID: folderID)
        try await firestore.removeCoachFromFolder(folderID: folderID, coachID: coachID)
        coachFolders.removeAll { $0.id == folderID }
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
        practiceContext: PracticeContext? = nil,
        playResult: String? = nil,
        pitchSpeed: Double? = nil,
        pitchType: String? = nil,
        seasonName: String? = nil,
        athleteName: String? = nil,
        isHighlight: Bool = false,
        clipNote: String? = nil
    ) async throws -> String {
        // Verify folder exists and user has upload permission before starting expensive upload
        guard let folder = try await firestore.fetchSharedFolder(folderID: folderID) else {
            throw SharedFolderError.folderNotFound
        }
        if folder.ownerAthleteID != uploadedBy {
            guard let perms = folder.getPermissions(for: uploadedBy), perms.canUpload else {
                throw SharedFolderError.insufficientPermissions
            }
        }

        // First, upload to Firebase Storage using the REAL implementation
        let storageURL = try await VideoCloudManager.shared.uploadVideo(
            localURL: videoURL,
            fileName: fileName,
            folderID: folderID,
            progressHandler: { progress in
                // Progress is already published by VideoCloudManager
            }
        )

        // Get file size
        let fileSize: Int64
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: videoURL.path)
            fileSize = attributes[.size] as? Int64 ?? 0
        } catch {
            folderLog.warning("Failed to read video file size: \(error.localizedDescription)")
            fileSize = 0
        }

        // Get video duration from AVAsset
        var duration: Double?
        do {
            let asset = AVURLAsset(url: videoURL)
            let durationCM = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(durationCM)
            if seconds.isFinite && seconds > 0 {
                duration = seconds
            }
        } catch {
            folderLog.warning("Failed to get video duration: \(error.localizedDescription)")
        }

        // Generate thumbnail using shared VideoFileManager (consistent size/quality with coach + athlete)
        var thumbnail: ThumbnailMetadata?
        let thumbResult = await VideoFileManager.generateThumbnail(from: videoURL)
        if case .success(let localThumbPath) = thumbResult {
            do {
                let thumbnailURL = try await firestore.uploadThumbnail(
                    localURL: URL(fileURLWithPath: localThumbPath),
                    videoFileName: fileName,
                    folderID: folderID
                )
                thumbnail = ThumbnailMetadata(standardURL: thumbnailURL)
            } catch {
                folderLog.warning("Failed to upload thumbnail: \(error.localizedDescription)")
            }
            // Clean up local thumbnail file
            try? FileManager.default.removeItem(atPath: localThumbPath)
        } else if case .failure(let error) = thumbResult {
            folderLog.warning("Failed to generate thumbnail: \(error.localizedDescription)")
        }

        // Upload metadata to Firestore
        let videoID = try await firestore.uploadVideoMetadata(
            fileName: fileName,
            storageURL: storageURL,
            thumbnail: thumbnail,
            folderID: folderID,
            uploadedBy: uploadedBy,
            uploadedByName: uploadedByName,
            fileSize: fileSize,
            duration: duration,
            videoType: videoType,
            gameContext: gameContext,
            practiceContext: practiceContext,
            playResult: playResult,
            pitchSpeed: pitchSpeed,
            pitchType: pitchType,
            seasonName: seasonName,
            athleteName: athleteName,
            isHighlight: isHighlight
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
                if Auth.auth().currentUser?.uid != nil {
                    try await VideoCloudManager.shared.deleteVideo(fileName: meta.fileName, folderID: folderID)
                } else {
                    folderLog.warning("Cannot delete video storage for \(videoID): user not authenticated")
                }
            } else {
                folderLog.warning("Video metadata not found for \(videoID), skipping storage deletion")
            }
        } catch {
            folderLog.warning("Failed to delete video storage for \(videoID): \(error.localizedDescription)")
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
    /// SECURITY: Ownership is NOT enforced client-side. A Firestore security rule
    /// must enforce `request.auth.uid == resource.data.userID` on annotation deletes.
    /// Without this rule, any authenticated user who knows the annotationID can delete
    /// any other user's comment (privilege escalation). See firestore.rules.
    func deleteComment(videoID: String, annotationID: String, userID: String) async throws {
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


