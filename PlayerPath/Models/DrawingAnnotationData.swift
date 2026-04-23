//
//  DrawingAnnotationData.swift
//  PlayerPath
//
//  Serialization helpers for PencilKit drawings stored as
//  base64-encoded data on VideoAnnotation documents.
//

import Foundation

// MARK: - VideoAnnotation Drawing Helpers

extension VideoAnnotation {
    /// True when this annotation represents a telestration drawing.
    var isDrawing: Bool { type == "drawing" }

    /// Decoded PencilKit drawing data, or nil if this isn't a drawing annotation
    /// or the data is corrupt.
    var drawingPKData: Data? {
        guard isDrawing, let base64 = drawingData else { return nil }
        return Data(base64Encoded: base64)
    }

    /// Decoded geometric shapes placed on this annotation. Empty array for
    /// non-drawing annotations, drawings authored before shape tools, or
    /// corrupt JSON.
    var decodedShapes: [TelestrationShape] {
        TelestrationShapesCodec.decode(shapes)
    }
}
