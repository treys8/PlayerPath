//
//  RetryHelpers.swift
//  PlayerPath
//
//  Reusable retry utilities for async operations
//

import Foundation

/// Retries an async throwing operation with configurable delay between attempts.
/// Returns the result on success, throws the last error after all attempts are exhausted.
/// - Parameters:
///   - backoff: When true, delay doubles each attempt (delay, delay×2, delay×4, ...)
///   - shouldRetry: When provided, only retries if closure returns true; otherwise re-throws immediately
func withRetry<T>(
    maxAttempts: Int = 3,
    delay: Duration = .seconds(2),
    backoff: Bool = false,
    shouldRetry: ((Error) -> Bool)? = nil,
    operation: () async throws -> T
) async throws -> T {
    var lastError: (any Error)?
    for attempt in 1...maxAttempts {
        do {
            return try await operation()
        } catch {
            lastError = error
            if let shouldRetry, !shouldRetry(error) {
                throw error
            }
            if attempt < maxAttempts {
                let currentDelay = backoff ? delay * Int(pow(2.0, Double(attempt - 1))) : delay
                try? await Task.sleep(for: currentDelay)
            }
        }
    }
    throw lastError!
}

/// Fire-and-forget retry: silently retries an async operation, discarding errors after exhaustion.
/// Use for background cleanup tasks where failure is acceptable (e.g., Firestore soft-deletes).
/// - Parameters:
///   - backoff: When true, delay doubles each attempt (delay, delay×2, delay×4, ...)
///   - shouldRetry: When provided, only retries if closure returns true; otherwise stops immediately
func retryAsync(
    maxAttempts: Int = 3,
    delay: Duration = .seconds(2),
    backoff: Bool = false,
    shouldRetry: ((Error) -> Bool)? = nil,
    operation: () async throws -> Void
) async {
    for attempt in 1...maxAttempts {
        do {
            try await operation()
            return
        } catch {
            if let shouldRetry, !shouldRetry(error) {
                return
            }
            if attempt < maxAttempts {
                let currentDelay = backoff ? delay * Int(pow(2.0, Double(attempt - 1))) : delay
                try? await Task.sleep(for: currentDelay)
            }
        }
    }
}
