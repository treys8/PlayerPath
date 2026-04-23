//
//  TelestrationToolMode.swift
//  PlayerPath
//
//  Drawing tool selection for the telestration toolbar. Only freehand uses
//  PencilKit; the other modes capture a drag gesture and emit a TelestrationShape.
//

import SwiftUI

enum TelestrationToolMode: String, CaseIterable, Identifiable {
    case freehand
    case arrow
    case line
    case circle
    case rectangle

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .freehand:  return "scribble.variable"
        case .arrow:     return "arrow.up.right"
        case .line:      return "line.diagonal"
        case .circle:    return "circle"
        case .rectangle: return "rectangle"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .freehand:  return "Freehand"
        case .arrow:     return "Arrow"
        case .line:      return "Line"
        case .circle:    return "Circle"
        case .rectangle: return "Rectangle"
        }
    }

    /// Shape kind this tool produces. `nil` for freehand (uses PencilKit).
    var shapeKind: TelestrationShapeKind? {
        switch self {
        case .freehand:  return nil
        case .arrow:     return .arrow
        case .line:      return .line
        case .circle:    return .circle
        case .rectangle: return .rectangle
        }
    }
}
