//
//  TelestrationShape.swift
//  PlayerPath
//
//  Model + JSON codec for straight shapes (arrow, line, circle, rectangle)
//  placed alongside PencilKit freehand strokes during telestration. Stored
//  on VideoAnnotation as a JSON string in the `shapes` field.
//

import SwiftUI

enum TelestrationShapeKind: String, Codable {
    case arrow
    case line
    case circle
    case rectangle
}

/// A single placed shape. Coordinates are normalized 0..1 within the canvas
/// they were drawn on, so playback can scale cleanly to any video frame size.
struct TelestrationShape: Codable, Identifiable, Equatable {
    let id: UUID
    let kind: TelestrationShapeKind
    let startX: Double
    let startY: Double
    let endX: Double
    let endY: Double
    let colorHex: String
    let lineWidth: Double

    init(
        kind: TelestrationShapeKind,
        start: CGPoint,
        end: CGPoint,
        canvasSize: CGSize,
        color: Color,
        lineWidth: CGFloat
    ) {
        self.id = UUID()
        self.kind = kind
        let w = max(canvasSize.width, 1)
        let h = max(canvasSize.height, 1)
        self.startX = Double(start.x / w)
        self.startY = Double(start.y / h)
        self.endX = Double(end.x / w)
        self.endY = Double(end.y / h)
        self.colorHex = color.toHex() ?? "#FF0000"
        self.lineWidth = Double(lineWidth)
    }

    func start(in size: CGSize) -> CGPoint {
        CGPoint(x: startX * size.width, y: startY * size.height)
    }

    func end(in size: CGSize) -> CGPoint {
        CGPoint(x: endX * size.width, y: endY * size.height)
    }

    var color: Color { Color(hex: colorHex) }
}

/// JSON serialization helpers. Stored as a base-level string on the annotation
/// doc (Firestore-safe) so the schema only gains one scalar field.
enum TelestrationShapesCodec {
    static func encode(_ shapes: [TelestrationShape]) -> String? {
        guard !shapes.isEmpty else { return nil }
        guard let data = try? JSONEncoder().encode(shapes) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ json: String?) -> [TelestrationShape] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([TelestrationShape].self, from: data)) ?? []
    }
}
