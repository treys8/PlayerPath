//
//  TooltipBubble.swift
//  PlayerPath
//

import SwiftUI

struct TooltipBubble: View {
    let text: String
    let arrowEdge: Edge
    let arrowOffset: CGFloat
    let onDismiss: () -> Void

    init(
        _ text: String,
        arrowEdge: Edge = .bottom,
        arrowOffset: CGFloat = 0,
        onDismiss: @escaping () -> Void
    ) {
        self.text = text
        self.arrowEdge = arrowEdge
        self.arrowOffset = arrowOffset
        self.onDismiss = onDismiss
    }

    private let arrowSize: CGFloat = 10
    private let cornerRadius: CGFloat = 12
    private let maxWidth: CGFloat = 220

    var body: some View {
        VStack(spacing: 0) {
            if arrowEdge == .bottom {
                bubbleContent
                arrowTriangle
                    .rotationEffect(.degrees(180))
                    .offset(x: arrowOffset)
            } else if arrowEdge == .top {
                arrowTriangle
                    .offset(x: arrowOffset)
                bubbleContent
            } else {
                HStack(spacing: 0) {
                    if arrowEdge == .trailing {
                        bubbleContent
                        arrowTriangle
                            .rotationEffect(.degrees(90))
                            .offset(y: arrowOffset)
                    } else {
                        arrowTriangle
                            .rotationEffect(.degrees(-90))
                            .offset(y: arrowOffset)
                        bubbleContent
                    }
                }
            }
        }
        .onTapGesture {
            Haptics.light()
            onDismiss()
        }
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
    }

    private var bubbleContent: some View {
        Text(text)
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: maxWidth)
            .background(Color.brandNavy)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var arrowTriangle: some View {
        TriangleShape()
            .fill(Color.brandNavy)
            .frame(width: arrowSize * 2, height: arrowSize)
    }
}

private struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
