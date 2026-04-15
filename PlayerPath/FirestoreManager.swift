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

let firestoreLog = Logger(subsystem: "com.playerpath.app", category: "Firestore")

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

    // MARK: - Cloud Functions

    /// Base URL for HTTPS-invoked Cloud Functions. Centralized so the project
    /// ID / region can be changed in one place rather than across every
    /// `acceptInvitation` / `syncSubscriptionTier` call site.
    private static let cloudFunctionBase = "https://us-central1-playerpath-159b2.cloudfunctions.net"

    /// Returns the HTTPS URL for a Cloud Function by name.
    static func cloudFunctionURL(_ name: String) -> URL {
        URL(string: "\(cloudFunctionBase)/\(name)")!
    }
}
