//
//  HapticManager.swift
//  PlayerPath
//
//  Created by Assistant on 10/26/25.
//

import UIKit

// MARK: - Haptic Manager
@MainActor
final class HapticManager: ObservableObject {
    static let shared = HapticManager()
    
    private init() {}
    
    // MARK: - Impact Feedback
    
    func light() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    func medium() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
    
    func heavy() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
    }
    
    // MARK: - Notification Feedback
    
    func success() {
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.success)
    }
    
    func warning() {
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.warning)
    }
    
    func error() {
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.error)
    }
    
    // MARK: - Selection Feedback
    
    func selection() {
        let selectionFeedback = UISelectionFeedbackGenerator()
        selectionFeedback.selectionChanged()
    }
    
    // MARK: - Contextual Feedback
    
    func authenticationSuccess() {
        success()
    }
    
    func authenticationError() {
        error()
    }
    
    func athleteCreated() {
        success()
    }
    
    func formValidation() {
        light()
    }
    
    func buttonTap() {
        light()
    }
}