//
//  Icons.swift
//  PlayerPath
//
//  Centralized SF Symbol vocabulary for recurring UI actions and states.
//  Parallels DesignTokens.swift.
//
//  Usage: prefer AppIcon.* over raw strings for common actions so variants
//  stay consistent. Domain-specific one-offs (sport icons, tab icons, etc.)
//  can keep their raw `systemName:` strings.
//

import Foundation

enum AppIcon {
    // MARK: - Actions

    /// Bare toolbar add button (no circle). Use in navigation bar trailing items.
    static let addToolbar = "plus"
    /// Inline "Add X" / "Create X" buttons in menus, sheets, and list rows.
    static let addInline = "plus.circle.fill"

    static let edit = "pencil"

    /// Standard delete action. Use in swipe actions, menus, and trash buttons.
    static let delete = "trash"
    /// `.fill` variant for permission badges and destructive primary buttons
    /// where visual weight communicates gravity. Not for standard delete actions.
    static let deleteEmphasis = "trash.fill"

    /// Bare toolbar dismiss. Use for "Cancel" / "Close" toolbar buttons.
    static let close = "xmark"

    /// iOS system share sheet (export, send outside the app).
    static let share = "square.and.arrow.up"
    /// Send to a specific person inside the app (invite, share-with-athlete).
    static let send = "paperplane.fill"
    /// Upload a video from the device library to a folder/cloud.
    static let upload = "square.and.arrow.down.on.square"

    static let settings = "gearshape"
    static let more = "ellipsis.circle.fill"
    static let back = "chevron.left"
    static let forward = "chevron.right"

    // MARK: - Status

    static let success = "checkmark.circle.fill"
    /// Plain checkmark for filter indicators and menu selection state.
    static let check = "checkmark"
    static let warning = "exclamationmark.triangle.fill"
    static let error = "exclamationmark.triangle.fill"
    static let info = "info.circle"

    // MARK: - Entities

    static let addPerson = "person.badge.plus"
    static let recordVideo = "video.badge.plus"
}
