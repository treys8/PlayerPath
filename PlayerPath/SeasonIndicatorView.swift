//
//  SeasonIndicatorView.swift
//  PlayerPath
//
//  Created by Assistant on 11/13/25.
//

import SwiftUI
import SwiftData

/// A compact indicator showing the current active season, with tap to manage
struct SeasonIndicatorView: View {
    let athlete: Athlete
    @State private var showingSeasonManagement = false
    
    var body: some View {
        Button {
            showingSeasonManagement = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: athlete.activeSeason?.sport.icon ?? "calendar")
                    .font(.caption)
                    .foregroundStyle(.blue)
                
                if let activeSeason = athlete.activeSeason {
                    Text(activeSeason.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                } else {
                    Text("No Active Season")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(.blue.opacity(0.1))
            }
        }
        .sheet(isPresented: $showingSeasonManagement) {
            NavigationStack {
                SeasonManagementView(athlete: athlete)
            }
        }
    }
}

/// A banner that shows season recommendations or warnings
struct SeasonRecommendationBanner: View {
    let athlete: Athlete
    let recommendation: SeasonManager.SeasonRecommendation
    @Environment(\.modelContext) private var modelContext
    @State private var showingSeasonManagement = false
    @State private var dismissed = false
    
    private var dismissedKey: String {
        "seasonBanner_\(athlete.id.uuidString)"
    }
    
    var body: some View {
        if !dismissed && !UserDefaults.standard.bool(forKey: dismissedKey), let message = recommendation.message {
            HStack(spacing: 12) {
                Image(systemName: iconForRecommendation)
                    .font(.title3)
                    .foregroundStyle(colorForRecommendation)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(titleForRecommendation)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    showingSeasonManagement = true
                } label: {
                    Text("Manage")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(colorForRecommendation.opacity(0.2))
                        .foregroundStyle(colorForRecommendation)
                        .clipShape(Capsule())
                }
                
                Button {
                    withAnimation {
                        dismissed = true
                        UserDefaults.standard.set(true, forKey: dismissedKey)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorForRecommendation.opacity(0.1))
            }
            .sheet(isPresented: $showingSeasonManagement) {
                NavigationStack {
                    SeasonManagementView(athlete: athlete)
                }
            }
        }
    }
    
    private var iconForRecommendation: String {
        switch recommendation {
        case .createFirst, .noActiveSeason:
            return "calendar.badge.plus"
        case .considerEnding:
            return "calendar.badge.exclamationmark"
        case .ok:
            return "checkmark.circle"
        }
    }
    
    private var colorForRecommendation: Color {
        switch recommendation {
        case .createFirst, .noActiveSeason:
            return .blue
        case .considerEnding:
            return .orange
        case .ok:
            return .green
        }
    }
    
    private var titleForRecommendation: String {
        switch recommendation {
        case .createFirst:
            return "Get Started"
        case .noActiveSeason:
            return "Season Needed"
        case .considerEnding:
            return "Season Check"
        case .ok:
            return "All Set"
        }
    }
}

/// A full-page prompt to create the first season (used in onboarding or empty states)
struct CreateFirstSeasonPrompt: View {
    let athlete: Athlete
    @Environment(\.modelContext) private var modelContext
    @State private var showingCreateSeason = false
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 80))
                .foregroundStyle(.blue)
            
            VStack(spacing: 8) {
                Text("Start Your First Season")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Organize your baseball journey by season. All games, practices, and videos will be saved in your active season.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "figure.baseball", text: "Track games and tournaments")
                FeatureRow(icon: "video", text: "Record and organize videos")
                FeatureRow(icon: "chart.line.uptrend.xyaxis", text: "View season statistics")
                FeatureRow(icon: "archivebox", text: "Archive seasons to keep history clean")
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.blue.opacity(0.1))
            }
            .padding(.horizontal)
            
            Button {
                showingCreateSeason = true
            } label: {
                Label("Create Season", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
            
            Button("I'll Do This Later") {
                // Create a default season in the background
                _ = SeasonManager.ensureActiveSeason(for: athlete, in: modelContext)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding()
        .sheet(isPresented: $showingCreateSeason) {
            CreateSeasonView(athlete: athlete)
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 30)
            
            Text(text)
                .font(.subheadline)
            
            Spacer()
        }
    }
}

// MARK: - Preview

#Preview("Season Indicator") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container: ModelContainer = {
        if let c = try? ModelContainer(for: Athlete.self, Season.self, configurations: config) {
            return c
        }
        // Fallback to an in-memory container without configurations
        return (try? ModelContainer(for: Athlete.self, Season.self)) ?? {
            // As a last resort, create an empty container using only Athlete to keep previews running
            // Note: adjust types if needed in your project
            return try! ModelContainer(for: Athlete.self, Season.self)
        }()
    }()
    
    let athlete = Athlete(name: "Test Player")
    let season = Season(name: "Spring 2025", startDate: Date(), sport: .baseball)
    season.activate()
    season.athlete = athlete
    
    container.mainContext.insert(athlete)
    container.mainContext.insert(season)
    
    return VStack {
        SeasonIndicatorView(athlete: athlete)
    }
    .modelContainer(container)
    .padding()
}

#Preview("Create First Season") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container: ModelContainer = (try? ModelContainer(for: Athlete.self, Season.self, configurations: config)) ?? (try! ModelContainer(for: Athlete.self, Season.self))
    
    let athlete = Athlete(name: "Test Player")
    container.mainContext.insert(athlete)
    
    return CreateFirstSeasonPrompt(athlete: athlete)
        .modelContainer(container)
}

#Preview("Season Recommendation Banner") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container: ModelContainer = (try? ModelContainer(for: Athlete.self, Season.self, configurations: config)) ?? (try! ModelContainer(for: Athlete.self, Season.self))
    
    let athlete = Athlete(name: "Test Player")
    container.mainContext.insert(athlete)
    
    return VStack {
        SeasonRecommendationBanner(
            athlete: athlete,
            recommendation: .createFirst
        )
        .padding()
        
        SeasonRecommendationBanner(
            athlete: athlete,
            recommendation: .noActiveSeason
        )
        .padding()
    }
    .modelContainer(container)
}

