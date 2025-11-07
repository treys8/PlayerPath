//
//  CloudKitManager.swift
//  PlayerPath
//
//  Created by Assistant on 10/29/25.
//

import Foundation
import CloudKit
import SwiftUI

@MainActor
class CloudKitManager: ObservableObject {
    // Use private database for user data
    private let container = CKContainer.default()
    private var privateDatabase: CKDatabase { container.privateCloudDatabase }
    
    @Published var isSignedInToiCloud = false
    @Published var cloudKitError: String?
    
    init() {
        checkiCloudStatus()
    }
    
    // MARK: - iCloud Account Status
    
    func checkiCloudStatus() {
        Task {
            do {
                let status = try await container.accountStatus()
                await MainActor.run {
                    self.isSignedInToiCloud = (status == .available)
                    print("CloudKit: iCloud status - \(status)")
                    
                    if status != .available {
                        self.cloudKitError = self.getStatusMessage(for: status)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isSignedInToiCloud = false
                    self.cloudKitError = "Failed to check iCloud status: \(error.localizedDescription)"
                    print("CloudKit: Error checking iCloud status - \(error)")
                }
            }
        }
    }
    
    private func getStatusMessage(for status: CKAccountStatus) -> String {
        switch status {
        case .couldNotDetermine:
            return "Could not determine iCloud status"
        case .noAccount:
            return "No iCloud account found. Please sign in to iCloud in Settings."
        case .restricted:
            return "iCloud account is restricted"
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable"
        case .available:
            return ""
        @unknown default:
            return "Unknown iCloud status"
        }
    }
}

// MARK: - CloudKit Record Types

extension CloudKitManager {
    // We'll add user preferences and data sync methods here in the next steps
}