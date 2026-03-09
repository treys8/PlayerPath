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
        // Enable offline persistence with a 100MB cache cap
        let settings = FirestoreSettings()
        let cacheSizeBytes = 100 * 1024 * 1024 // 100 MB
        settings.cacheSettings = PersistentCacheSettings(sizeBytes: NSNumber(value: cacheSizeBytes))
        db.settings = settings
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
            errorMessage = "Failed to create folder."
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
                .limit(to: 50)
                .getDocuments()
            
            let folders = snapshot.documents.compactMap { doc -> SharedFolder? in
                var folder = try? doc.data(as: SharedFolder.self)
                folder?.id = doc.documentID
                return folder
            }
            
            print("✅ Fetched \(folders.count) athlete folders")
            return folders
        } catch {
            print("❌ Failed to fetch athlete folders: \(error)")
            errorMessage = "Failed to load folders."
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
                .limit(to: 50)
                .getDocuments()

            let folders = snapshot.documents.compactMap { doc -> SharedFolder? in
                var folder = try? doc.data(as: SharedFolder.self)
                folder?.id = doc.documentID
                return folder
            }

            print("✅ Fetched \(folders.count) coach folders")
            return folders
        } catch {
            print("❌ Failed to fetch coach folders: \(error)")
            errorMessage = "Failed to load folders."
            throw error
        }
    }

    /// Fetches a single shared folder by ID with latest permissions
    func fetchSharedFolder(folderID: String) async throws -> SharedFolder? {
        do {
            let doc = try await db.collection("sharedFolders").document(folderID).getDocument()

            guard doc.exists else {
                return nil
            }

            var folder = try? doc.data(as: SharedFolder.self)
            folder?.id = doc.documentID
            return folder
        } catch {
            print("❌ Failed to fetch folder \(folderID): \(error)")
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
            errorMessage = "Failed to share folder."
            throw error
        }
    }
    
    /// Removes a coach from a shared folder.
    /// Pass `folderName`, `coachEmail`, and `athleteID` when already available at the call
    /// site to skip 2 redundant Firestore reads (folder doc + coach user doc).
    func removeCoachFromFolder(
        folderID: String,
        coachID: String,
        folderName: String? = nil,
        coachEmail: String? = nil,
        athleteID: String? = nil
    ) async throws {
        isLoading = true
        defer { isLoading = false }

        let folderRef = db.collection("sharedFolders").document(folderID)

        do {
            // Resolve folderName + athleteID — skip fetch if caller supplied them
            let resolvedFolderName: String
            let resolvedAthleteID: String
            if let fn = folderName, let aid = athleteID {
                resolvedFolderName = fn
                resolvedAthleteID = aid
            } else {
                let folderSnapshot = try await folderRef.getDocument()
                guard let folderData = folderSnapshot.data(),
                      let fn = folderData["name"] as? String,
                      let aid = folderData["ownerAthleteID"] as? String else {
                    throw NSError(domain: "FirestoreManager", code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "Failed to fetch folder details"])
                }
                resolvedFolderName = fn
                resolvedAthleteID = aid
            }

            // Resolve coachEmail — skip fetch if caller supplied it
            let resolvedCoachEmail: String
            if let ce = coachEmail {
                resolvedCoachEmail = ce
            } else {
                let coachSnapshot = try await db.collection("users").document(coachID).getDocument()
                guard let coachData = coachSnapshot.data(),
                      let ce = coachData["email"] as? String else {
                    throw NSError(domain: "FirestoreManager", code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "Failed to fetch coach email"])
                }
                resolvedCoachEmail = ce
            }

            // Athlete display name still requires a fetch — not available from any call site
            let athleteSnapshot = try await db.collection("users").document(resolvedAthleteID).getDocument()
            let athleteName = athleteSnapshot.data()?["fullName"] as? String ?? "An athlete"

            // Remove coach from folder
            try await folderRef.updateData([
                "sharedWithCoachIDs": FieldValue.arrayRemove([coachID]),
                "permissions.\(coachID)": FieldValue.delete(),
                "updatedAt": FieldValue.serverTimestamp()
            ])

            // Create revocation document to trigger email notification
            try await db.collection("coach_access_revocations").addDocument(data: [
                "folderID": folderID,
                "folderName": resolvedFolderName,
                "coachID": coachID,
                "coachEmail": resolvedCoachEmail,
                "athleteID": resolvedAthleteID,
                "athleteName": athleteName,
                "revokedAt": FieldValue.serverTimestamp(),
                "emailSent": false
            ])

            print("✅ Removed coach \(coachID) from folder \(folderID) and queued revocation email")
        } catch {
            print("❌ Failed to remove coach from folder: \(error)")
            errorMessage = "Failed to remove coach."
            throw error
        }
    }
    
    /// Deletes a shared folder (athlete only)
    func deleteSharedFolder(folderID: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Delete all videos in the folder (paginated — delete until none remain)
            let videosQuery = db.collection("videos")
                .whereField("sharedFolderID", isEqualTo: folderID)
            while true {
                let videosSnapshot = try await videosQuery.limit(to: 400).getDocuments()
                guard !videosSnapshot.documents.isEmpty else { break }
                let batch = db.batch()
                videosSnapshot.documents.forEach { batch.deleteDocument($0.reference) }
                try await batch.commit()
            }
            
            // Then delete the folder
            try await db.collection("sharedFolders").document(folderID).delete()
            
            print("✅ Deleted folder \(folderID) and its videos")
        } catch {
            print("❌ Failed to delete folder: \(error)")
            errorMessage = "Failed to delete folder."
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
            errorMessage = "Failed to save video."
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
                .limit(to: 100)
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
            errorMessage = "Failed to load videos."
            throw error
        }
    }
    
    /// Fetches a single video's metadata by document ID (point-read — 1 read regardless of folder size)
    func fetchVideo(videoID: String) async throws -> FirestoreVideoMetadata? {
        do {
            let doc = try await db.collection("videos").document(videoID).getDocument()
            guard doc.exists else { return nil }
            var video = try? doc.data(as: FirestoreVideoMetadata.self)
            video?.id = doc.documentID
            return video
        } catch {
            print("❌ Failed to fetch video \(videoID): \(error)")
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
            errorMessage = "Failed to delete video."
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

            // Increment annotationCount on the video document
            _ = try? await db.collection("videos").document(videoID)
                .updateData(["annotationCount": FieldValue.increment(Int64(1))])

            print("✅ Added annotation to video \(videoID)")
            return docRef.documentID
        } catch {
            print("❌ Failed to add annotation: \(error)")
            errorMessage = "Failed to add comment."
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
                .limit(to: 200)
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

            // Decrement annotationCount, floored at 0 via transaction
            let videoRef = db.collection("videos").document(videoID)
            _ = try? await db.runTransaction { transaction, errorPointer in
                do {
                    let doc = try transaction.getDocument(videoRef)
                    let current = doc.data()?["annotationCount"] as? Int64 ?? 0
                    transaction.updateData(["annotationCount": max(Int64(0), current - 1)], forDocument: videoRef)
                } catch let fetchError as NSError {
                    errorPointer?.pointee = fetchError
                }
                return nil
            }

            print("✅ Deleted annotation \(annotationID)")
        } catch {
            print("❌ Failed to delete annotation: \(error)")
            errorMessage = "Failed to delete comment."
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
            print("✅ Created invitation")
            return docRef.documentID
        } catch {
            print("❌ Failed to create invitation: \(error)")
            errorMessage = "Failed to send invitation."
            throw error
        }
    }
    
    /// Fetches pending invitations for a coach (by email)
    func fetchPendingInvitations(forEmail email: String) async throws -> [CoachInvitation] {
        do {
            let snapshot = try await db.collection("invitations")
                .whereField("coachEmail", isEqualTo: email.lowercased())
                .whereField("status", isEqualTo: "pending")
                .whereField("expiresAt", isGreaterThan: Timestamp(date: Date()))
                .limit(to: 100)
                .getDocuments()
            
            let invitations = snapshot.documents.compactMap { doc -> CoachInvitation? in
                var invitation = try? doc.data(as: CoachInvitation.self)
                invitation?.id = doc.documentID
                return invitation
            }
            
            print("✅ Found \(invitations.count) pending invitations")
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
            errorMessage = "Failed to accept invitation."
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
            errorMessage = "Failed to decline invitation."
            throw error
        }
    }

    /// Creates an invitation from a coach to an athlete (coach-initiated)
    /// This is for when coaches want to proactively invite athletes to connect
    @discardableResult
    func createCoachToAthleteInvitation(
        coachID: String,
        coachEmail: String,
        coachName: String,
        athleteEmail: String,
        athleteName: String,
        message: String?
    ) async throws -> String {
        isLoading = true
        defer { isLoading = false }

        var invitationData: [String: Any] = [
            "type": "coach_to_athlete",
            "coachID": coachID,
            "coachEmail": coachEmail.lowercased(),
            "coachName": coachName,
            "athleteEmail": athleteEmail.lowercased(),
            "athleteName": athleteName,
            "status": "pending",
            "sentAt": FieldValue.serverTimestamp(),
            "expiresAt": Date().addingTimeInterval(30 * 24 * 60 * 60) // 30 days
        ]

        if let message = message {
            invitationData["message"] = message
        }

        do {
            let docRef = try await db.collection("invitations").addDocument(data: invitationData)
            print("✅ Created coach-to-athlete invitation")

            // TODO: Trigger Cloud Function to send email notification
            // For now, the invitation will be visible when the athlete logs in

            return docRef.documentID
        } catch {
            print("❌ Failed to create coach-to-athlete invitation: \(error)")
            errorMessage = "Failed to send invitation."
            throw error
        }
    }

    /// Fetches pending invitations from coaches for an athlete (by email)
    func fetchPendingCoachInvitations(forAthleteEmail email: String) async throws -> [CoachToAthleteInvitation] {
        do {
            let snapshot = try await db.collection("invitations")
                .whereField("type", isEqualTo: "coach_to_athlete")
                .whereField("athleteEmail", isEqualTo: email.lowercased())
                .whereField("status", isEqualTo: "pending")
                .limit(to: 100)
                .getDocuments()

            let invitations = snapshot.documents.compactMap { doc -> CoachToAthleteInvitation? in
                let data = doc.data()
                return CoachToAthleteInvitation(
                    id: doc.documentID,
                    coachID: data["coachID"] as? String ?? "",
                    coachEmail: data["coachEmail"] as? String ?? "",
                    coachName: data["coachName"] as? String ?? "",
                    athleteEmail: data["athleteEmail"] as? String ?? "",
                    athleteName: data["athleteName"] as? String ?? "",
                    message: data["message"] as? String,
                    status: data["status"] as? String ?? "pending",
                    sentAt: (data["sentAt"] as? Timestamp)?.dateValue()
                )
            }

            print("✅ Found \(invitations.count) pending coach invitations")
            return invitations
        } catch {
            print("❌ Failed to fetch coach invitations: \(error)")
            throw error
        }
    }

    /// Accepts a coach-to-athlete invitation
    func acceptCoachToAthleteInvitation(invitationID: String, athleteUserID: String) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            try await db.collection("invitations").document(invitationID).updateData([
                "status": "accepted",
                "acceptedAt": FieldValue.serverTimestamp(),
                "athleteUserID": athleteUserID
            ])

            print("✅ Accepted coach-to-athlete invitation \(invitationID)")
        } catch {
            print("❌ Failed to accept coach invitation: \(error)")
            throw error
        }
    }

    /// Declines a coach-to-athlete invitation
    func declineCoachToAthleteInvitation(invitationID: String) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            try await db.collection("invitations").document(invitationID).updateData([
                "status": "declined",
                "declinedAt": FieldValue.serverTimestamp()
            ])

            print("✅ Declined coach-to-athlete invitation \(invitationID)")
        } catch {
            print("❌ Failed to decline coach invitation: \(error)")
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
        
        // Strip subscription/billing fields from general profile updates — use syncSubscriptionTiers() for tier writes
        let serverOnlyFields: Set<String> = ["subscriptionTier"]
        let safeProfileData = profileData.filter { !serverOnlyFields.contains($0.key) }

        // Merge additional profile data; keep explicitly set fields (email, role) on conflict
        userData.merge(safeProfileData) { current, _ in current }
        
        do {
            try await db.collection("users").document(userID).setData(userData, merge: true)
            print("✅ Updated user profile")
        } catch {
            print("❌ Failed to update user profile: \(error)")
            errorMessage = "Failed to update profile."
            throw error
        }
    }

    /// Syncs StoreKit-resolved subscription tiers to the user's Firestore doc.
    /// Separate from updateUserProfile so it bypasses the serverOnlyFields strip.
    func syncSubscriptionTiers(
        userID: String,
        tier: SubscriptionTier,
        coachTier: CoachSubscriptionTier
    ) async {
        var data: [String: Any] = [
            "subscriptionTier": tier.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        // Only write coachSubscriptionTier when StoreKit resolves a paid coach tier.
        // If StoreKit resolves .free, leave Firestore alone — it may hold "coach_academy"
        // which must not be overwritten.
        if coachTier != .free {
            data["coachSubscriptionTier"] = coachTier.rawValue
        }
        do {
            try await db.collection("users").document(userID).setData(data, merge: true)
            print("✅ Synced tiers to Firestore: \(tier.rawValue) / \(coachTier.rawValue)")
        } catch {
            print("⚠️ Failed to sync subscription tiers to Firestore: \(error)")
        }
    }

    /// Deletes user profile and all associated data (GDPR compliance)
    /// This includes:
    /// - User profile document
    /// - Shared folders owned by the user
    /// - All videos in those folders
    /// - All annotations created by the user
    func deleteUserProfile(userID: String) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            print("🗑️ Deleting Firestore data for user: \(userID)")

            // Step 1: Delete all shared folders owned by this user (paginated)
            let foldersQuery = db.collection("sharedFolders")
                .whereField("ownerAthleteID", isEqualTo: userID)
            var folderCount = 0
            while true {
                let foldersSnapshot = try await foldersQuery.limit(to: 50).getDocuments()
                guard !foldersSnapshot.documents.isEmpty else { break }
                for folderDoc in foldersSnapshot.documents {
                    let folderID = folderDoc.documentID
                    // Delete all videos in this folder (paginated)
                    let videosQuery = db.collection("videos")
                        .whereField("sharedFolderID", isEqualTo: folderID)
                    while true {
                        let videosSnapshot = try await videosQuery.limit(to: 100).getDocuments()
                        guard !videosSnapshot.documents.isEmpty else { break }
                        for videoDoc in videosSnapshot.documents {
                            // Delete annotations for this video (paginated)
                            let annotationsQuery = db.collection("videos")
                                .document(videoDoc.documentID)
                                .collection("annotations")
                            while true {
                                let annSnap = try await annotationsQuery.limit(to: 400).getDocuments()
                                guard !annSnap.documents.isEmpty else { break }
                                let batch = db.batch()
                                annSnap.documents.forEach { batch.deleteDocument($0.reference) }
                                try await batch.commit()
                            }
                            try await videoDoc.reference.delete()
                        }
                    }
                    try await db.collection("sharedFolders").document(folderID).delete()
                    folderCount += 1
                }
            }
            print("✅ Deleted \(folderCount) folders with all videos")

            // Step 2: Delete all annotations created by this user across all videos (paginated)
            let userAnnotationsQuery = db.collectionGroup("annotations")
                .whereField("userID", isEqualTo: userID)
            var annotationCount = 0
            while true {
                let snap = try await userAnnotationsQuery.limit(to: 400).getDocuments()
                guard !snap.documents.isEmpty else { break }
                let batch = db.batch()
                snap.documents.forEach { batch.deleteDocument($0.reference) }
                try await batch.commit()
                annotationCount += snap.documents.count
            }
            print("✅ Deleted \(annotationCount) annotations by user")

            // Step 3: Delete all invitations sent by this user (paginated)
            let invitationsQuery = db.collection("invitations")
                .whereField("athleteID", isEqualTo: userID)
            var invitationCount = 0
            while true {
                let snap = try await invitationsQuery.limit(to: 400).getDocuments()
                guard !snap.documents.isEmpty else { break }
                let batch = db.batch()
                snap.documents.forEach { batch.deleteDocument($0.reference) }
                try await batch.commit()
                invitationCount += snap.documents.count
            }
            print("✅ Deleted \(invitationCount) invitations")

            // Step 4: Delete all in-app notifications for this user (GDPR, paginated)
            let notificationsQuery = db.collection("notifications")
                .document(userID)
                .collection("items")
            var notificationCount = 0
            while true {
                let snap = try await notificationsQuery.limit(to: 400).getDocuments()
                guard !snap.documents.isEmpty else { break }
                let batch = db.batch()
                snap.documents.forEach { batch.deleteDocument($0.reference) }
                try await batch.commit()
                notificationCount += snap.documents.count
            }
            try? await db.collection("notifications").document(userID).delete()
            print("✅ Deleted \(notificationCount) notifications")

            // Step 5: Delete user profile document
            try await db.collection("users").document(userID).delete()
            print("✅ Deleted user profile document")

        } catch {
            print("❌ Failed to delete user profile: \(error)")
            errorMessage = "Failed to delete user data."
            throw error
        }
    }

    /// Fetches coach information (name and email) by ID
    /// Returns a tuple with name and email for display purposes
    func fetchCoachInfo(coachID: String) async throws -> (name: String, email: String) {
        do {
            let doc = try await db.collection("users").document(coachID).getDocument()

            guard doc.exists else {
                throw NSError(
                    domain: "FirestoreManager",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Coach not found"]
                )
            }

            let data = doc.data() ?? [:]
            let email = data["email"] as? String ?? "Unknown"
            let fullName = data["fullName"] as? String
            let displayName = data["displayName"] as? String

            // Use fullName if available, fallback to displayName, then email
            let name = fullName ?? displayName ?? email.components(separatedBy: "@").first ?? "Unknown Coach"

            return (name: name, email: email)
        } catch {
            #if DEBUG
            print("❌ Failed to fetch coach info for \(coachID): \(error)")
            #else
            print("❌ Failed to fetch coach info")
            #endif
            throw error
        }
    }

    // MARK: - Athletes Sync

    /// Creates a new athlete in Firestore for cross-device sync
    /// - Parameters:
    ///   - userId: The user ID who owns this athlete
    ///   - data: Athlete data dictionary (from Athlete.toFirestoreData())
    /// - Returns: The Firestore document ID for the created athlete
    func createAthlete(userId: String, data: [String: Any]) async throws -> String {
        isLoading = true
        defer { isLoading = false }

        var athleteData = data
        athleteData["createdAt"] = FieldValue.serverTimestamp()
        athleteData["updatedAt"] = FieldValue.serverTimestamp()

        do {
            let docRef = try await db
                .collection("users")
                .document(userId)
                .collection("athletes")
                .addDocument(data: athleteData)

            print("✅ Created athlete in Firestore: \(docRef.documentID)")
            return docRef.documentID
        } catch {
            print("❌ Failed to create athlete: \(error)")
            errorMessage = "Failed to create athlete."
            throw error
        }
    }

    /// Updates an existing athlete in Firestore
    /// - Parameters:
    ///   - userId: The user ID who owns this athlete
    ///   - athleteId: The Firestore document ID of the athlete
    ///   - data: Updated athlete data dictionary
    func updateAthlete(userId: String, athleteId: String, data: [String: Any]) async throws {
        isLoading = true
        defer { isLoading = false }

        var updateData = data
        updateData["updatedAt"] = FieldValue.serverTimestamp()

        do {
            try await db
                .collection("users")
                .document(userId)
                .collection("athletes")
                .document(athleteId)
                .setData(updateData, merge: true)

            print("✅ Updated athlete in Firestore: \(athleteId)")
        } catch {
            print("❌ Failed to update athlete: \(error)")
            errorMessage = "Failed to update athlete."
            throw error
        }
    }

    /// Fetches all athletes for a user from Firestore
    /// - Parameter userId: The user ID to fetch athletes for
    /// - Returns: Array of FirestoreAthlete objects
    func fetchAthletes(userId: String) async throws -> [FirestoreAthlete] {
        isLoading = true
        defer { isLoading = false }

        do {
            let snapshot = try await db
                .collection("users")
                .document(userId)
                .collection("athletes")
                .whereField("isDeleted", isEqualTo: false)
                .order(by: "createdAt", descending: false)
                .getDocuments()

            let athletes = snapshot.documents.compactMap { doc -> FirestoreAthlete? in
                var athlete = try? doc.data(as: FirestoreAthlete.self)
                athlete?.id = doc.documentID
                return athlete
            }

            print("✅ Fetched \(athletes.count) athletes for user \(userId)")
            return athletes
        } catch {
            print("❌ Failed to fetch athletes: \(error)")
            errorMessage = "Failed to load athletes."
            throw error
        }
    }

    /// Soft deletes an athlete in Firestore (marks as deleted, doesn't remove)
    /// - Parameters:
    ///   - userId: The user ID who owns this athlete
    ///   - athleteId: The Firestore document ID of the athlete
    func deleteAthlete(userId: String, athleteId: String) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            try await db
                .collection("users")
                .document(userId)
                .collection("athletes")
                .document(athleteId)
                .updateData([
                    "isDeleted": true,
                    "deletedAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp()
                ])

            print("✅ Soft deleted athlete in Firestore: \(athleteId)")
        } catch {
            print("❌ Failed to delete athlete: \(error)")
            errorMessage = "Failed to delete athlete."
            throw error
        }
    }

    // MARK: - Seasons Sync

    /// Creates a new season in Firestore for cross-device sync
    /// - Parameters:
    ///   - userId: The user ID who owns this season
    ///   - data: Season data dictionary (from Season.toFirestoreData())
    /// - Returns: The Firestore document ID for the created season
    func createSeason(userId: String, data: [String: Any]) async throws -> String {
        isLoading = true
        defer { isLoading = false }

        var seasonData = data
        seasonData["createdAt"] = FieldValue.serverTimestamp()
        seasonData["updatedAt"] = FieldValue.serverTimestamp()

        do {
            let docRef = try await db
                .collection("users")
                .document(userId)
                .collection("seasons")
                .addDocument(data: seasonData)

            print("✅ Created season in Firestore: \(docRef.documentID)")
            return docRef.documentID
        } catch {
            print("❌ Failed to create season: \(error)")
            errorMessage = "Failed to create season."
            throw error
        }
    }

    /// Updates an existing season in Firestore
    /// - Parameters:
    ///   - userId: The user ID who owns this season
    ///   - seasonId: The Firestore document ID of the season
    ///   - data: Updated season data dictionary
    func updateSeason(userId: String, seasonId: String, data: [String: Any]) async throws {
        isLoading = true
        defer { isLoading = false }

        var updateData = data
        updateData["updatedAt"] = FieldValue.serverTimestamp()

        do {
            try await db
                .collection("users")
                .document(userId)
                .collection("seasons")
                .document(seasonId)
                .setData(updateData, merge: true)

            print("✅ Updated season in Firestore: \(seasonId)")
        } catch {
            print("❌ Failed to update season: \(error)")
            errorMessage = "Failed to update season."
            throw error
        }
    }

    /// Fetches all seasons for a user from Firestore
    /// - Parameter userId: The user ID to fetch seasons for
    /// - Returns: Array of FirestoreSeason objects
    func fetchSeasons(userId: String) async throws -> [FirestoreSeason] {
        isLoading = true
        defer { isLoading = false }

        do {
            let snapshot = try await db
                .collection("users")
                .document(userId)
                .collection("seasons")
                .whereField("isDeleted", isEqualTo: false)
                .order(by: "createdAt", descending: true)
                .limit(to: 100)
                .getDocuments()

            let seasons = snapshot.documents.compactMap { doc -> FirestoreSeason? in
                guard var season = try? doc.data(as: FirestoreSeason.self) else { return nil }
                season.id = doc.documentID
                return season
            }

            print("✅ Fetched \(seasons.count) seasons from Firestore")
            return seasons
        } catch {
            print("❌ Failed to fetch seasons: \(error)")
            errorMessage = "Failed to fetch seasons."
            throw error
        }
    }

    /// Soft deletes a season in Firestore
    /// - Parameters:
    ///   - userId: The user ID who owns this season
    ///   - seasonId: The Firestore document ID of the season
    func deleteSeason(userId: String, seasonId: String) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            try await db
                .collection("users")
                .document(userId)
                .collection("seasons")
                .document(seasonId)
                .updateData([
                    "isDeleted": true,
                    "deletedAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp()
                ])

            print("✅ Soft deleted season in Firestore: \(seasonId)")
        } catch {
            print("❌ Failed to delete season: \(error)")
            errorMessage = "Failed to delete season."
            throw error
        }
    }

    // MARK: - Games Sync

    /// Creates a new game in Firestore for cross-device sync
    /// - Parameters:
    ///   - userId: The user ID who owns this game
    ///   - data: Game data dictionary (from Game.toFirestoreData())
    /// - Returns: The Firestore document ID for the created game
    func createGame(userId: String, data: [String: Any]) async throws -> String {
        isLoading = true
        defer { isLoading = false }

        var gameData = data
        gameData["createdAt"] = FieldValue.serverTimestamp()
        gameData["updatedAt"] = FieldValue.serverTimestamp()

        do {
            let docRef = try await db
                .collection("users")
                .document(userId)
                .collection("games")
                .addDocument(data: gameData)

            print("✅ Created game in Firestore: \(docRef.documentID)")
            return docRef.documentID
        } catch {
            print("❌ Failed to create game: \(error)")
            errorMessage = "Failed to create game."
            throw error
        }
    }

    /// Updates an existing game in Firestore
    /// - Parameters:
    ///   - userId: The user ID who owns this game
    ///   - gameId: The Firestore document ID of the game
    ///   - data: Updated game data dictionary
    func updateGame(userId: String, gameId: String, data: [String: Any]) async throws {
        isLoading = true
        defer { isLoading = false }

        var updateData = data
        updateData["updatedAt"] = FieldValue.serverTimestamp()

        do {
            try await db
                .collection("users")
                .document(userId)
                .collection("games")
                .document(gameId)
                .setData(updateData, merge: true)

            print("✅ Updated game in Firestore: \(gameId)")
        } catch {
            print("❌ Failed to update game: \(error)")
            errorMessage = "Failed to update game."
            throw error
        }
    }

    /// Fetches all games for a user from Firestore
    /// - Parameter userId: The user ID to fetch games for
    /// - Returns: Array of FirestoreGame objects
    func fetchGames(userId: String) async throws -> [FirestoreGame] {
        isLoading = true
        defer { isLoading = false }

        do {
            let snapshot = try await db
                .collection("users")
                .document(userId)
                .collection("games")
                .whereField("isDeleted", isEqualTo: false)
                .order(by: "date", descending: true)
                .limit(to: 200)
                .getDocuments()

            let games = snapshot.documents.compactMap { doc -> FirestoreGame? in
                guard var game = try? doc.data(as: FirestoreGame.self) else { return nil }
                game.id = doc.documentID
                return game
            }

            print("✅ Fetched \(games.count) games from Firestore")
            return games
        } catch {
            print("❌ Failed to fetch games: \(error)")
            errorMessage = "Failed to fetch games."
            throw error
        }
    }

    /// Soft deletes a game in Firestore
    /// - Parameters:
    ///   - userId: The user ID who owns this game
    ///   - gameId: The Firestore document ID of the game
    func deleteGame(userId: String, gameId: String) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            try await db
                .collection("users")
                .document(userId)
                .collection("games")
                .document(gameId)
                .updateData([
                    "isDeleted": true,
                    "deletedAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp()
                ])

            print("✅ Soft deleted game in Firestore: \(gameId)")
        } catch {
            print("❌ Failed to delete game: \(error)")
            errorMessage = "Failed to delete game."
            throw error
        }
    }

    // MARK: - Practices Sync

    /// Creates a new practice in Firestore for cross-device sync
    /// - Parameters:
    ///   - userId: The user ID who owns this practice
    ///   - data: Practice data dictionary (from Practice.toFirestoreData())
    /// - Returns: The Firestore document ID for the created practice
    func createPractice(userId: String, data: [String: Any]) async throws -> String {
        isLoading = true
        defer { isLoading = false }

        var practiceData = data
        practiceData["createdAt"] = FieldValue.serverTimestamp()
        practiceData["updatedAt"] = FieldValue.serverTimestamp()

        do {
            let docRef = try await db
                .collection("users")
                .document(userId)
                .collection("practices")
                .addDocument(data: practiceData)

            print("✅ Created practice in Firestore: \(docRef.documentID)")
            return docRef.documentID
        } catch {
            print("❌ Failed to create practice: \(error)")
            errorMessage = "Failed to create practice."
            throw error
        }
    }

    /// Updates an existing practice in Firestore
    /// - Parameters:
    ///   - userId: The user ID who owns this practice
    ///   - practiceId: The Firestore document ID of the practice
    ///   - data: Updated practice data dictionary
    func updatePractice(userId: String, practiceId: String, data: [String: Any]) async throws {
        isLoading = true
        defer { isLoading = false }

        var updateData = data
        updateData["updatedAt"] = FieldValue.serverTimestamp()

        do {
            try await db
                .collection("users")
                .document(userId)
                .collection("practices")
                .document(practiceId)
                .setData(updateData, merge: true)

            print("✅ Updated practice in Firestore: \(practiceId)")
        } catch {
            print("❌ Failed to update practice: \(error)")
            errorMessage = "Failed to update practice."
            throw error
        }
    }

    /// Fetches all practices for a user from Firestore
    /// - Parameter userId: The user ID to fetch practices for
    /// - Returns: Array of FirestorePractice objects
    func fetchPractices(userId: String) async throws -> [FirestorePractice] {
        isLoading = true
        defer { isLoading = false }

        do {
            let snapshot = try await db
                .collection("users")
                .document(userId)
                .collection("practices")
                .whereField("isDeleted", isEqualTo: false)
                .order(by: "date", descending: true)
                .limit(to: 200)
                .getDocuments()

            let practices = snapshot.documents.compactMap { doc -> FirestorePractice? in
                var practice = try? doc.data(as: FirestorePractice.self)
                practice?.id = doc.documentID
                return practice
            }

            print("✅ Fetched \(practices.count) practices for user \(userId)")
            return practices
        } catch {
            print("❌ Failed to fetch practices: \(error)")
            errorMessage = "Failed to load practices."
            throw error
        }
    }

    /// Soft deletes a practice in Firestore (marks as deleted, doesn't remove)
    /// - Parameters:
    ///   - userId: The user ID who owns this practice
    ///   - practiceId: The Firestore document ID of the practice
    func deletePractice(userId: String, practiceId: String) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            try await db
                .collection("users")
                .document(userId)
                .collection("practices")
                .document(practiceId)
                .updateData([
                    "isDeleted": true,
                    "deletedAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp()
                ])

            print("✅ Soft deleted practice in Firestore: \(practiceId)")
        } catch {
            print("❌ Failed to delete practice: \(error)")
            errorMessage = "Failed to delete practice."
            throw error
        }
    }

    // MARK: - Practice Notes Sync

    func createPracticeNote(userId: String, practiceFirestoreId: String, data: [String: Any]) async throws -> String {
        var noteData = data
        noteData["createdAt"] = FieldValue.serverTimestamp()
        noteData["updatedAt"] = FieldValue.serverTimestamp()
        let docRef = try await db
            .collection("users").document(userId)
            .collection("practices").document(practiceFirestoreId)
            .collection("notes")
            .addDocument(data: noteData)
        print("✅ Created practice note in Firestore: \(docRef.documentID)")
        return docRef.documentID
    }

    func updatePracticeNote(userId: String, practiceFirestoreId: String, noteId: String, data: [String: Any]) async throws {
        var updateData = data
        updateData["updatedAt"] = FieldValue.serverTimestamp()
        try await db
            .collection("users").document(userId)
            .collection("practices").document(practiceFirestoreId)
            .collection("notes").document(noteId)
            .setData(updateData, merge: true)
        print("✅ Updated practice note in Firestore: \(noteId)")
    }

    func fetchPracticeNotes(userId: String, practiceFirestoreId: String) async throws -> [FirestorePracticeNote] {
        let snapshot = try await db
            .collection("users").document(userId)
            .collection("practices").document(practiceFirestoreId)
            .collection("notes")
            .whereField("isDeleted", isEqualTo: false)
            .getDocuments()
        return snapshot.documents.compactMap { doc -> FirestorePracticeNote? in
            var note = try? doc.data(as: FirestorePracticeNote.self)
            note?.id = doc.documentID
            return note
        }
    }

    // MARK: - Photos Sync

    func createPhoto(data: [String: Any]) async throws -> String {
        var photoData = data
        photoData["createdAt"] = FieldValue.serverTimestamp()
        photoData["updatedAt"] = FieldValue.serverTimestamp()
        let docRef = try await db.collection("photos").addDocument(data: photoData)
        print("✅ Created photo in Firestore: \(docRef.documentID)")
        return docRef.documentID
    }

    func fetchPhotos(uploadedBy ownerUID: String, athleteId: String) async throws -> [FirestorePhoto] {
        let snapshot = try await db
            .collection("photos")
            .whereField("uploadedBy", isEqualTo: ownerUID)
            .whereField("athleteId", isEqualTo: athleteId)
            .whereField("isDeleted", isEqualTo: false)
            .limit(to: 500)
            .getDocuments()
        return snapshot.documents.compactMap { doc -> FirestorePhoto? in
            var photo = try? doc.data(as: FirestorePhoto.self)
            photo?.id = doc.documentID
            return photo
        }
    }

    // MARK: - Coaches Sync

    func createCoach(userId: String, athleteFirestoreId: String, data: [String: Any]) async throws -> String {
        var coachData = data
        coachData["createdAt"] = FieldValue.serverTimestamp()
        coachData["updatedAt"] = FieldValue.serverTimestamp()
        let docRef = try await db
            .collection("users").document(userId)
            .collection("athletes").document(athleteFirestoreId)
            .collection("coaches")
            .addDocument(data: coachData)
        print("✅ Created coach in Firestore: \(docRef.documentID)")
        return docRef.documentID
    }

    func updateCoach(userId: String, athleteFirestoreId: String, coachId: String, data: [String: Any]) async throws {
        var updateData = data
        updateData["updatedAt"] = FieldValue.serverTimestamp()
        try await db
            .collection("users").document(userId)
            .collection("athletes").document(athleteFirestoreId)
            .collection("coaches").document(coachId)
            .setData(updateData, merge: true)
        print("✅ Updated coach in Firestore: \(coachId)")
    }

    func fetchCoaches(userId: String, athleteFirestoreId: String) async throws -> [FirestoreCoach] {
        let snapshot = try await db
            .collection("users").document(userId)
            .collection("athletes").document(athleteFirestoreId)
            .collection("coaches")
            .whereField("isDeleted", isEqualTo: false)
            .getDocuments()
        return snapshot.documents.compactMap { doc -> FirestoreCoach? in
            var coach = try? doc.data(as: FirestoreCoach.self)
            coach?.id = doc.documentID
            return coach
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
            errorMessage = "Failed to upload thumbnail."
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

        // Allowlist prevents arbitrary fields from being written to Firestore
        let allowedFields: Set<String> = [
            "fileName", "firebaseStorageURL", "uploadedBy", "uploadedByName",
            "sharedFolderID", "fileSize", "duration", "videoType", "isHighlight",
            "thumbnail", "thumbnailURL", "gameOpponent", "gameDate", "practiceDate",
            "notes", "playResult", "athleteName", "seasonID"
        ]
        var safeMetadata = metadata.filter { allowedFields.contains($0.key) }
        safeMetadata["sharedFolderID"] = folderID
        safeMetadata["createdAt"] = FieldValue.serverTimestamp()

        do {
            let docRef = try await db.collection("videos").addDocument(data: safeMetadata)
            
            // Increment video count in folder
            try await db.collection("sharedFolders").document(folderID).updateData([
                "videoCount": FieldValue.increment(Int64(1)),
                "updatedAt": FieldValue.serverTimestamp()
            ])
            
            print("✅ Created video metadata: \(docRef.documentID)")
            return docRef.documentID
        } catch {
            print("❌ Failed to create video metadata: \(error)")
            errorMessage = "Failed to save video."
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
struct SharedFolder: Codable, Identifiable, Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: SharedFolder, rhs: SharedFolder) -> Bool { lhs.id == rhs.id }
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

    // ENHANCED: Upload source tracking
    let uploadedByType: UploadedByType? // "athlete" or "coach"
    let isOrphaned: Bool? // True if uploader deleted their account
    let orphanedAt: Date? // When uploader account was deleted

    // Annotation count (incremented/decremented atomically via FieldValue.increment)
    let annotationCount: Int?

    // Game/Practice context
    let videoType: String? // "game", "practice", or "highlight"
    let gameOpponent: String?
    let gameDate: Date?
    let practiceDate: Date?
    let notes: String?

    /// Display name for uploader (handles orphaned accounts)
    var uploaderDisplayName: String {
        if isOrphaned == true {
            return "\(uploadedByName) (Former Coach)"
        }
        return uploadedByName
    }

    /// Whether this video was uploaded by a coach
    var wasUploadedByCoach: Bool {
        uploadedByType == .coach
    }
}

/// Type of user who uploaded a video
enum UploadedByType: String, Codable {
    case athlete
    case coach

    var displayName: String {
        switch self {
        case .athlete: return "Athlete"
        case .coach: return "Coach"
        }
    }
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
    let permissions: FolderPermissions?
    let createdAt: Date
    var status: InvitationStatus

    enum InvitationStatus: String, Codable {
        case pending
        case accepted
        case declined
    }
}

/// Coach-to-Athlete invitation (when coach initiates the connection)
struct CoachToAthleteInvitation: Identifiable {
    let id: String
    let coachID: String
    let coachEmail: String
    let coachName: String
    let athleteEmail: String
    let athleteName: String
    let message: String?
    let status: String
    let sentAt: Date?
}

/// User profile model
struct UserProfile: Codable, Identifiable {
    var id: String?
    let email: String
    let role: String
    let subscriptionTier: String?
    let coachSubscriptionTier: String?
    let createdAt: Date?
    let updatedAt: Date?

    // Role-specific profiles would be nested objects in Firestore

    var userRole: UserRole {
        UserRole(rawValue: role) ?? .athlete
    }

    var tier: SubscriptionTier {
        SubscriptionTier(rawValue: subscriptionTier ?? "free") ?? .free
    }
}

/// Athlete model for Firestore sync
struct FirestoreAthlete: Codable, Identifiable {
    var id: String?           // Firestore document ID (auto-generated, not encoded)
    let swiftDataId: String   // Original SwiftData UUID
    let name: String
    let primaryRole: String?
    let userId: String
    let createdAt: Date?
    let updatedAt: Date?
    let version: Int
    let isDeleted: Bool

    enum CodingKeys: String, CodingKey {
        case swiftDataId = "id"  // Maps to "id" field in Firestore document
        case name
        case primaryRole
        case userId
        case createdAt
        case updatedAt
        case version
        case isDeleted
    }
}

/// Season model for Firestore sync
struct FirestoreSeason: Codable, Identifiable {
    var id: String?           // Firestore document ID (auto-generated, not encoded)
    let swiftDataId: String   // Original SwiftData UUID
    let name: String
    let athleteId: String
    let startDate: Date?
    let endDate: Date?
    let isActive: Bool
    let sport: String
    let notes: String
    let createdAt: Date?
    let updatedAt: Date?
    let version: Int
    let isDeleted: Bool

    enum CodingKeys: String, CodingKey {
        case swiftDataId = "id"  // Maps to "id" field in Firestore document
        case name
        case athleteId
        case startDate
        case endDate
        case isActive
        case sport
        case notes
        case createdAt
        case updatedAt
        case version
        case isDeleted
    }
}

/// Game model for Firestore sync
struct FirestoreGame: Codable, Identifiable {
    var id: String?           // Firestore document ID (auto-generated, not encoded)
    let swiftDataId: String   // Original SwiftData UUID
    let athleteId: String
    let seasonId: String?
    let tournamentId: String?
    let opponent: String
    let date: Date?
    let year: Int
    let isLive: Bool
    let isComplete: Bool
    let createdAt: Date?
    let updatedAt: Date?
    let version: Int
    let isDeleted: Bool

    enum CodingKeys: String, CodingKey {
        case swiftDataId = "id"  // Maps to "id" field in Firestore document
        case athleteId
        case seasonId
        case tournamentId
        case opponent
        case date
        case year
        case isLive
        case isComplete
        case createdAt
        case updatedAt
        case version
        case isDeleted
    }
}

struct FirestorePractice: Codable, Identifiable {
    var id: String?           // Firestore document ID (auto-generated, not encoded)
    let swiftDataId: String   // Original SwiftData UUID
    let athleteId: String
    let seasonId: String?
    let date: Date?
    let createdAt: Date?
    let updatedAt: Date?
    let version: Int
    let isDeleted: Bool

    enum CodingKeys: String, CodingKey {
        case swiftDataId = "id"
        case athleteId
        case seasonId
        case date
        case createdAt
        case updatedAt
        case version
        case isDeleted
    }
}

struct FirestorePracticeNote: Codable, Identifiable {
    var id: String?
    let swiftDataId: String
    let practiceId: String
    let content: String
    let createdAt: Date?
    let updatedAt: Date?
    let isDeleted: Bool

    enum CodingKeys: String, CodingKey {
        case swiftDataId = "id"
        case practiceId
        case content
        case createdAt
        case updatedAt
        case isDeleted
    }
}

struct FirestorePhoto: Codable, Identifiable {
    var id: String?
    let swiftDataId: String
    let fileName: String
    let athleteId: String
    let uploadedBy: String
    let downloadURL: String?
    let caption: String?
    let gameId: String?
    let practiceId: String?
    let seasonId: String?
    let createdAt: Date?
    let updatedAt: Date?
    let isDeleted: Bool

    enum CodingKeys: String, CodingKey {
        case swiftDataId = "id"
        case fileName
        case athleteId
        case uploadedBy
        case downloadURL
        case caption
        case gameId
        case practiceId
        case seasonId
        case createdAt
        case updatedAt
        case isDeleted
    }
}

struct FirestoreCoach: Codable, Identifiable {
    var id: String?
    let swiftDataId: String
    let athleteId: String
    let name: String
    let role: String
    let email: String
    let phone: String?
    let notes: String?
    let firebaseCoachID: String?
    let invitationStatus: String?
    let createdAt: Date?
    let updatedAt: Date?
    let isDeleted: Bool

    enum CodingKeys: String, CodingKey {
        case swiftDataId = "id"
        case athleteId
        case name
        case role
        case email
        case phone
        case notes
        case firebaseCoachID
        case invitationStatus
        case createdAt
        case updatedAt
        case isDeleted
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
