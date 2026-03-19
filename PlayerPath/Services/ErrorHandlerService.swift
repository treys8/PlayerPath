//
//  ErrorHandlerService.swift
//  PlayerPath
//
//  Centralized error handling, logging, and user notification
//

import Foundation
import SwiftUI
import SwiftData
import OSLog
import Combine

@MainActor
final class ErrorHandlerService: ObservableObject {
    static let shared = ErrorHandlerService()

    @Published private(set) var currentError: AppError?
    @Published private(set) var showErrorAlert = false
    @Published private(set) var errorHistory: [ErrorRecord] = []

    private let logger = Logger(subsystem: "com.playerpath.app", category: "ErrorHandler")
    private let maxHistorySize = 50

    private init() {}

    // MARK: - Error Record

    struct ErrorRecord: Identifiable {
        let id = UUID()
        let error: AppError
        let timestamp: Date
        let context: String?

        var description: String {
            let timeString = timestamp.formatted(date: .omitted, time: .standard)
            let contextString = context.map { " [\($0)]" } ?? ""
            return "\(timeString)\(contextString): \(error.errorDescription ?? "Unknown error")"
        }
    }

    // MARK: - Handle Error

    /// Handle an error and optionally show an alert to the user
    func handle(_ error: Error, context: String? = nil, showAlert: Bool = true) {
        let appError = AppError.from(error)
        handle(appError, context: context, showAlert: showAlert)
    }

    /// Handle an AppError and optionally show an alert to the user
    func handle(_ error: AppError, context: String? = nil, showAlert: Bool = true) {
        // Log error
        logError(error, context: context)

        // Record in history
        recordError(error, context: context)

        // Haptic feedback based on severity
        switch error.severity {
        case .low: break
        case .medium: Haptics.warning()
        case .high, .critical: Haptics.error()
        }

        // Show alert if requested
        if showAlert {
            presentError(error)
        }

        // Track analytics (optional - can integrate with Firebase Analytics)
        trackErrorAnalytics(error, context: context)
    }

    /// Save a ModelContext, logging on failure instead of silently dropping the error.
    /// Use this in place of `try? context.save()` to get visibility into save failures.
    @discardableResult
    func saveContext(_ context: ModelContext, caller: String) -> Bool {
        guard context.hasChanges else { return true }
        do {
            try context.save()
            return true
        } catch {
            handle(error, context: caller, showAlert: false)
            return false
        }
    }

    // MARK: - View Error Reporting

    /// Report an error from a view catch block: logs centrally, sets local state for the view's own alert,
    /// and triggers haptic feedback. Use this instead of manual `errorMessage = ...; showingError = true; Haptics.error()`.
    func reportError(
        _ error: Error,
        context: String,
        message: Binding<String>,
        isPresented: Binding<Bool>,
        userMessage: String? = nil
    ) {
        let appError = AppError.from(error)
        handle(appError, context: context, showAlert: false)
        message.wrappedValue = userMessage ?? appError.errorDescription ?? error.localizedDescription
        isPresented.wrappedValue = true
    }

    /// Report a validation or non-Error failure from a view: logs centrally and sets local state.
    func reportWarning(
        _ userMessage: String,
        context: String,
        message: Binding<String>,
        isPresented: Binding<Bool>
    ) {
        logger.warning("[\(context)] \(userMessage)")
        message.wrappedValue = userMessage
        isPresented.wrappedValue = true
        Haptics.error()
    }

    /// Present an error alert to the user
    func presentError(_ error: AppError) {
        currentError = error
        showErrorAlert = true
    }

    /// Dismiss the current error alert
    func dismissError() {
        showErrorAlert = false

        // Clear after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.currentError = nil
        }
    }

    // MARK: - Logging

    private func logError(_ error: AppError, context: String?) {
        let contextString = context.map { "[\($0)] " } ?? ""
        let errorMessage = error.errorDescription ?? "Unknown error"

        switch error.severity {
        case .low:
            logger.info("\(contextString)\(errorMessage, privacy: .public)")
        case .medium:
            logger.warning("\(contextString)\(errorMessage, privacy: .public)")
        case .high, .critical:
            logger.error("\(contextString)\(errorMessage, privacy: .public)")
        }

        #if DEBUG
        print("🔴 ERROR [\(error.severity)] \(contextString)\(errorMessage)")
        if let recovery = error.recoverySuggestion {
            print("   💡 Recovery: \(recovery)")
        }
        #endif
    }

    // MARK: - Error History

    private func recordError(_ error: AppError, context: String?) {
        let record = ErrorRecord(error: error, timestamp: Date(), context: context)
        errorHistory.insert(record, at: 0)

        // Limit history size
        if errorHistory.count > maxHistorySize {
            errorHistory.removeLast()
        }
    }

    func clearHistory() {
        errorHistory.removeAll()
    }

    func getRecentErrors(limit: Int = 10) -> [ErrorRecord] {
        return Array(errorHistory.prefix(limit))
    }

    // MARK: - Analytics

    private func trackErrorAnalytics(_ error: AppError, context: String?) {
        AnalyticsService.shared.trackError(error, context: context ?? "unknown")
    }

    // MARK: - Error Statistics

    func getErrorStatistics() -> ErrorStatistics {
        let totalErrors = errorHistory.count
        let errorsBySeverity = Dictionary(grouping: errorHistory, by: { $0.error.severity })
        let criticalCount = errorsBySeverity[.critical]?.count ?? 0
        let highCount = errorsBySeverity[.high]?.count ?? 0
        let mediumCount = errorsBySeverity[.medium]?.count ?? 0
        let lowCount = errorsBySeverity[.low]?.count ?? 0

        return ErrorStatistics(
            totalErrors: totalErrors,
            criticalErrors: criticalCount,
            highErrors: highCount,
            mediumErrors: mediumCount,
            lowErrors: lowCount
        )
    }

    struct ErrorStatistics {
        let totalErrors: Int
        let criticalErrors: Int
        let highErrors: Int
        let mediumErrors: Int
        let lowErrors: Int

        var hasErrors: Bool {
            totalErrors > 0
        }

        var hasCriticalErrors: Bool {
            criticalErrors > 0
        }
    }
}

// MARK: - Error Alert Modifier

struct ErrorAlertModifier: ViewModifier {
    @ObservedObject var errorHandler = ErrorHandlerService.shared

    func body(content: Content) -> some View {
        content
            .alert(
                errorHandler.currentError?.errorDescription ?? "Error",
                isPresented: Binding(
                    get: { errorHandler.showErrorAlert },
                    set: { if !$0 { errorHandler.dismissError() } }
                )
            ) {
                // Generate action buttons based on error type
                if let error = errorHandler.currentError {
                    ForEach(error.suggestedActions, id: \.self) { action in
                        actionButton(for: action, error: error)
                    }
                }
            } message: {
                if let error = errorHandler.currentError,
                   let recovery = error.recoverySuggestion {
                    Text(recovery)
                }
            }
    }

    @ViewBuilder
    private func actionButton(for action: AppError.UserAction, error: AppError) -> some View {
        switch action {
        case .retry:
            Button("Retry") {
                // Retry action - views should implement their own retry logic
                errorHandler.dismissError()
            }
        case .openSettings:
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                errorHandler.dismissError()
            }
        case .contactSupport:
            Button("Contact Support") {
                // TODO: Open support contact flow
                errorHandler.dismissError()
            }
        case .dismiss:
            Button("OK") {
                errorHandler.dismissError()
            }
        case .signIn:
            Button("Sign In") {
                // TODO: Navigate to sign in
                errorHandler.dismissError()
            }
        }
    }
}

extension View {
    /// Add global error handling to any view
    func withErrorHandling() -> some View {
        modifier(ErrorAlertModifier())
    }
}

// MARK: - Error Banner View

struct ErrorBanner: View {
    let error: AppError
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(iconColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(error.errorDescription ?? "Error")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                if let recovery = error.recoverySuggestion {
                    Text(recovery)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(backgroundColor)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
    }

    private var iconName: String {
        switch error.severity {
        case .low:
            return "info.circle.fill"
        case .medium:
            return "exclamationmark.triangle.fill"
        case .high, .critical:
            return "xmark.octagon.fill"
        }
    }

    private var iconColor: Color {
        switch error.severity {
        case .low:
            return .blue
        case .medium:
            return .orange
        case .high, .critical:
            return .red
        }
    }

    private var backgroundColor: Color {
        switch error.severity {
        case .low:
            return Color.blue.opacity(0.1)
        case .medium:
            return Color.orange.opacity(0.1)
        case .high, .critical:
            return Color.red.opacity(0.1)
        }
    }
}

// MARK: - Error History View

struct ErrorHistoryView: View {
    @ObservedObject var errorHandler = ErrorHandlerService.shared

    var body: some View {
        List {
            Section {
                let stats = errorHandler.getErrorStatistics()
                VStack(alignment: .leading, spacing: 12) {
                    StatRow(label: "Total Errors", value: "\(stats.totalErrors)")
                    if stats.criticalErrors > 0 {
                        StatRow(label: "Critical", value: "\(stats.criticalErrors)", color: .red)
                    }
                    if stats.highErrors > 0 {
                        StatRow(label: "High Priority", value: "\(stats.highErrors)", color: .orange)
                    }
                    if stats.mediumErrors > 0 {
                        StatRow(label: "Medium Priority", value: "\(stats.mediumErrors)", color: .yellow)
                    }
                    if stats.lowErrors > 0 {
                        StatRow(label: "Low Priority", value: "\(stats.lowErrors)", color: .blue)
                    }
                }
                .padding(.vertical, 8)
            } header: {
                Text("Statistics")
            }

            if errorHandler.errorHistory.isEmpty {
                Section {
                    Text("No errors recorded")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            } else {
                Section {
                    ForEach(errorHandler.errorHistory) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.error.errorDescription ?? "Unknown error")
                                .font(.subheadline)

                            HStack {
                                Text(record.timestamp.formatted(date: .omitted, time: .standard))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                if let context = record.context {
                                    Text("•")
                                        .foregroundStyle(.secondary)
                                    Text(context)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                severityBadge(for: record.error.severity)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    HStack {
                        Text("Recent Errors")
                        Spacer()
                        Button("Clear") {
                            errorHandler.clearHistory()
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .navigationTitle("Error Log")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func severityBadge(for severity: AppError.Severity) -> some View {
        Text(String(describing: severity).uppercased())
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(severityColor(for: severity))
            .cornerRadius(4)
    }

    private func severityColor(for severity: AppError.Severity) -> Color {
        switch severity {
        case .low: return .blue
        case .medium: return .yellow
        case .high: return .orange
        case .critical: return .red
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
    }
}
