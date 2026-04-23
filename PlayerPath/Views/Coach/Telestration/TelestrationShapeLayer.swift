//
//  TelestrationShapeLayer.swift
//  PlayerPath
//
//  Renders an array of TelestrationShape instances as SwiftUI Paths.
//  Used by both the coach drawing overlay (static placed shapes + live
//  in-flight preview) and the athlete read-only DrawingAnnotationOverlay.
//

import SwiftUI

struct TelestrationShapeLayer: View {
    let shapes: [TelestrationShape]
    let canvasSize: CGSize
    /// Optional shape currently being dragged — rendered above placed shapes.
    var inFlight: TelestrationShape? = nil

    var body: some View {
        ZStack {
            ForEach(shapes) { shape in
                shapeView(shape)
            }
            if let inFlight {
                shapeView(inFlight)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }

    @ViewBuilder
    private func shapeView(_ shape: TelestrationShape) -> some View {
        let start = shape.start(in: canvasSize)
        let end = shape.end(in: canvasSize)
        let color = shape.color
        let width = CGFloat(shape.lineWidth)

        switch shape.kind {
        case .line:
            Path { p in
                p.move(to: start)
                p.addLine(to: end)
            }
            .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))

        case .arrow:
            ArrowShapePath(start: start, end: end, lineWidth: width)
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))

        case .circle:
            // Ellipse inscribed in the rect defined by start/end corners.
            let rect = rectBetween(start, end)
            Ellipse()
                .stroke(color, lineWidth: width)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

        case .rectangle:
            let rect = rectBetween(start, end)
            Rectangle()
                .stroke(color, lineWidth: width)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
    }

    private func rectBetween(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        let x = min(a.x, b.x)
        let y = min(a.y, b.y)
        let w = abs(b.x - a.x)
        let h = abs(b.y - a.y)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

/// Shaft + arrowhead as a single Path. Arrowhead size scales with lineWidth
/// (head length = lineWidth * 4) so thin arrows get proportional heads.
private struct ArrowShapePath: Shape {
    let start: CGPoint
    let end: CGPoint
    let lineWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0.5 else { return path }

        let headLength = min(max(lineWidth * 4, 12), length * 0.6)
        let headAngle: CGFloat = .pi / 7  // ~25°

        // Shaft stops short of the tip so the triangle join looks clean.
        let shaftEndScale = max(0, (length - headLength * 0.6) / length)
        let shaftEnd = CGPoint(
            x: start.x + dx * shaftEndScale,
            y: start.y + dy * shaftEndScale
        )
        path.move(to: start)
        path.addLine(to: shaftEnd)

        let angle = atan2(dy, dx)
        let leftAngle = angle + .pi - headAngle
        let rightAngle = angle + .pi + headAngle
        let left = CGPoint(
            x: end.x + cos(leftAngle) * headLength,
            y: end.y + sin(leftAngle) * headLength
        )
        let right = CGPoint(
            x: end.x + cos(rightAngle) * headLength,
            y: end.y + sin(rightAngle) * headLength
        )
        path.move(to: left)
        path.addLine(to: end)
        path.addLine(to: right)
        return path
    }
}
