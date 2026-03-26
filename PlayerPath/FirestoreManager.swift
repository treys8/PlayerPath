//
//  FirestoreManager.swift
//  PlayerPath
//
//  Core Firestore service singleton
//  Methods are organized in extension files:
//    +SharedFolders, +VideoMetadata, +Annotations,
//    +Invitations, +UserProfile, +EntitySync
//

import Foundation
import FirebaseFirestore
import Combine
import os

nonisolated(unsafe) let firestoreLog = Logger(subsystem: "com.playerpath.app", category: "Firestore")

/// Main service for all Firestore operations
/// Handles shared folders, video metadata, annotations, and invitations
@MainActor
class FirestoreManager: ObservableObject {

    static let shared = FirestoreManager()

    let db = Firestore.firestore()

    // Published state for reactive UI
    @Published var errorMessage: String?

    private init() {
        // Firestore settings (cache, offline persistence) are configured in
        // PlayerPathApp.init() immediately after FirebaseApp.configure(),
        // before any code accesses the Firestore instance.
    }
}
