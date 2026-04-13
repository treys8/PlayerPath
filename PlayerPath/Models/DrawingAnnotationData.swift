//
//  DrawingAnnotationData.swift
//  PlayerPath
//
//  Serialization helpers for PencilKit drawings stored as
//  base64-encoded data on VideoAnnotation documents.
//

import PencilKit

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
}

// MARK: - PKDrawing Serialization

extension PKDrawing {
    /// Base64-encoded string of the drawing's binary representation.
    var base64String: String {
        dataRepresentation().base64EncodedString()
    }

    /// Decodes a drawing from a base64-encoded string.
    /// Returns nil if the string is invalid or the data can't be parsed.
    init?(base64String: String) {
        guard let data = Data(base64Encoded: base64String) else { return nil }
        do {
            self = try PKDrawing(data: data)
        } catch {
            return nil
        }
    }
}
