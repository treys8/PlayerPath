//
//  ErrorHandlerService.swift
//  PlayerPath
//
//  Created by Assistant on 10/29/25.
//

import Foundation
import SwiftUI
import os.log

@MainActor
class ErrorHandlerService: ObservableObject {
    private let logger = Logger(subsystem: "PlayerPath", category: "ErrorHandlerService")
    
    @Published var currentError: PlayerPathError?
    @Published var isShowingError = false
    
    private var retryAttempts: [String: Int] = [:]
    private let maxRetryAttempts = 3
    
    // MARK: - Error Handling
    
    /// Handle an error with optional context and automatic retry logic
    func handle(_ error: PlayerPathError, context: String? = nil, canRetry: Bool = false) {
        let contextString = context ?? "Unknown context"
        logger.error("Error in \(contextString): \(error.localizedDescription)")
        
        // Log additional error details
        if let recoverySuggestion = error.recoverySuggestion {
            logger.info("Recovery suggestion: \(recoverySuggestion)")
        }
        
        // Update UI state
        currentError = error
        isShowingError = true
        
        // Handle retry logic if applicable
        if canRetry && error.isRetryable {
            let retryKey = "\(contextString)_\(error.id)"
            let attempts = retryAttempts[retryKey, default: 0]
            
            if attempts < maxRetryAttempts {
                retryAttempts[retryKey] = attempts + 1
                logger.info("Retry attempt \(attempts + 1)/\(maxRetryAttempts) for \(retryKey)")
            } else {
                logger.error("Max retry attempts reached for \(retryKey)")
                retryAttempts.removeValue(forKey: retryKey)
            }
        }
    }
    
    /// Clear the current error
    func clearError() {
        currentError = nil
        isShowingError = false
    }
    
    /// Reset retry attempts for a specific context
    func resetRetryAttempts(for context: String) {
        let keysToRemove = retryAttempts.keys.filter { $0.hasPrefix(context) }
        for key in keysToRemove {
            retryAttempts.removeValue(forKey: key)
        }
    }
    
    // MARK: - Async Error Handling with Results
    
    /// Execute an async operation with automatic error handling
    func withErrorHandling<T>(
        context: String,
        canRetry: Bool = false,
        operation: () async throws -> T
    ) async -> Result<T, PlayerPathError> {
        do {
            let result = try await operation()
            
            // Reset retry attempts on success
            if canRetry {
                resetRetryAttempts(for: context)
            }
            
            return .success(result)
        } catch let error as PlayerPathError {
            handle(error, context: context, canRetry: canRetry)
            return .failure(error)
        } catch {
            let playerPathError = PlayerPathError.unknownError(error.localizedDescription)
            handle(playerPathError, context: context, canRetry: canRetry)
            return .failure(playerPathError)
        }
    }
    
    /// Check if operation can be retried
    func canRetry(context: String, errorId: String) -> Bool {
        let retryKey = "\(context)_\(errorId)"
        let attempts = retryAttempts[retryKey, default: 0]
        return attempts < maxRetryAttempts
    }
    
    /// Get current retry attempt count
    func getRetryAttempt(context: String, errorId: String) -> Int {
        let retryKey = "\(context)_\(errorId)"
        return retryAttempts[retryKey, default: 0]
    }
}

// MARK: - Error Display View
struct PlayerPathErrorView: View {
    let error: PlayerPathError
    let onDismiss: () -> Void
    let onRetry: (() -> Void)?
    
    init(error: PlayerPathError, onDismiss: @escaping () -> Void, onRetry: (() -> Void)? = nil) {
        self.error = error
        self.onDismiss = onDismiss
        self.onRetry = onRetry
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: errorIcon)
                    .foregroundColor(.red)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Error")
                        .font(.headline)
                        .foregroundColor(.red)
                    
                    if let description = error.errorDescription {
                        Text(description)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                    }
                }
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .font(.title3)
                }
            }
            
            // Recovery suggestion
            if let recovery = error.recoverySuggestion {
                Text(recovery)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Action buttons
            HStack(spacing: 12) {
                Button("Dismiss") {
                    onDismiss()
                }
                .foregroundColor(.secondary)
                
                if let onRetry = onRetry, error.isRetryable {
                    Button("Retry") {
                        onRetry()
                        onDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
        .padding(.horizontal)
    }
    
    private var errorIcon: String {
        switch error {
        case .videoUploadFailed, .networkError:
            return "wifi.exclamationmark"
        case .videoProcessingFailed, .videoFileCorrupted:
            return "exclamationmark.triangle.fill"
        case .videoFileTooLarge, .videoFileTooSmall:
            return "doc.badge.exclamationmark"
        case .videoDurationTooLong, .videoDurationTooShort:
            return "clock.badge.exclamationmark"
        case .unsupportedVideoFormat:
            return "video.badge.exclamationmark"
        case .videoFileNotFound:
            return "doc.badge.questionmark"
        case .authenticationRequired:
            return "person.badge.exclamationmark"
        case .cloudStorageFull:
            return "icloud.and.arrow.up"
        case .unknownError:
            return "questionmark.circle.fill"
        }
    }
}