//
//  ConnectivityMonitor.swift
//  PlayerPath
//
//  Monitors network connectivity for smart upload management
//

import Foundation
import Network

@MainActor
@Observable
final class ConnectivityMonitor {
    static let shared = ConnectivityMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "ConnectivityMonitor")

    // Published state
    var isConnected: Bool = true
    var connectionType: ConnectionType = .unknown
    var isExpensive: Bool = false

    private init() {
        startMonitoring()
    }

    // MARK: - Connection Types

    enum ConnectionType {
        case wifi
        case cellular
        case wired
        case unknown

        var displayName: String {
            switch self {
            case .wifi: return "WiFi"
            case .cellular: return "Cellular"
            case .wired: return "Ethernet"
            case .unknown: return "Unknown"
            }
        }

        var icon: String {
            switch self {
            case .wifi: return "wifi"
            case .cellular: return "antenna.radiowaves.left.and.right"
            case .wired: return "cable.connector"
            case .unknown: return "network.slash"
            }
        }
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                self.isConnected = path.status == .satisfied
                self.isExpensive = path.isExpensive

                // Determine connection type
                if path.usesInterfaceType(.wifi) {
                    self.connectionType = .wifi
                } else if path.usesInterfaceType(.cellular) {
                    self.connectionType = .cellular
                } else if path.usesInterfaceType(.wiredEthernet) {
                    self.connectionType = .wired
                } else {
                    self.connectionType = .unknown
                }

                print("ConnectivityMonitor: Connection changed - \(self.connectionType.displayName), Connected: \(self.isConnected), Expensive: \(self.isExpensive)")

                // Notify upload manager of network change
                NotificationCenter.default.post(name: .networkStatusChanged, object: nil)
            }
        }

        monitor.start(queue: queue)
    }

    // MARK: - Upload Eligibility

    /// Determines if uploads should proceed based on network conditions and user preferences
    func shouldAllowUploads(preferences: UserPreferences?) -> Bool {
        // No connection - pause uploads
        guard isConnected else {
            return false
        }

        // Check user preferences for cellular uploads
        guard let prefs = preferences else {
            // No preferences loaded - default to WiFi only
            return connectionType == .wifi
        }

        // If on cellular, check if cellular uploads are allowed
        if connectionType == .cellular {
            return prefs.allowCellularUploads
        }

        // WiFi or wired - always allow
        return true
    }

    var networkStatusMessage: String {
        if !isConnected {
            return "No internet connection"
        }

        if connectionType == .cellular {
            if isExpensive {
                return "Connected via cellular (limited data)"
            } else {
                return "Connected via cellular"
            }
        }

        return "Connected via \(connectionType.displayName)"
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let networkStatusChanged = Notification.Name("NetworkStatusChanged")
}
