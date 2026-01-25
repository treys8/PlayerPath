//
//  QualityDetailCard.swift
//  PlayerPath
//
//  Extracted from MainAppView.swift
//

import SwiftUI

struct QualityDetailCard: View {
    let quality: UIImagePickerController.QualityType
    
    private var qualityInfo: (name: String, resolution: String, mbPerMinute: Double, maxSize: String, icon: String, color: Color, description: String) {
        switch quality {
        case .typeHigh:
            return ("High Quality", "1080p", 60.0, "600MB", "sparkles.tv.fill", .purple, "Best quality for sharing and editing")
        case .typeMedium:
            return ("Medium Quality", "720p", 25.0, "250MB", "tv.fill", .blue, "Good balance of quality and file size")
        case .typeLow:
            return ("Low Quality", "480p", 10.0, "100MB", "tv", .green, "Smaller files, faster uploads")
        case .type640x480:
            return ("SD Quality", "480p", 8.0, "80MB", "tv.and.mediabox", .orange, "Minimum quality for quick sharing")
        default:
            return ("High Quality", "1080p", 60.0, "600MB", "sparkles.tv.fill", .purple, "Best quality")
        }
    }
    
    var body: some View {
        let info = qualityInfo
        
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: info.icon)
                    .font(.title2)
                    .foregroundStyle(info.color)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(info.color.opacity(0.15))
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(info.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    
                    Text(info.resolution)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
                    .symbolEffect(.bounce, value: quality)
            }
            .padding()
            
            Divider()
            
            // Stats
            HStack(spacing: 0) {
                QualityStatItem(
                    icon: "arrow.down.circle.fill",
                    label: "Per Minute",
                    value: "~\(Int(info.mbPerMinute))MB",
                    color: info.color
                )
                
                Divider()
                    .frame(height: 50)
                
                QualityStatItem(
                    icon: "doc.fill",
                    label: "Max Size",
                    value: info.maxSize,
                    color: info.color
                )
            }
            .padding(.vertical, 12)
            
            Divider()
            
            // Description
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.caption)
                    .foregroundStyle(info.color)
                
                Text(info.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
            }
            .padding()
            .background(info.color.opacity(0.05))
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(info.color.opacity(0.3), lineWidth: 1.5)
        )
    }
}
