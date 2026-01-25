//
//  NotificationObserverManager.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import Foundation
import SwiftUI
import Combine

/// Manages NotificationCenter observers with automatic lifecycle handling
/// This prevents observer duplication during view lifecycle events
final class NotificationObserverManager: ObservableObject {
    private var observers: [NSObjectProtocol] = []

    deinit {
        // Cleanup synchronously in deinit - this is safe because
        // removeObserver is synchronous and doesn't require MainActor
        // Remove observers directly here since deinit is non-isolated
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    /// Add an observer and track it for cleanup
    @MainActor
    func observe(name: Notification.Name, object: Any? = nil, using block: @escaping @Sendable (Notification) -> Void) {
        let observer = NotificationCenter.default.addObserver(
            forName: name,
            object: object,
            queue: .main,
            using: block
        )
        observers.append(observer)
    }

    /// Remove all observers
    @MainActor
    func cleanup() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }
}
