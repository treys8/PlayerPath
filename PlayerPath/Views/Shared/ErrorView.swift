//
//  ErrorView.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI
import UIKit

// MARK: - Error Display Type

enum ErrorDisplayType {
    case network
    case permission
    case empty
    case generic

    var icon: String {
        switch self {
        case .network:
            return "wifi.slash"
        case .permission:
            return "lock.shield.fill"
        case .empty:
            return "tray.fill"
        case .generic:
            return "exclamationmark.triangle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .network:
            return .brandNavy
        case .permission:
            return .red
        case .empty:
            return .secondary
        case .generic:
            return .orange
        }
    }

    var defaultTitle: String {
        switch self {
        case .network:
            return "Connection Issue"
        case .permission:
            return "Permission Required"
        case .empty:
            return "Nothing Here Yet"
        case .generic:
            return "Something Went Wrong"
        }
    }

    var defaultSuggestion: String? {
        switch self {
        case .network:
            return "Check your internet connection and try again."
        case .permission:
            return "Open Settings to grant the required permissions."
        case .empty:
            return nil
        case .generic:
            return "Pull to refresh or try again in a moment."
        }
    }

    var retryLabel: String {
        switch self {
        case .network:
            return "Retry Connection"
        case .permission:
            return "Open Settings"
        case .empty:
            return "Refresh"
        case .generic:
            return "Try Again"
        }
    }
}

// MARK: - ErrorView

struct ErrorView: View {
    let message: String
    let retry: (() -> Void)?
    var errorType: ErrorDisplayType
    var title: String?
    var suggestion: String?

    init(
        message: String,
        retry: (() -> Void)? = nil,
        errorType: ErrorDisplayType = .generic,
        title: String? = nil,
        suggestion: String? = nil
    ) {
        self.message = message
        self.retry = retry
        self.errorType = errorType
        self.title = title
        self.suggestion = suggestion
    }

    private var displayTitle: String {
        title ?? errorType.defaultTitle
    }

    private var displaySuggestion: String? {
        suggestion ?? errorType.defaultSuggestion
    }

    var body: some View {
        VStack(spacing: 20) {
            // Icon with background circle
            ZStack {
                Circle()
                    .fill(errorType.iconColor.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: errorType.icon)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundColor(errorType.iconColor)
            }
            .padding(.bottom, 4)

            // Title
            Text(displayTitle)
                .font(.title3)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            // Message
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            // Recovery suggestion
            if let suggestion = displaySuggestion {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                    Text(suggestion)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }

            // Retry button
            if let retry {
                Button(action: retry) {
                    HStack(spacing: 8) {
                        Image(systemName: retryIconName)
                            .font(.subheadline.weight(.semibold))
                        Text(errorType.retryLabel)
                            .fontWeight(.semibold)
                    }
                    .frame(minWidth: 180)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
                    .background(errorType.iconColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(displayTitle). \(message)"))
    }

    private var retryIconName: String {
        switch errorType {
        case .network:
            return "arrow.clockwise"
        case .permission:
            return "gear"
        case .empty:
            return "arrow.clockwise"
        case .generic:
            return "arrow.clockwise"
        }
    }
}

// MARK: - Convenience Initializers

extension ErrorView {
    /// Network error with standard messaging
    static func network(
        message: String = "Unable to connect to the server.",
        retry: (() -> Void)? = nil
    ) -> ErrorView {
        ErrorView(
            message: message,
            retry: retry,
            errorType: .network
        )
    }

    /// Permission error with settings link
    static func permission(
        message: String,
        retry: (() -> Void)? = nil
    ) -> ErrorView {
        ErrorView(
            message: message,
            retry: retry ?? {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            },
            errorType: .permission
        )
    }

    /// Generic error from an AppError
    static func fromAppError(
        _ error: AppError,
        retry: (() -> Void)? = nil
    ) -> ErrorView {
        let displayType: ErrorDisplayType
        switch error {
        case .noInternetConnection, .requestTimeout, .networkFailure:
            displayType = .network
        case .cameraPermissionDenied, .microphonePermissionDenied, .firestorePermissionDenied:
            displayType = .permission
        default:
            displayType = .generic
        }

        return ErrorView(
            message: error.errorDescription ?? "An unexpected error occurred.",
            retry: retry,
            errorType: displayType,
            suggestion: error.recoverySuggestion
        )
    }
}

// MARK: - Preview

#Preview("Generic Error") {
    ErrorView(
        message: "Failed to load your data. Please try again.",
        retry: { }
    )
}

#Preview("Network Error") {
    ErrorView.network(retry: { })
}

#Preview("Permission Error") {
    ErrorView.permission(
        message: "Camera access is required to record videos. Please enable it in Settings."
    )
}

#Preview("Error without retry") {
    ErrorView(
        message: "This feature is not yet available.",
        errorType: .generic,
        title: "Coming Soon"
    )
}
