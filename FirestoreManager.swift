//
//  FirestoreManager.swift
//  PlayerPath
//
//  Created by Assistant on 11/21/25.
//  Core Firestore service for shared folder data management
//

import Foundation
import FirebaseFirestore
import Combine

/// Main service for all Firestore operations
/// Handles shared folders, video metadata, annotations, and invitations
@MainActor
class FirestoreManager: ObservableObject {
    
    static let shared = FirestoreManager()
    
    private let db = Firestore.firestore()
    
    // Published state for reactive UI
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private init() {
        // Enable offline persistence with modern cache settings
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings(sizeBytes: NSNumber(value: FirestoreCacheSizeUnlimited))
        db.settings = settings
        
        print("FirestoreManager initialized with offline persistence")
    }
    
    // MARK: - Shared Folders
    
    /// Creates a new shared folder for an athlete
    /// - Parameters:
    ///   - name: Display name for the folder (e.g., "Coach Smith")
    ///   - ownerAthleteID: User ID of the athlete creating the folder
    ///   - permissions: Dictionary of coach IDs to their permissions
    /// - Returns: The created folder ID
    func createSharedFolder(
        name: String,
        ownerAthleteID: String,
        permissions: [String: FolderPermissions] = [:]
    ) async throws -> String {
        isLoading = true
        defer { isLoading = false }
        
        let folderData: [String: Any] = [
            "name": name,
            "ownerAthleteID": ownerAthleteID,
            "sharedWithCoachIDs": Array(permissions.keys),
            "permissions": permissions.mapValues { $0.toDictionary() },
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
            "videoCount": 0
        ]
        
        do {
            let docRef = try await db.collection("sharedFolders").addDocument(data: folderData)
            print("✅ Created shared folder: \(docRef.documentID)")
            return docRef.documentID
        } catch {
            print("❌ Failed to create shared folder: \(error)")
            errorMessage = "Failed to create folder: \(error.localizedDescription)"
            throw error
        }
    }
    
    /// Fetches all shared folders owned by an athlete
    func fetchSharedFolders(forAthlete athleteID: String) async throws -> [SharedFolder] {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let snapshot = try await db.collection("sharedFolders")
                .whereField("ownerAthleteID", isEqualTo: athleteID)
                .order(by: "createdAt", descending: true)
                .getDocuments()
            
            let folders = snapshot.documents.compactMap { doc -> SharedFolder? in
                var folder = try? doc.data(as: SharedFolder.self)
                folder?.id = doc.documentID
                return folder
            }
            
            print("✅ Fetched \(folders.count) folders for athlete \(athleteID)")
            return folders
        } catch {
            print("❌ Failed to fetch athlete folders: \(error)")
            errorMessage = "Failed to load folders: \(error.localizedDescription)"
            throw error
        }
    }
    
    /// Fetches all shared folders that a coach has access to
    func fetchSharedFolders(forCoach coachID: String) async throws -> [SharedFolder] {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let snapshot = try await db.collection("sharedFolders")
                .whereField("sharedWithCoachIDs", arrayContains: coachID)
                .order(by: "updatedAt", descending: true)
                .getDocuments()
            
            let folders = snapshot.documents.compactMap { doc -> SharedFolder? in
                var folder = try? doc.data(as: SharedFolder.self)
                folder?.id = doc.documentID
                return folder
            }
            
            print("✅ Fetched \(folders.count) folders for coach \(coachID)")
            return folders
        } catch {
            print("❌ Failed to fetch coach folders: \(error)")
            errorMessage = "Failed to load folders: \(error.localizedDescription)"
            throw error
        }
    }
    
    /// Adds a coach to a shared folder
    func addCoachToFolder(
        folderID: String,
        coachID: String,
        permissions: FolderPermissions
    ) async throws {
        isLoading = true
        defer { isLoading = false }
        
        let folderRef = db.collection("sharedFolders").document(folderID)
        
        do {
            try await folderRef.updateData([
                "sharedWithCoachIDs": FieldValue.arrayUnion([coachID]),
                "permissions.\(coachID)": permissions.toDictionary(),
                "updatedAt": FieldValue.serverTimestamp()
            ])
            
            print("✅ Added coach \(coachID) to folder \(folderID)")
        } catch {
            print("❌ Failed to add coach to folder: \(error)")
            errorMessage = "Failed to share folder: \(error.localizedDescription)"
            throw error
        }
    }
    
    /// Removes a coach from a shared folder
    func removeCoachFromFolder(folderID: String, coachID: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        let folderRef = db.collection("sharedFolders").document(folderID)
        
        do {
            try await folderRef.updateData([
                "sharedWithCoachIDs": FieldValue.arrayRemove([coachID]),
                "permissions.\(coachID)": FieldValue.delete(),
                "updatedAt": FieldValue.serverTimestamp()
            ])
            
            print("✅ Removed coach \(coachID) from folder \(folderID)")
        } catch {
            print("❌ Failed to remove coach from folder: \(error)")
            errorMessage = "Failed to remove coach: \(error.localizedDescription)"
            throw error
        }
    }
    
    /// Deletes a shared folder (athlete only)
    func deleteSharedFolder(folderID: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // First, delete all videos in the folder
            let videosSnapshot = try await db.collection("videos")
                .whereField("sharedFolderID", isEqualTo: folderID)
                .getDocuments()
            
            // Batch delete videos
            let batch = db.batch()
            for doc in videosSnapshot.documents {
                batch.deleteDocument(doc.reference)
            }
            try await batch.commit()
            
            // Then delete the folder
            try await db.collection("sharedFolders").document(folderID).delete()
            
            print("✅ Deleted folder \(folderID) and \(videosSnapshot.documents.count) videos")
        } catch {
            print("❌ Failed to delete folder: \(error)")
            errorMessage = "Failed to delete folder: \(error.localizedDescription)"
            throw error
        }
    }
    
    // MARK: - Video Metadata
    
    /// Uploads video metadata to Firestore after file upload to Storage
    /// - Parameters:
    ///   - fileName: Name of the video file
    ///   - storageURL: Firebase Storage URL for the video
    ///   - thumbnail: Structured thumbnail metadata (supports multiple qualities)
    ///   - folderID: Shared folder ID
    ///   - uploadedBy: User ID of uploader
    ///   - uploadedByName: Display name of uploader
    ///   - fileSize: File size in bytes
    ///   - duration: Video duration in seconds
    ///   - videoType: Type of video ("game", "practice", "highlight")
    ///   - gameContext: Optional game-specific metadata
    ///   - practiceContext: Optional practice-specific metadata
    /// - Returns: Document ID of created video metadata
    func uploadVideoMetadata(
        fileName: String,
        storageURL: String,
        thumbnail: ThumbnailMetadata?,
        folderID: String,
        uploadedBy: String,
        uploadedByName: String,
        fileSize: Int64,
        duration: Double?,
        videoType: String = "game",
        gameContext: GameContext? = nil,
        practiceContext: PracticeContext? = nil
    ) async throws -> String {
        isLoading = true
        defer { isLoading = false }
        
        var videoData: [String: Any] = [
            "fileName": fileName,
            "firebaseStorageURL": storageURL,
            "uploadedBy": uploadedBy,
            "uploadedByName": uploadedByName,
            "sharedFolderID": folderID,
            "createdAt": FieldValue.serverTimestamp(),
            "fileSize": fileSize,
            "duration": duration as Any,
            "videoType": videoType,
            "isHighlight": videoType == "highlight"
        ]
        
        // Add structured thumbnail data
        if let thumbnail = thumbnail {
            var thumbnailDict: [String: Any] = [
                "standardURL": thumbnail.standardURL
            ]
            if let highQualityURL = thumbnail.highQualityURL {
                thumbnailDict["highQualityURL"] = highQualityURL
            }
            if let timestamp = thumbnail.timestamp {
                thumbnailDict["timestamp"] = timestamp
            }
            if let width = thumbnail.width {
                thumbnailDict["width"] = width
            }
            if let height = thumbnail.height {
                thumbnailDict["height"] = height
            }
            videoData["thumbnail"] = thumbnailDict
            
            // Keep legacy field for backward compatibility
            videoData["thumbnailURL"] = thumbnail.standardURL
        }
        
        // Add game-specific context
        if let game = gameContext {
            videoData["gameOpponent"] = game.opponent
            videoData["gameDate"] = game.date
            if let notes = game.notes {
                videoData["notes"] = notes
            }
        }
        
        // Add practice-specific context
        if let practice = practiceContext {
            videoData["practiceDate"] = practice.date
            if let notes = practice.notes {
                videoData["notes"] = notes
            }
        }
        
        do {
            let docRef = try await db.collection("videos").addDocument(data: videoData)
            
            // Increment video count in folder
            try await db.collection("sharedFolders").document(folderID).updateData([
                "videoCount": FieldValue.increment(Int64(1)),
                "updatedAt": FieldValue.serverTimestamp()
            ])
            
            print("✅ Uploaded video metadata: \(docRef.documentID) [Type: \(videoType)]")
            return docRef.documentID
        } catch {
            print("❌ Failed to upload video metadata: \(error)")
            errorMessage = "Failed to save video: \(error.localizedDescription)"
            throw error
        }
    }
    
    /// Legacy method for backward compatibility - use uploadVideoMetadata with ThumbnailMetadata instead
    @available(*, deprecated, message: "Use uploadVideoMetadata with ThumbnailMetadata parameter")
    func uploadVideoMetadata(
        fileName: String,
        storageURL: String,
        thumbnailURL: String?,
        folderID: String,
        uploadedBy: String,
        uploadedByName: String,
        fileSize: Int64,
        duration: Double?
    ) async throws -> String {
        let thumbnail = thumbnailURL.map { ThumbnailMetadata(standardURL: $0) }
        return try await uploadVideoMetadata(
            fileName: fileName,
            storageURL: storageURL,
            thumbnail: thumbnail,
            folderID: folderID,
            uploadedBy: uploadedBy,
            uploadedByName: uploadedByName,
            fileSize: fileSize,
            duration: duration
        )
    }
    
    /// Fetches all videos in a shared folder
    func fetchVideos(forFolder folderID: String) async throws -> [FirestoreVideoMetadata] {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let snapshot = try await db.collection("videos")
                .whereField("sharedFolderID", isEqualTo: folderID)
                .order(by: "createdAt", descending: true)
                .getDocuments()
            
            let videos = snapshot.documents.compactMap { doc -> FirestoreVideoMetadata? in
                var video = try? doc.data(as: FirestoreVideoMetadata.self)
                video?.id = doc.documentID
                return video
            }
            
            print("✅ Fetched \(videos.count) videos for folder \(folderID)")
            return videos
        } catch {
            print("❌ Failed to fetch videos: \(error)")
            errorMessage = "Failed to load videos: \(error.localizedDescription)"
            throw error
        }
    }
    
    /// Deletes a video and its metadata
    func deleteVideo(videoID: String, folderID: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Delete all annotations first
            let annotationsSnapshot = try await db.collection("videos")
                .document(videoID)
                .collection("annotations")
                .getDocuments()
            
            let batch = db.batch()
            for doc in annotationsSnapshot.documents {
                batch.deleteDocument(doc.reference)
            }
            try await batch.commit()
            
            // Delete video metadata
            try await db.collection("videos").document(videoID).delete()
            
            // Decrement folder video count
            try await db.collection("sharedFolders").document(folderID).updateData([
                "videoCount": FieldValue.increment(Int64(-1)),
                "updatedAt": FieldValue.serverTimestamp()
            ])
            
            print("✅ Deleted video \(videoID)")
        } catch {
            print("❌ Failed to delete video: \(error)")
            errorMessage = "Failed to delete video: \(error.localizedDescription)"
            throw error
        }
    }
    
    // MARK: - Annotations
    
    /// Adds a comment/annotation to a video
    func addAnnotation(
        videoID: String,
        userID: String,
        userName: String,
        timestamp: Double,
        text: String,
        isCoachComment: Bool
    ) async throws -> String {
        isLoading = true
        defer { isLoading = false }
        
        let annotationData: [String: Any] = [
            "userID": userID,
            "userName": userName,
            "timestamp": timestamp,
            "text": text,
            "createdAt": FieldValue.serverTimestamp(),
            "isCoachComment": isCoachComment
        ]
        
        do {
            let docRef = try await db.collection("videos")
                .document(videoID)
                .collection("annotations")
                .addDocument(data: annotationData)
            
            print("✅ Added annotation to video \(videoID)")
            return docRef.documentID
        } catch {
            print("❌ Failed to add annotation: \(error)")
            errorMessage = "Failed to add comment: \(error.localizedDescription)"
            throw error
        }
    }
    
    /// Fetches all annotations for a video
    func fetchAnnotations(forVideo videoID: String) async throws -> [VideoAnnotation] {
        do {
            let snapshot = try await db.collection("videos")
                .document(videoID)
                .collection("annotations")
                .order(by: "timestamp")
                .getDocuments()
            
            let annotations = snapshot.documents.compactMap { doc -> VideoAnnotation? in
                var annotation = try? doc.data(as: VideoAnnotation.self)
                annotation?.id = doc.documentID
                return annotation
            }
            
            print("✅ Fetched \(annotations.count) annotations for video \(videoID)")
            return annotations
        } catch {
            print("❌ Failed to fetch annotations: \(error)")
            throw error
        }
    }
    
    /// Real-time listener for annotations (for live updates)
    func listenToAnnotations(
        videoID: String,
        completion: @escaping ([VideoAnnotation]) -> Void
    ) -> ListenerRegistration {
        return db.collection("videos")
            .document(videoID)
            .collection("annotations")
            .order(by: "timestamp")
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else {
                    print("❌ Annotation listener error: \(error?.localizedDescription ?? "unknown")")
                    return
                }
                
                let annotations = documents.compactMap { doc -> VideoAnnotation? in
                    var annotation = try? doc.data(as: VideoAnnotation.self)
                    annotation?.id = doc.documentID
                    return annotation
                }
                
                completion(annotations)
            }
    }
    
    /// Deletes an annotation (user can only delete their own)
    func deleteAnnotation(videoID: String, annotationID: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await db.collection("videos")
                .document(videoID)
                .collection("annotations")
                .document(annotationID)
                .delete()
            
            print("✅ Deleted annotation \(annotationID)")
        } catch {
            print("❌ Failed to delete annotation: \(error)")
            errorMessage = "Failed to delete comment: \(error.localizedDescription)"
            throw error
        }
    }
    
    // MARK: - Invitations
    
    /// Creates an invitation for a coach to join a shared folder
    func createInvitation(
        athleteID: String,
        athleteName: String,
        coachEmail: String,
        folderID: String,
        folderName: String
    ) async throws -> String {
        isLoading = true
        defer { isLoading = false }
        
        let invitationData: [String: Any] = [
            "athleteID": athleteID,
            "athleteName": athleteName,
            "coachEmail": coachEmail.lowercased(),
            "folderID": folderID,
            "folderName": folderName,
            "status": "pending",
            "sentAt": FieldValue.serverTimestamp(),
            "expiresAt": Date().addingTimeInterval(30 * 24 * 60 * 60) // 30 days
        ]
        
        do {
            let docRef = try await db.collection("invitations").addDocument(data: invitationData)
            print("✅ Created invitation for \(coachEmail)")
            return docRef.documentID
        } catch {
            print("❌ Failed to create invitation: \(error)")
            errorMessage = "Failed to send invitation: \(error.localizedDescription)"
            throw error
        }
    }
    
    /// Fetches pending invitations for a coach (by email)
    func fetchPendingInvitations(forEmail email: String) async throws -> [CoachInvitation] {
        do {
            let snapshot = try await db.collection("invitations")
                .whereField("coachEmail", isEqualTo: email.lowercased())
                .whereField("status", isEqualTo: "pending")
                .getDocuments()
            
            let invitations = snapshot.documents.compactMap { doc -> CoachInvitation? in
                var invitation = try? doc.data(as: CoachInvitation.self)
                invitation?.id = doc.documentID
                return invitation
            }
            
            print("✅ Found \(invitations.count) pending invitations for \(email)")
            return invitations
        } catch {
            print("❌ Failed to fetch invitations: \(error)")
            throw error
        }
    }
    
    /// Accepts an invitation and adds coach to folder
    func acceptInvitation(
        invitationID: String,
        coachID: String,
        permissions: FolderPermissions
    ) async throws {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Get invitation details
            let invitationDoc = try await db.collection("invitations").document(invitationID).getDocument()
            guard let invitation = try? invitationDoc.data(as: CoachInvitation.self) else {
                throw NSError(domain: "FirestoreManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid invitation"])
            }
            
            let folderID = invitation.folderID
            
            // Add coach to folder
            try await addCoachToFolder(folderID: folderID, coachID: coachID, permissions: permissions)
            
            // Update invitation status
            try await db.collection("invitations").document(invitationID).updateData([
                "status": "accepted",
                "acceptedAt": FieldValue.serverTimestamp()
            ])
            
            print("✅ Accepted invitation \(invitationID)")
        } catch {
            print("❌ Failed to accept invitation: \(error)")
            errorMessage = "Failed to accept invitation: \(error.localizedDescription)"
            throw error
        }
    }
    
    /// Declines an invitation
    func declineInvitation(invitationID: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await db.collection("invitations").document(invitationID).updateData([
                "status": "declined",
                "declinedAt": FieldValue.serverTimestamp()
            ])
            
            print("✅ Declined invitation \(invitationID)")
        } catch {
            print("❌ Failed to decline invitation: \(error)")
            errorMessage = "Failed to decline invitation: \(error.localizedDescription)"
            throw error
        }
    }
    
    // MARK: - User Profile
    
    /// Fetches a user profile by ID
    func fetchUserProfile(userID: String) async throws -> UserProfile? {
        do {
            let doc = try await db.collection("users").document(userID).getDocument()
            var profile = try? doc.data(as: UserProfile.self)
            profile?.id = doc.documentID
            return profile
        } catch {
            print("❌ Failed to fetch user profile: \(error)")
            throw error
        }
    }
    
    /// Updates or creates a user profile
    func updateUserProfile(
        userID: String,
        email: String,
        role: UserRole,
        profileData: [String: Any]
    ) async throws {
        isLoading = true
        defer { isLoading = false }
        
        var userData: [String: Any] = [
            "email": email.lowercased(),
            "role": role.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        // Merge additional profile data
        userData.merge(profileData) { _, new in new }
        
        do {
            try await db.collection("users").document(userID).setData(userData, merge: true)
            print("✅ Updated user profile for \(userID)")
        } catch {
            print("❌ Failed to update user profile: \(error)")
            errorMessage = "Failed to update profile: \(error.localizedDescription)"
            throw error
        }
    }
    
    // MARK: - Helper Methods for Coach Views
    
    /// Fetches videos for a shared folder (convenience method)
    func fetchVideos(forSharedFolder folderID: String) async throws -> [FirestoreVideoMetadata] {
        return try await fetchVideos(forFolder: folderID)
    }
    
    // MARK: - Thumbnail Management
    
    /// Uploads a single thumbnail to Firebase Storage
    /// - Parameters:
    ///   - localURL: Local file URL of the thumbnail image
    ///   - videoFileName: The video file name (to create matching thumbnail name)
    ///   - folderID: Shared folder ID
    ///   - quality: Quality level ("standard" or "high")
    /// - Returns: The download URL for the uploaded thumbnail
    func uploadThumbnail(
        localURL: URL,
        videoFileName: String,
        folderID: String,
        quality: ThumbnailQuality = .standard
    ) async throws -> String {
        isLoading = true
        defer { isLoading = false }
        
        // Use VideoCloudManager for actual upload
        let cloudManager = VideoCloudManager.shared
        
        // Generate appropriate filename based on quality
        let baseFileName = (videoFileName as NSString).deletingPathExtension
        let suffix = quality == .high ? "_thumbnail_hq.jpg" : "_thumbnail.jpg"
        let thumbnailFileName = baseFileName + suffix
        
        do {
            // Create a temporary reference using the quality-specific filename
            let thumbnailURL = try await cloudManager.uploadThumbnail(
                thumbnailURL: localURL,
                videoFileName: thumbnailFileName,
                folderID: folderID
            )
            
            print("✅ Uploaded \(quality.rawValue) quality thumbnail for \(videoFileName)")
            return thumbnailURL
        } catch {
            print("❌ Failed to upload thumbnail: \(error)")
            errorMessage = "Failed to upload thumbnail: \(error.localizedDescription)"
            throw error
        }
    }
    
    /// Uploads multiple thumbnails (standard and high quality) for highlights
    /// - Parameters:
    ///   - standardURL: Local file URL of standard quality thumbnail
    ///   - highQualityURL: Local file URL of high quality thumbnail (optional)
    ///   - videoFileName: The video file name
    ///   - folderID: Shared folder ID
    ///   - timestamp: Time in video where thumbnail was captured
    /// - Returns: Complete ThumbnailMetadata object with all URLs
    func uploadThumbnails(
        standardURL: URL,
        highQualityURL: URL?,
        videoFileName: String,
        folderID: String,
        timestamp: Double? = nil
    ) async throws -> ThumbnailMetadata {
        isLoading = true
        defer { isLoading = false }
        
        // Upload standard quality thumbnail
        let standardDownloadURL = try await uploadThumbnail(
            localURL: standardURL,
            videoFileName: videoFileName,
            folderID: folderID,
            quality: .standard
        )
        
        // Upload high quality thumbnail if provided
        var highQualityDownloadURL: String?
        if let highQualityURL = highQualityURL {
            highQualityDownloadURL = try await uploadThumbnail(
                localURL: highQualityURL,
                videoFileName: videoFileName,
                folderID: folderID,
                quality: .high
            )
        }
        
        return ThumbnailMetadata(
            standardURL: standardDownloadURL,
            highQualityURL: highQualityDownloadURL,
            timestamp: timestamp
        )
    }
    
    enum ThumbnailQuality: String {
        case standard = "standard"
        case high = "high"
    }
    
    /// Creates video metadata with additional context (convenience method)
    func createVideoMetadata(
        folderID: String,
        metadata: [String: Any]
    ) async throws -> String {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let docRef = try await db.collection("videos").addDocument(data: metadata)
            
            // Increment video count in folder
            try await db.collection("sharedFolders").document(folderID).updateData([
                "videoCount": FieldValue.increment(Int64(1)),
                "updatedAt": FieldValue.serverTimestamp()
            ])
            
            print("✅ Created video metadata: \(docRef.documentID)")
            return docRef.documentID
        } catch {
            print("❌ Failed to create video metadata: \(error)")
            errorMessage = "Failed to save video: \(error.localizedDescription)"
            throw error
        }
    }
    
    /// Creates an annotation (convenience method)
    func createAnnotation(
        videoID: String,
        text: String,
        timestamp: Double,
        userID: String,
        userName: String,
        isCoachComment: Bool
    ) async throws -> VideoAnnotation {
        let annotationID = try await addAnnotation(
            videoID: videoID,
            userID: userID,
            userName: userName,
            timestamp: timestamp,
            text: text,
            isCoachComment: isCoachComment
        )
        
        return VideoAnnotation(
            id: annotationID,
            userID: userID,
            userName: userName,
            timestamp: timestamp,
            text: text,
            createdAt: Date(),
            isCoachComment: isCoachComment
        )
    }
}

// MARK: - Supporting Types

/// User role in the app
enum UserRole: String, Codable {
    case athlete
    case coach
}

/// Permissions a coach has for a specific folder
struct FolderPermissions: Codable, Equatable {
    var canUpload: Bool
    var canComment: Bool
    var canDelete: Bool
    
    func toDictionary() -> [String: Bool] {
        return [
            "canUpload": canUpload,
            "canComment": canComment,
            "canDelete": canDelete
        ]
    }
    
    static let `default` = FolderPermissions(canUpload: true, canComment: true, canDelete: false)
    static let viewOnly = FolderPermissions(canUpload: false, canComment: true, canDelete: false)
}

// MARK: - Firestore Models

/// Shared folder model
struct SharedFolder: Codable, Identifiable {
    var id: String?
    let name: String
    let ownerAthleteID: String
    let ownerAthleteName: String?  // Name of the athlete who owns this folder
    let sharedWithCoachIDs: [String]
    let permissions: [String: [String: Bool]]
    let createdAt: Date?
    let updatedAt: Date?
    let videoCount: Int?

    /// Helper to get typed permissions for a coach
    func getPermissions(for coachID: String) -> FolderPermissions? {
        guard let permDict = permissions[coachID] else { return nil }
        return FolderPermissions(
            canUpload: permDict["canUpload"] ?? false,
            canComment: permDict["canComment"] ?? true,
            canDelete: permDict["canDelete"] ?? false
        )
    }
}

/// Thumbnail metadata with support for multiple quality levels
struct ThumbnailMetadata: Codable, Equatable {
    let standardURL: String         // Standard quality (160x120)
    let highQualityURL: String?     // High quality (320x240) - for highlights
    let timestamp: Double?          // Time in video (seconds) where thumbnail was captured
    let width: Int?
    let height: Int?
    
    init(standardURL: String, highQualityURL: String? = nil, timestamp: Double? = nil, width: Int? = nil, height: Int? = nil) {
        self.standardURL = standardURL
        self.highQualityURL = highQualityURL
        self.timestamp = timestamp
        self.width = width
        self.height = height
    }
}

/// Video metadata model
struct FirestoreVideoMetadata: Codable, Identifiable {
    var id: String?
    let fileName: String
    let firebaseStorageURL: String
    
    // IMPROVED: Structured thumbnail metadata instead of single URL
    let thumbnail: ThumbnailMetadata?
    
    // DEPRECATED: Use thumbnail.standardURL instead
    @available(*, deprecated, message: "Use thumbnail.standardURL instead")
    var thumbnailURL: String? {
        thumbnail?.standardURL
    }
    
    let uploadedBy: String
    let uploadedByName: String
    let sharedFolderID: String
    let createdAt: Date?
    let fileSize: Int64?
    let duration: Double?
    let isHighlight: Bool?
    
    // Game/Practice context
    let videoType: String? // "game", "practice", or "highlight"
    let gameOpponent: String?
    let gameDate: Date?
    let practiceDate: Date?
    let notes: String?
}

/// Video annotation/comment model
struct VideoAnnotation: Codable, Identifiable {
    var id: String?
    let userID: String
    let userName: String
    let timestamp: Double // Seconds into video
    let text: String
    let createdAt: Date?
    let isCoachComment: Bool
}

/// Coach invitation model
struct CoachInvitation: Codable, Identifiable {
    var id: String?
    let folderID: String
    let folderName: String
    let athleteID: String
    let athleteName: String
    let coachEmail: String
    let permissions: FolderPermissions
    let createdAt: Date
    var status: InvitationStatus

    enum InvitationStatus: String, Codable {
        case pending
        case accepted
        case declined
    }
}

/// User profile model
struct UserProfile: Codable, Identifiable {
    var id: String?
    let email: String
    let role: String
    let isPremium: Bool?
    let createdAt: Date?
    let updatedAt: Date?
    
    // Role-specific profiles would be nested objects in Firestore
    
    var userRole: UserRole {
        UserRole(rawValue: role) ?? .athlete
    }
}

// MARK: - Video Context Models

/// Context metadata for game videos
struct GameContext {
    let opponent: String
    let date: Date
    let notes: String?
    
    init(opponent: String, date: Date, notes: String? = nil) {
        self.opponent = opponent
        self.date = date
        self.notes = notes
    }
}

/// Context metadata for practice videos
struct PracticeContext {
    let date: Date
    let notes: String?
    let drillType: String?
    
    init(date: Date, notes: String? = nil, drillType: String? = nil) {
        self.date = date
        self.notes = notes
        self.drillType = drillType
    }
}
