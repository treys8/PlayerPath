//
//  ToastModifier.swift
//  PlayerPath
//
//  Reusable toast overlay for non-blocking success/info/warning messages.
//

import SwiftUI

enum ToastType {
    case success
    case info
    case warning

    var icon: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .success: .success
        case .info: .info
        case .warning: .warning
        }
    }

    func fireHaptic() {
        switch self {
        case .success: Haptics.success()
        case .info: Haptics.light()
        case .warning: Haptics.warning()
        }
    }
}

private struct ToastModifier: ViewModifier {
    @Binding var isPresenting: Bool
    let type: ToastType
    let message: String
    let duration: TimeInterval

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if isPresenting {
                    Label(message, systemImage: type.icon)
                        .font(.headingMedium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, .spacingLarge)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 100)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            type.fireHaptic()
                            Task {
                                try? await Task.sleep(for: .seconds(duration))
                                withAnimation(.standard) {
                                    isPresenting = false
                                }
                            }
                        }
                }
            }
            .animation(.standard, value: isPresenting)
    }
}

extension View {
    func toast(
        isPresenting: Binding<Bool>,
        type: ToastType = .success,
        message: String,
        duration: TimeInterval = 2.0
    ) -> some View {
        modifier(ToastModifier(
            isPresenting: isPresenting,
            type: type,
            message: message,
            duration: duration
        ))
    }
}
