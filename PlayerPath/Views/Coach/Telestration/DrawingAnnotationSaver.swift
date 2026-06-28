//
//  DrawingAnnotationSaver.swift
//  PlayerPath
//
//  Single saver for telestration drawings. Replaces the previously duplicated
//  paths in ClipReviewSheet.saveDrawing and CoachVideoPlayerViewModel.addDrawingAnnotation
//  (200KB size guard → base64 → shapes JSON encode → createAnnotation).
//

import Foundation
import PencilKit
import CoreGraphics

@MainActor
enum DrawingAnnotationSaver {

    enum SaveError: LocalizedError {
        case tooComplex
        case missingVideoID
        case underlying(Error)

        var errorDescription: String? {
            switch self {
            case .tooComplex:
                return "Drawing is too complex. Try simplifying and saving again."
            case .missingVideoID:
                return "This video is not available to annotate."
            case .underlying(let error):
                return "Failed to save drawing: \(error.localizedDescription)"
            }
        }
    }

    /// Encodes and persists a telestration drawing as a "drawing" `VideoAnnotation`.
    /// Throws `SaveError` for caller-actionable failures (size cap, missing
    /// video ID) and wraps underlying Firestore errors. Permission rechecks
    /// live at the UI boundary — they need a folder ref this saver doesn't.
    static func save(
        videoID: String,
        drawing: PKDrawing,
        shapes: [TelestrationShape],
        timestamp: Double,
        canvasSize: CGSize,
        userID: String,
        userName: String,
        isCoachComment: Bool = true
    ) async throws -> VideoAnnotation {
        let raw = drawing.dataRepresentation()
        guard raw.count <= TelestrationConstants.maxDrawingByteSize else {
            throw SaveError.tooComplex
        }
        guard !videoID.isEmpty else {
            throw SaveError.missingVideoID
        }

        let base64 = raw.base64EncodedString()
        let shapesJSON = TelestrationShapesCodec.encode(shapes)
        if let shapesJSON, shapesJSON.utf8.count > TelestrationConstants.maxShapesByteSize {
            throw SaveError.tooComplex
        }

        do {
            return try await FirestoreManager.shared.createAnnotation(
                videoID: videoID,
                text: "Drawing annotation",
                timestamp: timestamp,
                userID: userID,
                userName: userName,
                isCoachComment: isCoachComment,
                type: "drawing",
                drawingData: base64,
                drawingCanvasWidth: canvasSize.width > 0 ? Double(canvasSize.width) : nil,
                drawingCanvasHeight: canvasSize.height > 0 ? Double(canvasSize.height) : nil,
                shapes: shapesJSON
            )
        } catch {
            throw SaveError.underlying(error)
        }
    }
}
