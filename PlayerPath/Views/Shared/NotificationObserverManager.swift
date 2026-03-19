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
@MainActor
final class NotificationObserverManager: ObservableObject {
    // nonisolated(unsafe) allows safe access from deinit (which is non-isolated).
    // All mutations go through @MainActor methods, and deinit only runs after
    // all references are gone, so there is no concurrent access.
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
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
