//
//  ErrorHandlerService.swift
//  PlayerPath
//
//  Created by Assistant on 10/29/25.
//

import Foundation
import SwiftUI
import os.log

// MARK: - PlayerPath Error Types

enum PlayerPathError: LocalizedError, Identifiable, Equatable {
    // Video-related errors
    case videoUploadFailed(reason: String)
    case videoProcessingFailed(reason: String)
    case videoFileCorrupted
    case videoFileTooLarge(size: Int64, maxSize: Int64)
    case videoFileTooSmall
    case videoDurationTooLong(duration: TimeInterval, maxDuration: TimeInterval)
    case videoDurationTooShort(duration: TimeInterval, minDuration: TimeInterval)
    case unsupportedVideoFormat(format: String?)
    case videoFileNotFound
    
    // Network and connectivity
    case networkError(underlying: Error)
    case noInternetConnection
    case slowConnection
    case requestTimeout
    
    // Authentication
    case authenticationRequired
    case sessionExpired
    case permissionDenied
    
    // Storage
    case cloudStorageFull
    case localStorageFull
    case insufficientSpace(required: Int64, available: Int64)
    
    // Data errors
    case dataCorrupted(type: String)
    case syncFailed(reason: String)
    case saveError(underlying: Error)
    
    // Generic
    case unknownError(String)
    
    // MARK: - Equatable Conformance
    static func == (lhs: PlayerPathError, rhs: PlayerPathError) -> Bool {
        lhs.id == rhs.id
    }
    
    var id: String {
        switch self {
        case .videoUploadFailed: return "video_upload_failed"
        case .videoProcessingFailed: return "video_processing_failed"
        case .videoFileCorrupted: return "video_file_corrupted"
        case .videoFileTooLarge: return "video_file_too_large"
        case .videoFileTooSmall: return "video_file_too_small"
        case .videoDurationTooLong: return "video_duration_too_long"
        case .videoDurationTooShort: return "video_duration_too_short"
        case .unsupportedVideoFormat: return "unsupported_video_format"
        case .videoFileNotFound: return "video_file_not_found"
        case .networkError: return "network_error"
        case .noInternetConnection: return "no_internet_connection"
        case .slowConnection: return "slow_connection"
        case .requestTimeout: return "request_timeout"
        case .authenticationRequired: return "authentication_required"
        case .sessionExpired: return "session_expired"
        case .permissionDenied: return "permission_denied"
        case .cloudStorageFull: return "cloud_storage_full"
        case .localStorageFull: return "local_storage_full"
        case .insufficientSpace: return "insufficient_space"
        case .dataCorrupted: return "data_corrupted"
        case .syncFailed: return "sync_failed"
        case .saveError: return "save_error"
        case .unknownError: return "unknown_error"
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .videoUploadFailed(let reason):
            return "Video upload failed: \(reason)"
        case .videoProcessingFailed(let reason):
            return "Video processing failed: \(reason)"
        case .videoFileCorrupted:
            return "The video file appears to be corrupted"
        case .videoFileTooLarge(let size, let maxSize):
            return "Video file is too large (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))). Maximum size is \(ByteCountFormatter.string(fromByteCount: maxSize, countStyle: .file))"
        case .videoFileTooSmall:
            return "Video file is too small"
        case .videoDurationTooLong(let duration, let maxDuration):
            return "Video is too long (\(Int(duration))s). Maximum duration is \(Int(maxDuration))s"
        case .videoDurationTooShort(let duration, let minDuration):
            return "Video is too short (\(Int(duration))s). Minimum duration is \(Int(minDuration))s"
        case .unsupportedVideoFormat(let format):
            if let format = format {
                return "Unsupported video format: \(format)"
            } else {
                return "Unsupported video format"
            }
        case .videoFileNotFound:
            return "Video file could not be found"
        case .networkError(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        case .noInternetConnection:
            return "No internet connection available"
        case .slowConnection:
            return "Connection is too slow to complete this operation"
        case .requestTimeout:
            return "Request timed out"
        case .authenticationRequired:
            return "Authentication required"
        case .sessionExpired:
            return "Your session has expired"
        case .permissionDenied:
            return "Permission denied"
        case .cloudStorageFull:
            return "Cloud storage is full"
        case .localStorageFull:
            return "Device storage is full"
        case .insufficientSpace(let required, let available):
            return "Not enough space. Need \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file)) but only \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file)) available"
        case .dataCorrupted(let type):
            return "\(type) data is corrupted"
        case .syncFailed(let reason):
            return "Sync failed: \(reason)"
        case .saveError(let underlying):
            return "Failed to save: \(underlying.localizedDescription)"
        case .unknownError(let message):
            return "Unknown error: \(message)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .videoUploadFailed, .syncFailed:
            return "Check your internet connection and try again."
        case .videoProcessingFailed:
            return "Try selecting a different video or restart the app."
        case .videoFileCorrupted, .dataCorrupted:
            return "Please select a different file."
        case .videoFileTooLarge:
            return "Please select a smaller video or compress the current video."
        case .videoFileTooSmall:
            return "Please select a longer video."
        case .videoDurationTooLong:
            return "Please trim your video to be shorter."
        case .videoDurationTooShort:
            return "Please select a longer video."
        case .unsupportedVideoFormat:
            return "Please convert your video to a supported format (MP4, MOV)."
        case .videoFileNotFound:
            return "Please select the video again."
        case .networkError, .requestTimeout:
            return "Check your internet connection and try again."
        case .noInternetConnection:
            return "Connect to the internet to continue."
        case .slowConnection:
            return "Connect to a faster network or try again later."
        case .authenticationRequired:
            return "Please sign in to continue."
        case .sessionExpired:
            return "Please sign in again."
        case .permissionDenied:
            return "Grant the required permissions in Settings."
        case .cloudStorageFull:
            return "Free up space in your cloud storage or upgrade your plan."
        case .localStorageFull, .insufficientSpace:
            return "Free up space on your device by deleting unused files."
        case .saveError:
            return "Please try saving again."
        case .unknownError:
            return "Please try again or restart the app."
        }
    }
    
    var isRetryable: Bool {
        switch self {
        case .videoUploadFailed, .videoProcessingFailed, .networkError, 
             .noInternetConnection, .slowConnection, .requestTimeout,
             .syncFailed, .saveError, .unknownError:
            return true
        case .videoFileCorrupted, .videoFileTooLarge, .videoFileTooSmall, 
             .videoDurationTooLong, .videoDurationTooShort, .unsupportedVideoFormat, 
             .videoFileNotFound, .authenticationRequired, .sessionExpired,
             .permissionDenied, .cloudStorageFull, .localStorageFull,
             .insufficientSpace, .dataCorrupted:
            return false
        }
    }
    
    var severity: ErrorHandlerService.ErrorSeverity {
        switch self {
        case .videoUploadFailed, .videoProcessingFailed, .syncFailed:
            return .medium
        case .networkError, .requestTimeout:
            return .high
        case .noInternetConnection:
            return .critical
        case .slowConnection:
            return .medium
        case .authenticationRequired, .sessionExpired, .permissionDenied:
            return .high
        case .cloudStorageFull, .localStorageFull:
            return .critical
        case .insufficientSpace:
            return .high
        case .videoFileCorrupted, .dataCorrupted, .unknownError:
            return .high
        case .videoFileTooLarge, .videoFileTooSmall, .videoDurationTooLong, 
             .videoDurationTooShort, .unsupportedVideoFormat, .videoFileNotFound,
             .saveError:
            return .medium
        }
    }
}

@MainActor
@Observable
final class ErrorHandlerService {
    static let shared = ErrorHandlerService()
    
    private let logger = Logger(subsystem: "PlayerPath", category: "ErrorHandlerService")
    
    private(set) var currentError: PlayerPathError?
    private(set) var isShowingError = false
    private(set) var errorQueue: [PlayerPathError] = []
    private(set) var criticalErrors: [PlayerPathError] = []
    
    // Enhanced retry and recovery
    private var retryAttempts: [String: Int] = [:]
    private var errorHistory: [String: [Date]] = [:]
    private var retryTimers: [String: Timer] = [:]
    private var retryCallbacks: [String: () async -> Bool] = [:]

    // Configuration
    private let maxRetryAttempts = 3
    private let errorHistoryLimit = 10
    private let retryBackoffBase: TimeInterval = 2.0 // Exponential backoff base
    private let maxRetryDelay: TimeInterval = 60.0 // Max 1 minute delay
    
    // Analytics and reporting
    private var errorAnalytics: [String: ErrorAnalytics] = [:]
    
    struct ErrorAnalytics {
        var occurrenceCount: Int = 0
        var firstOccurrence: Date = Date()
        var lastOccurrence: Date = Date()
        var userDismissalCount: Int = 0
        var successfulRetryCount: Int = 0
        var contexts: Set<String> = []
    }
    
    // MARK: - Convenience Factory Methods
    
    /// Convert common Swift/Foundation errors to PlayerPathError
    static func from(_ error: Error) -> PlayerPathError {
        // Check if already a PlayerPathError
        if let playerPathError = error as? PlayerPathError {
            return playerPathError
        }
        
        // Handle URL/Network errors
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return .noInternetConnection
            case .timedOut:
                return .requestTimeout
            case .networkConnectionLost:
                return .slowConnection
            default:
                return .networkError(underlying: urlError)
            }
        }
        
        // Handle NSError domain checks
        let nsError = error as NSError
        
        // CloudKit errors
        if nsError.domain == "CKErrorDomain" {
            // CKError codes
            switch nsError.code {
            case 2: // .networkUnavailable
                return .noInternetConnection
            case 4: // .networkFailure
                return .networkError(underlying: error)
            case 27: // .quotaExceeded
                return .cloudStorageFull
            default:
                return .unknownError(error.localizedDescription)
            }
        }
        
        // File system errors
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileNoSuchFileError:
                return .videoFileNotFound
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
                return .permissionDenied
            default:
                return .saveError(underlying: error)
            }
        }
        
        // Default unknown error
        return .unknownError(error.localizedDescription)
    }
    
    // MARK: - Enhanced Error Handling
    
    /// Handle an error with comprehensive context and recovery options
    func handle(
        _ error: PlayerPathError,
        context: String? = nil,
        severity: ErrorSeverity = .medium,
        canRetry: Bool = false,
        autoRetry: Bool = false,
        userInfo: [String: Any] = [:]
    ) {
        let contextString = context ?? "Unknown context"
        let retryKey = "\(contextString)_\(error.id)"
        
        // Update analytics
        updateErrorAnalytics(error, context: contextString)
        
        // Log with appropriate level based on severity
        switch severity {
        case .low:
            logger.info("Low severity error in \(contextString): \(error.localizedDescription)")
        case .medium:
            logger.notice("Medium severity error in \(contextString): \(error.localizedDescription)")
        case .high:
            logger.error("High severity error in \(contextString): \(error.localizedDescription)")
        case .critical:
            logger.critical("CRITICAL ERROR in \(contextString): \(error.localizedDescription)")
            criticalErrors.append(error)
        }
        
        // Handle error history for pattern detection
        recordErrorOccurrence(retryKey)
        
        // Determine if we should show this error to the user
        let shouldShow = shouldShowError(error, severity: severity)
        
        if shouldShow {
            // Queue error for display if we're already showing one
            if isShowingError {
                errorQueue.append(error)
            } else {
                displayError(error, context: contextString, canRetry: canRetry)
            }
        }
        
        // Handle automatic retry logic
        if autoRetry && error.isRetryable && canRetryError(retryKey) {
            scheduleRetry(retryKey: retryKey, error: error, context: contextString)
        }
        
        // Check for error patterns that might indicate system issues
        detectErrorPatterns(error, context: contextString)
    }
    
    enum ErrorSeverity {
        case low      // Non-blocking, background failures
        case medium   // User-facing but recoverable
        case high     // Blocks user workflows
        case critical // App stability issues
        
        var showsToUser: Bool {
            switch self {
            case .low: return false
            case .medium, .high, .critical: return true
            }
        }
        
        var requiresImmediateAction: Bool {
            switch self {
            case .critical: return true
            default: return false
            }
        }
    }
    
    private func shouldShowError(_ error: PlayerPathError, severity: ErrorSeverity) -> Bool {
        // Don't show low severity errors
        if !severity.showsToUser {
            return false
        }
        
        // Always show critical errors
        if severity == .critical {
            return true
        }
        
        // Don't spam the user with the same error
        let analytics = errorAnalytics[error.id]
        if let analytics = analytics,
           analytics.occurrenceCount > 3,
           Date().timeIntervalSince(analytics.lastOccurrence) < 60 {
            return false // Don't show if occurred >3 times in last minute
        }
        
        return true
    }
    
    private func displayError(_ error: PlayerPathError, context: String, canRetry: Bool) {
        self.currentError = error
        self.isShowingError = true
        
        // Auto-dismiss non-critical errors after delay
        if !criticalErrors.contains(where: { $0.id == error.id }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                if self?.currentError?.id == error.id {
                    self?.dismissError(userInitiated: false)
                }
            }
        }
    }
    
    private func updateErrorAnalytics(_ error: PlayerPathError, context: String) {
        if var analytics = errorAnalytics[error.id] {
            analytics.occurrenceCount += 1
            analytics.lastOccurrence = Date()
            analytics.contexts.insert(context)
            errorAnalytics[error.id] = analytics
        } else {
            errorAnalytics[error.id] = ErrorAnalytics(
                occurrenceCount: 1,
                firstOccurrence: Date(),
                lastOccurrence: Date(),
                userDismissalCount: 0,
                successfulRetryCount: 0,
                contexts: [context]
            )
        }
    }
    
    private func recordErrorOccurrence(_ retryKey: String) {
        let now = Date()
        if var history = errorHistory[retryKey] {
            history.append(now)
            // Keep only last 10 occurrences
            if history.count > errorHistoryLimit {
                history.removeFirst()
            }
            errorHistory[retryKey] = history
        } else {
            errorHistory[retryKey] = [now]
        }
    }
    
    private func detectErrorPatterns(_ error: PlayerPathError, context: String) {
        let retryKey = "\(context)_\(error.id)"
        
        guard let history = errorHistory[retryKey], history.count >= 3 else { return }
        
        // Check for rapid error occurrence (3+ errors in 60 seconds)
        let recentErrors = history.filter { Date().timeIntervalSince($0) < 60 }
        if recentErrors.count >= 3 {
            logger.warning("Error pattern detected: \(error.id) occurred \(recentErrors.count) times in last minute in context: \(context)")
            
            // Could trigger additional actions like:
            // - Disabling automatic retries
            // - Sending telemetry
            // - Showing different UI
        }
    }
    
    /// Clear the current error and show next in queue
    func dismissError(userInitiated: Bool = true) {
        if let currentError = currentError, userInitiated {
            // Update analytics for user dismissal
            if var analytics = errorAnalytics[currentError.id] {
                analytics.userDismissalCount += 1
                errorAnalytics[currentError.id] = analytics
            }
        }
        
        self.currentError = nil
        self.isShowingError = false
        
        // Show next error in queue if any
        if let nextError = errorQueue.first {
            errorQueue.removeFirst()
            displayError(nextError, context: "Queued", canRetry: nextError.isRetryable)
        }
    }
    
    /// Clear all errors and queued errors
    func clearAllErrors() {
        self.currentError = nil
        self.isShowingError = false
        self.errorQueue.removeAll()
        
        // Cancel any pending retry timers
        retryTimers.values.forEach { $0.invalidate() }
        retryTimers.removeAll()
        retryCallbacks.removeAll()
    }
    
    /// Clear old error history to prevent memory bloat
    func cleanupOldHistory(olderThan timeInterval: TimeInterval = 3600) {
        let cutoffDate = Date().addingTimeInterval(-timeInterval)
        
        for (key, history) in errorHistory {
            let recentHistory = history.filter { $0 > cutoffDate }
            if recentHistory.isEmpty {
                errorHistory.removeValue(forKey: key)
            } else {
                errorHistory[key] = recentHistory
            }
        }
    }
    
    /// Get detailed error report for debugging/support
    func generateErrorReport() -> String {
        var report = "PlayerPath Error Report\n"
        report += "Generated: \(Date().formatted())\n\n"
        
        report += "Current Error:\n"
        if let current = currentError {
            report += "  ID: \(current.id)\n"
            report += "  Description: \(current.errorDescription ?? "None")\n"
            report += "  Severity: \(current.severity)\n"
            report += "  Retryable: \(current.isRetryable)\n\n"
        } else {
            report += "  None\n\n"
        }
        
        report += "Queued Errors: \(errorQueue.count)\n"
        for (index, error) in errorQueue.enumerated() {
            report += "  \(index + 1). \(error.id)\n"
        }
        report += "\n"
        
        report += "Critical Errors: \(criticalErrors.count)\n"
        for error in criticalErrors {
            report += "  - \(error.id)\n"
        }
        report += "\n"
        
        report += "Error Analytics:\n"
        for (errorId, analytics) in errorAnalytics.sorted(by: { $0.value.occurrenceCount > $1.value.occurrenceCount }) {
            report += "  \(errorId):\n"
            report += "    Occurrences: \(analytics.occurrenceCount)\n"
            report += "    First seen: \(analytics.firstOccurrence.formatted())\n"
            report += "    Last seen: \(analytics.lastOccurrence.formatted())\n"
            report += "    Successful retries: \(analytics.successfulRetryCount)\n"
            report += "    Contexts: \(analytics.contexts.joined(separator: ", "))\n"
        }
        
        return report
    }
    
    /// Get error analytics for reporting
    func getErrorAnalytics() -> [String: ErrorAnalytics] {
        return errorAnalytics
    }
    
    /// Reset analytics (useful for testing or after app updates)
    func resetAnalytics() {
        errorAnalytics.removeAll()
        errorHistory.removeAll()
        retryAttempts.removeAll()
    }
    
    // MARK: - Retry Logic
    
    private func canRetryError(_ retryKey: String) -> Bool {
        let attempts = retryAttempts[retryKey, default: 0]
        return attempts < maxRetryAttempts
    }
    
    private func scheduleRetry(retryKey: String, error: PlayerPathError, context: String) {
        let currentAttempt = retryAttempts[retryKey, default: 0]
        let delay = min(retryBackoffBase * pow(2.0, Double(currentAttempt)), maxRetryDelay)
        
        logger.info("Scheduling retry for \(retryKey) in \(delay) seconds (attempt \(currentAttempt + 1))")
        
        // Cancel existing timer if any
        retryTimers[retryKey]?.invalidate()
        
        retryTimers[retryKey] = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.attemptRetry(retryKey: retryKey, error: error, context: context)
            }
        }
    }
    
    /// Register a retry callback for a specific retry key ("<context>_<error.id>")
    func registerRetryCallback(for retryKey: String, callback: @escaping () async -> Bool) {
        retryCallbacks[retryKey] = callback
    }
    
    /// Unregister a retry callback for a specific retry key
    func unregisterRetryCallback(for retryKey: String) {
        retryCallbacks.removeValue(forKey: retryKey)
    }
    
    private func attemptRetry(retryKey: String, error: PlayerPathError, context: String) async {
        retryAttempts[retryKey] = (retryAttempts[retryKey] ?? 0) + 1
        logger.info("Attempting retry for \(retryKey)")

        // Execute registered callback if available
        guard let callback = retryCallbacks[retryKey] else {
            logger.notice("No retry callback registered for \(retryKey)")
            retryTimers.removeValue(forKey: retryKey)
            return
        }

        let succeeded = await callback()

        if succeeded {
            // Update analytics
            if var analytics = errorAnalytics[error.id] {
                analytics.successfulRetryCount += 1
                errorAnalytics[error.id] = analytics
            }
            // Reset attempts for this context prefix
            resetRetryAttempts(for: context)
            // Dismiss current error if it matches
            if currentError?.id == error.id {
                dismissError(userInitiated: false)
            }
            retryTimers.removeValue(forKey: retryKey)
            logger.info("Retry succeeded for \(retryKey)")
            return
        } else {
            logger.notice("Retry failed for \(retryKey)")
            // If we can still retry, schedule next attempt with backoff
            if canRetryError(retryKey) {
                scheduleRetry(retryKey: retryKey, error: error, context: context)
            } else {
                retryTimers.removeValue(forKey: retryKey)
                logger.error("Max retry attempts reached for \(retryKey)")
            }
        }
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
        return attempts < self.maxRetryAttempts
    }
    
    /// Get current retry attempt count
    func getRetryAttempt(context: String, errorId: String) -> Int {
        let retryKey = "\(context)_\(errorId)"
        return retryAttempts[retryKey, default: 0]
    }
}

// MARK: - Enhanced Error Display View
struct PlayerPathErrorView: View {
    let error: PlayerPathError
    let onDismiss: () -> Void
    let onRetry: (() -> Void)?
    let showAnalytics: Bool
    
    @State private var isExpanded = false
    
    init(
        error: PlayerPathError,
        onDismiss: @escaping () -> Void,
        onRetry: (() -> Void)? = nil,
        showAnalytics: Bool = false
    ) {
        self.error = error
        self.onDismiss = onDismiss
        self.onRetry = onRetry
        self.showAnalytics = showAnalytics
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Main error content
            errorContent
            
            // Expandable details
            if isExpanded {
                errorDetails
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // Action buttons
            errorActions
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(errorBorderColor, lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .padding(.horizontal)
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isExpanded)
    }
    
    private var errorContent: some View {
        HStack(alignment: .top, spacing: 12) {
            // Error icon with glassmorphism effect
            Image(systemName: errorIcon)
                .foregroundStyle(errorIconGradient)
                .font(.title2)
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(errorBorderColor, lineWidth: 1))
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(errorTitle)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        if let description = error.errorDescription {
                            Text(description)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    
                    Spacer()
                    
                    // Expand/collapse button
                    Button(action: { isExpanded.toggle() }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                
                // Recovery suggestion (always visible for important info)
                if let recovery = error.recoverySuggestion {
                    Text(recovery)
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.top, 4)
                }
            }
        }
    }
    
    @ViewBuilder
    private var errorDetails: some View {
        if showAnalytics {
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                
                Text("Error Details")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    detailRow("Error ID", error.id)
                    detailRow("Retryable", error.isRetryable ? "Yes" : "No")
                    detailRow("Timestamp", Date().formatted(date: .omitted, time: .shortened))
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
    }
    
    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label + ":")
                .fontWeight(.medium)
            Spacer()
            Text(value)
                .foregroundColor(.primary)
        }
    }
    
    private var errorActions: some View {
        HStack(spacing: 12) {
            Button("Dismiss") {
                onDismiss()
            }
            .buttonStyle(.bordered)
            .foregroundColor(.secondary)
            
            if let onRetry = onRetry, error.isRetryable {
                Button("Retry") {
                    onRetry()
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            
            // Report button for critical errors
            if error.severity == .critical {
                Button("Report Issue") {
                    // Handle bug reporting
                    reportError()
                }
                .buttonStyle(.bordered)
                .foregroundColor(.orange)
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var errorTitle: String {
        switch error {
        case .videoUploadFailed, .videoProcessingFailed:
            return "Video Error"
        case .networkError:
            return "Connection Error"
        case .authenticationRequired:
            return "Sign In Required"
        case .cloudStorageFull:
            return "Storage Full"
        default:
            return "Error"
        }
    }
    
    private var errorIcon: String {
        switch error {
        case .videoUploadFailed, .networkError, .slowConnection:
            return "wifi.exclamationmark"
        case .noInternetConnection:
            return "wifi.slash"
        case .requestTimeout:
            return "clock.badge.exclamationmark"
        case .videoProcessingFailed, .videoFileCorrupted, .dataCorrupted:
            return "exclamationmark.triangle.fill"
        case .videoFileTooLarge, .videoFileTooSmall:
            return "doc.badge.exclamationmark"
        case .videoDurationTooLong, .videoDurationTooShort:
            return "clock.badge.exclamationmark"
        case .unsupportedVideoFormat:
            return "video.badge.exclamationmark"
        case .videoFileNotFound:
            return "doc.badge.questionmark"
        case .authenticationRequired, .sessionExpired:
            return "person.badge.exclamationmark"
        case .permissionDenied:
            return "hand.raised.fill"
        case .cloudStorageFull:
            return "icloud.slash.fill"
        case .localStorageFull, .insufficientSpace:
            return "internaldrive.fill"
        case .syncFailed:
            return "arrow.triangle.2.circlepath.circle"
        case .saveError:
            return "square.and.arrow.down.trianglebadge.exclamationmark"
        case .unknownError:
            return "questionmark.circle.fill"
        }
    }
    
    private var errorIconGradient: LinearGradient {
        switch error.severity {
        case .critical:
            return LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .high:
            return LinearGradient(colors: [.red, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .medium:
            return LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .low:
            return LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
    
    private var errorBorderColor: Color {
        switch error.severity {
        case .critical: return .red
        case .high: return .red.opacity(0.7)
        case .medium: return .orange
        case .low: return .blue
        }
    }
    
    private func reportError() {
        // Implement error reporting logic
        // Could integrate with your analytics service, send email, etc.
        print("Reporting error: \(error.id)")
    }
}

// MARK: - Error Handling View Modifier

/// View modifier that automatically shows errors from ErrorHandlerService
struct ErrorHandlingModifier: ViewModifier {
    @Environment(\.errorHandler) private var errorHandler: ErrorHandlerService?
    let onRetry: ((PlayerPathError) -> Void)?
    let showAnalytics: Bool
    
    init(onRetry: ((PlayerPathError) -> Void)? = nil, showAnalytics: Bool = false) {
        self.onRetry = onRetry
        self.showAnalytics = showAnalytics
    }
    
    func body(content: Content) -> some View {
        let service = errorHandler ?? ErrorHandlerService.shared
        
        content
            .overlay(alignment: .top) {
                if service.isShowingError, let error = service.currentError {
                    PlayerPathErrorView(
                        error: error,
                        onDismiss: {
                            service.dismissError(userInitiated: true)
                        },
                        onRetry: onRetry != nil ? { onRetry?(error) } : nil,
                        showAnalytics: showAnalytics
                    )
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: service.isShowingError)
                    .zIndex(999)
                }
            }
    }
}

extension View {
    /// Apply automatic error handling to this view
    func handleErrors(
        onRetry: ((PlayerPathError) -> Void)? = nil,
        showAnalytics: Bool = false
    ) -> some View {
        modifier(ErrorHandlingModifier(onRetry: onRetry, showAnalytics: showAnalytics))
    }
}

// MARK: - Environment Key for ErrorHandlerService

private struct ErrorHandlerKey: EnvironmentKey {
    static let defaultValue: ErrorHandlerService? = nil
}

extension EnvironmentValues {
    var errorHandler: ErrorHandlerService? {
        get { self[ErrorHandlerKey.self] }
        set { self[ErrorHandlerKey.self] = newValue }
    }
}

extension View {
    /// Inject ErrorHandlerService into the environment
    func errorHandlerService(_ service: ErrorHandlerService) -> some View {
        environment(\.errorHandler, service)
    }
}

