//
//  Quality ComparisonRow.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI

struct QualityComparisonRow: View {
    let quality: UIImagePickerController.QualityType
    let isSelected: Bool
    
    private var qualityInfo: (name: String, size: String, color: Color) {
        switch quality {
        case .typeHigh:
            return ("High (1080p)", "~60MB/min", .purple)
        case .typeMedium:
            return ("Medium (720p)", "~25MB/min", .blue)
        case .typeLow:
            return ("Low (480p)", "~10MB/min", .green)
        case .type640x480:
            return ("SD (480p)", "~8MB/min", .orange)
        default:
            return ("High", "~60MB/min", .purple)
        }
    }
    
    var body: some View {
        let info = qualityInfo
        
        HStack(spacing: 12) {
            Circle()
                .fill(isSelected ? info.color : Color(.systemGray4))
                .frame(width: 8, height: 8)
            
            Text(info.name)
                .font(.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .fontWeight(isSelected ? .medium : .regular)
            
            Spacer()
            
            Text(info.size)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}
