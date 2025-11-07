//
//  VideoCloudManager.swift
//  PlayerPath
//
//  Cross-platform video storage manager using Firebase
//

import Foundation
import FirebaseStorage
import FirebaseFirestore
import SwiftData

@MainActor
class VideoCloudManager: ObservableObject {
    private let storage = Storage.storage()
    private let firestore = Firestore.firestore()
    
    @Published var uploadProgress: [UUID: Double] = [:]
    @Published var isUploading: [UUID: Bool] = [:]
    
    // MARK: - Upload Video
    func uploadVideo(_ videoClip: VideoClip, athlete: Athlete) async throws -> String {
        let videoURL = URL(fileURLWithPath: videoClip.filePath)
        
        // Create storage reference
        let fileName = "\(athlete.id.uuidString)/\(videoClip.id.uuidString).mov"
        let storageRef = storage.reference().child("videos/\(fileName)")
        
        // Update UI state
        isUploading[videoClip.id] = true
        uploadProgress[videoClip.id] = 0.0
        
        // Create upload task with progress tracking
        let uploadTask = storageRef.putFile(from: videoURL, metadata: nil)
        
        // Observe upload progress
        uploadTask.observe(.progress) { [weak self] snapshot in
            guard let self = self,
                  let progress = snapshot.progress else { return }
            
            Task { @MainActor in
                self.uploadProgress[videoClip.id] = progress.fractionCompleted
            }
        }
        
        // Wait for upload completion
        let result = try await uploadTask
        let downloadURL = try await result.reference.downloadURL()
        
        // Save metadata to Firestore
        try await saveVideoMetadata(videoClip: videoClip, 
                                  athlete: athlete, 
                                  downloadURL: downloadURL.absoluteString)
        
        // Update UI state
        isUploading[videoClip.id] = false
        uploadProgress[videoClip.id] = 1.0
        
        return downloadURL.absoluteString
    }
    
    // MARK: - Save Video Metadata to Firestore
    private func saveVideoMetadata(videoClip: VideoClip, athlete: Athlete, downloadURL: String) async throws {
        let videoData: [String: Any] = [
            "id": videoClip.id.uuidString,
            "fileName": videoClip.fileName,
            "downloadURL": downloadURL,
            "createdAt": Timestamp(date: videoClip.createdAt),
            "isHighlight": videoClip.isHighlight,
            "athleteID": athlete.id.uuidString,
            "athleteName": athlete.name,
            "playResult": videoClip.playResult?.type.rawValue ?? NSNull(),
            "gameOpponent": videoClip.game?.opponent ?? NSNull(),
            "practiceDate": videoClip.practice?.date ?? NSNull()
        ]
        
        try await firestore
            .collection("users")
            .document(athlete.user?.id.uuidString ?? "unknown")
            .collection("athletes")
            .document(athlete.id.uuidString)
            .collection("videoClips")
            .document(videoClip.id.uuidString)
            .setData(videoData)
    }
    
    // MARK: - Download Video
    func downloadVideo(from url: String, to localPath: String) async throws {
        let downloadURL = URL(string: url)!
        let localURL = URL(fileURLWithPath: localPath)
        
        let (tempURL, _) = try await URLSession.shared.download(from: downloadURL)
        
        // Move to final location
        if FileManager.default.fileExists(atPath: localURL.path) {
            try FileManager.default.removeItem(at: localURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: localURL)
    }
    
    // MARK: - Sync Videos for Athlete
    func syncVideos(for athlete: Athlete) async throws -> [VideoClipMetadata] {
        let snapshot = try await firestore
            .collection("users")
            .document(athlete.user?.id.uuidString ?? "unknown")
            .collection("athletes")
            .document(athlete.id.uuidString)
            .collection("videoClips")
            .getDocuments()
        
        var videoMetadata: [VideoClipMetadata] = []
        
        for document in snapshot.documents {
            let data = document.data()
            
            let metadata = VideoClipMetadata(
                id: UUID(uuidString: data["id"] as? String ?? "") ?? UUID(),
                fileName: data["fileName"] as? String ?? "",
                downloadURL: data["downloadURL"] as? String ?? "",
                createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                isHighlight: data["isHighlight"] as? Bool ?? false,
                playResult: data["playResult"] as? String,
                gameOpponent: data["gameOpponent"] as? String,
                athleteName: data["athleteName"] as? String ?? ""
            )
            
            videoMetadata.append(metadata)
        }
        
        return videoMetadata
    }
    
    // MARK: - Delete Video
    func deleteVideo(_ videoClip: VideoClip, athlete: Athlete) async throws {
        // Delete from Firebase Storage
        let fileName = "\(athlete.id.uuidString)/\(videoClip.id.uuidString).mov"
        let storageRef = storage.reference().child("videos/\(fileName)")
        try await storageRef.delete()
        
        // Delete from Firestore
        try await firestore
            .collection("users")
            .document(athlete.user?.id.uuidString ?? "unknown")
            .collection("athletes")
            .document(athlete.id.uuidString)
            .collection("videoClips")
            .document(videoClip.id.uuidString)
            .delete()
    }
}

// MARK: - Video Metadata Structure
struct VideoClipMetadata {
    let id: UUID
    let fileName: String
    let downloadURL: String
    let createdAt: Date
    let isHighlight: Bool
    let playResult: String?
    let gameOpponent: String?
    let athleteName: String
}

// MARK: - Enhanced VideoClip Model
extension VideoClip {
    var cloudURL: String? {
        get { 
            // You'll need to add this property to your SwiftData model
            return nil // Placeholder - add cloudURL property to your model
        }
        set { 
            // Set the cloud URL when uploaded
        }
    }
    
    var isUploaded: Bool {
        return cloudURL != nil && !cloudURL!.isEmpty
    }
}