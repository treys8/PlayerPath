//
//  HapticManager.swift
//  PlayerPath
//
//  Created by Assistant on 10/26/25.
//

import UIKit

@MainActor
final class HapticManager {
    static let shared = HapticManager()
    
    // Reusable generators to reduce allocation overhead
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()
    
    private init() {
        // Prepare generators on initialization for better performance
        impactLight.prepare()
        impactMedium.prepare()
        impactHeavy.prepare()
        notification.prepare()
        selection.prepare()
    }
    
    func authenticationSuccess() {
        impactMedium.impactOccurred()
        impactMedium.prepare() // Re-prepare after use
    }
    
    func authenticationError() {
        notification.notificationOccurred(.error)
        notification.prepare()
    }
    
    func buttonTap() {
        impactLight.impactOccurred()
        impactLight.prepare()
    }
    
    func successAction() {
        notification.notificationOccurred(.success)
        notification.prepare()
    }
    
    // Additional haptic methods
    func success() {
        notification.notificationOccurred(.success)
        notification.prepare()
    }
    
    func error() {
        notification.notificationOccurred(.error)
        notification.prepare()
    }
    
    func warning() {
        notification.notificationOccurred(.warning)
        notification.prepare()
    }
    
    func selectionChanged() {
        selection.selectionChanged()
        selection.prepare()
    }
    
    func impact(style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        switch style {
        case .light:
            impactLight.impactOccurred()
            impactLight.prepare()
        case .medium:
            impactMedium.impactOccurred()
            impactMedium.prepare()
        case .heavy:
            impactHeavy.impactOccurred()
            impactHeavy.prepare()
        case .soft:
            // For soft and rigid, create on-demand since they're less common
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            generator.impactOccurred()
        case .rigid:
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            generator.impactOccurred()
        @unknown default:
            impactMedium.impactOccurred()
            impactMedium.prepare()
        }
    }
}

