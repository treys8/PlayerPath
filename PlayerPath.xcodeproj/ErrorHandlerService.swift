//
//  ErrorHandlerService.swift
//  PlayerPath
//
//  Centralized error handling and user notification service
//

import Foundation
import SwiftUI
import os.log

@MainActor
class ErrorHandlerService: ObservableObject {
    @Published var currentError: PlayerPathError?
    @Published var showingErrorAlert = false
    @Published var showingRetryDialog = false
    @Published var errorHistory: [ErrorLogEntry] = []
    
    private let logger = Logger(subsystem: "PlayerPath", category: "ErrorHandler")
    private var retryAction: (() async -> Void)?
    
    // MARK: - Configuration
    private let maxErrorHistoryCount = 50
    private let shouldLogAllErrors = true
    private let shouldSendAnalytics = false // Set to true when analytics are implemented
    
    // MARK: - Public Interface
    
    /// Handle an error with context information
    func handle(_ error: Error, context: String = "", canRetry: Bool = false, retryAction: (() async -> Void)? = nil) {
        let playerPathError = convertToPlayerPathError(error, context: context)
        
        // Log the error
        logError(playerPathError, context: context)
        
        // Add to history
        addToHistory(playerPathError, context: context)
        
        // Show to user if appropriate
        if shouldShowToUser(playerPathError) {
            currentError = playerPathError
            
            if canRetry && retryAction != nil {
                self.retryAction = retryAction
                showingRetryDialog = true
            } else {
                showingErrorAlert = true
            }
        }
        
        // Send analytics if enabled
        if shouldSendAnalytics {
            sendErrorAnalytics(playerPathError, context: context)
        }
        
        // Perform automatic recovery if possible
        Task {
            await attemptAutomaticRecovery(for: playerPathError)
        }
    }
    
    /// Handle an error with a completion handler for success/failure
    func handle<T>(_ result: Result<T, Error>, context: String = "", canRetry: Bool = false, retryAction: (() async -> Void)? = nil) -> T? {
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            handle(error, context: context, canRetry: canRetry, retryAction: retryAction)
            return nil
        }
    }
    
    /// Execute an operation with automatic error handling
    func withErrorHandling<T>(
        context: String,
        canRetry: Bool = false,
        operation: () async throws -> T
    ) async -> Result<T, PlayerPathError> {
        do {
            let result = try await operation()
            return .success(result)
        } catch {
            let playerPathError = convertToPlayerPathError(error, context: context)
            
            if canRetry {
                handle(playerPathError, context: context, canRetry: true) {
                    _ = await withErrorHandling(context: context, canRetry: false, operation: operation)
                }
            } else {
                handle(playerPathError, context: context)
            }
            
            return .failure(playerPathError)
        }
    }
    
    /// Retry the last failed operation
    func retryLastOperation() {
        guard let retryAction = retryAction else { return }
        
        showingRetryDialog = false
        self.retryAction = nil
        
        Task {
            await retryAction()
        }
    }
    
    /// Dismiss current error
    func dismissError() {
        currentError = nil
        showingErrorAlert = false
        showingRetryDialog = false
        retryAction = nil
    }
    
    /// Clear error history
    func clearErrorHistory() {
        errorHistory.removeAll()
    }
    
    // MARK: - Private Implementation
    
    private func convertToPlayerPathError(_ error: Error, context: String) -> PlayerPathError {
        // Return if already a PlayerPath error
        if let playerPathError = error as? PlayerPathError {
            return playerPathError
        }
        
        // Convert CloudKit errors
        if let ckError = error as? CKError {
            return PlayerPathError.from(cloudKitError: ckError)
        }
        
        // Convert Firebase Auth errors
        if let authError = error as? NSError, authError.domain == "FIRAuthErrorDomain" {
            return PlayerPathError.from(firebaseAuthError: authError)
        }
        
        // Convert URL errors
        if let urlError = error as? URLError {
            return convertURLError(urlError)
        }
        
        // Convert common system errors
        if let nsError = error as? NSError {
            return convertNSError(nsError, context: context)
        }
        
        // Fallback to unknown error
        return .unknownError(error)
    }
    
    private func convertURLError(_ error: URLError) -> PlayerPathError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return .networkUnavailable
        case .timedOut:
            return .requestTimeout
        case .cannotFindHost, .cannotConnectToHost:
            return .serverError(code: error.errorCode, message: "Cannot connect to server")
        default:
            return .networkUnavailable
        }
    }
    
    private func convertNSError(_ error: NSError, context: String) -> PlayerPathError {
        switch error.domain {
        case NSCocoaErrorDomain:
            switch error.code {
            case NSFileReadNoSuchFileError:
                return .fileNotFound(path: error.localizedDescription)
            case NSFileWriteFileExistsError:
                return .fileWriteFailed(path: context)
            case NSValidationErrorMaximum, NSValidationErrorMinimum:
                return .validationFailed(field: context, reason: error.localizedDescription)
            default:
                return .unknownError(error)
            }
        case AVFoundationErrorDomain:
            return .videoProcessingFailed(reason: error.localizedDescription)
        default:
            return .unknownError(error)
        }
    }
    
    private func shouldShowToUser(_ error: PlayerPathError) -> Bool {
        switch error {
        case .cloudKitRecordNotFound:
            return false // This is often expected for new records
        case .configurationError:
            return false // Development/config issues shouldn't bother users
        case .unknownError(let underlyingError):
            // Don't show generic system errors that users can't act on
            return !(underlyingError is NSError && (underlyingError as! NSError).domain == NSCocoaErrorDomain)
        default:
            return true
        }
    }
    
    private func logError(_ error: PlayerPathError, context: String) {
        let contextString = context.isEmpty ? "" : " [\(context)]"
        logger.error("PlayerPath Error\(contextString): \(error.localizedDescription)")
        
        if let failureReason = error.failureReason {
            logger.error("Failure reason: \(failureReason)")
        }
        
        if shouldLogAllErrors {
            print("🚨 PlayerPath Error\(contextString): \(error)")
        }
    }
    
    private func addToHistory(_ error: PlayerPathError, context: String) {
        let entry = ErrorLogEntry(
            error: error,
            context: context,
            timestamp: Date()
        )
        
        errorHistory.insert(entry, at: 0)
        
        // Limit history size
        if errorHistory.count > maxErrorHistoryCount {
            errorHistory = Array(errorHistory.prefix(maxErrorHistoryCount))
        }
    }
    
    private func sendErrorAnalytics(_ error: PlayerPathError, context: String) {
        // TODO: Implement analytics when available
        // Analytics.shared.trackError(error, context: context)
    }
    
    private func attemptAutomaticRecovery(for error: PlayerPathError) async {
        switch error {
        case .cloudKitNotSignedIn:
            // Could potentially prompt for iCloud sign-in
            break
        case .networkUnavailable:
            // Could implement network retry logic
            break
        case .quotaExceeded:
            // Could suggest cleanup or storage management
            break
        default:
            break
        }
    }
}

// MARK: - Error Log Entry
struct ErrorLogEntry: Identifiable {
    let id = UUID()
    let error: PlayerPathError
    let context: String
    let timestamp: Date
    
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: timestamp)
    }
}

// MARK: - SwiftUI Integration
extension ErrorHandlerService {
    
    /// Create error alert for SwiftUI views
    func errorAlert() -> Alert {
        Alert(
            title: Text("Error"),
            message: Text(currentError?.localizedDescription ?? "An unknown error occurred"),
            dismissButton: .default(Text("OK")) {
                dismissError()
            }
        )
    }
    
    /// Create retry dialog for SwiftUI views
    func retryAlert() -> Alert {
        Alert(
            title: Text("Error"),
            message: Text(currentError?.localizedDescription ?? "An unknown error occurred"),
            primaryButton: .default(Text("Retry")) {
                retryLastOperation()
            },
            secondaryButton: .cancel {
                dismissError()
            }
        )
    }
}

// MARK: - View Modifier for Easy Integration
struct ErrorHandlingModifier: ViewModifier {
    @ObservedObject var errorHandler: ErrorHandlerService
    
    func body(content: Content) -> some View {
        content
            .alert("Error", isPresented: $errorHandler.showingErrorAlert) {
                Button("OK") {
                    errorHandler.dismissError()
                }
                
                if let recoverySuggestion = errorHandler.currentError?.recoverySuggestion {
                    Button("Help") {
                        // Could open help or settings
                        print("Help: \(recoverySuggestion)")
                    }
                }
            } message: {
                if let error = errorHandler.currentError {
                    Text(error.localizedDescription)
                }
            }
            .alert("Retry?", isPresented: $errorHandler.showingRetryDialog) {
                Button("Retry") {
                    errorHandler.retryLastOperation()
                }
                Button("Cancel", role: .cancel) {
                    errorHandler.dismissError()
                }
            } message: {
                if let error = errorHandler.currentError {
                    Text(error.localizedDescription)
                }
            }
    }
}

extension View {
    func errorHandling(_ errorHandler: ErrorHandlerService) -> some View {
        modifier(ErrorHandlingModifier(errorHandler: errorHandler))
    }
}