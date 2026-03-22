//
//  RetryHelpers.swift
//  PlayerPath
//
//  Reusable retry utilities for async operations
//

import Foundation

/// Retries an async throwing operation with a fixed delay between attempts.
/// Returns the result on success, throws the last error after all attempts are exhausted.
func withRetry<T>(
    maxAttempts: Int = 3,
    delay: Duration = .seconds(2),
    operation: () async throws -> T
) async throws -> T {
    var lastError: (any Error)?
    for attempt in 1...maxAttempts {
        do {
            return try await operation()
        } catch {
            lastError = error
            if attempt < maxAttempts {
                try? await Task.sleep(for: delay)
            }
        }
    }
    throw lastError!
}

/// Fire-and-forget retry: silently retries an async operation, discarding errors after exhaustion.
/// Use for background cleanup tasks where failure is acceptable (e.g., Firestore soft-deletes).
func retryAsync(
    maxAttempts: Int = 3,
    delay: Duration = .seconds(2),
    operation: () async throws -> Void
) async {
    for attempt in 1...maxAttempts {
        do {
            try await operation()
            return
        } catch {
            if attempt < maxAttempts {
                try? await Task.sleep(for: delay)
            }
        }
    }
}
