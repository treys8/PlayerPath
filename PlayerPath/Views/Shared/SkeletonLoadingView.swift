//
//  SkeletonLoadingView.swift
//  PlayerPath
//
//  Skeleton loading placeholders with shimmer animation
//

import SwiftUI

// MARK: - Skeleton Shape Types

enum SkeletonShape {
    case textLine(width: CGFloat = .infinity, height: CGFloat = 14)
    case card(height: CGFloat = 120)
    case thumbnail(width: CGFloat = 80, height: CGFloat = 80)
    case circle(diameter: CGFloat = 40)
    case rectangle(width: CGFloat = .infinity, height: CGFloat = 40, cornerRadius: CGFloat = 8)
}

// MARK: - Shimmer Modifier

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
                .opacity(0.6)
        } else {
            content
                .overlay(
                    GeometryReader { geometry in
                        LinearGradient(
                            gradient: Gradient(colors: [
                                .clear,
                                Color.primary.opacity(0.1),
                                .clear
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geometry.size.width * 0.6)
                        .offset(x: -geometry.size.width * 0.3 + (geometry.size.width * 1.6) * phase)
                    }
                    .mask(content)
                )
                .onAppear {
                    withAnimation(
                        .linear(duration: 1.5)
                        .repeatForever(autoreverses: false)
                    ) {
                        phase = 1
                    }
                }
        }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Single Skeleton Element

struct SkeletonElement: View {
    let shape: SkeletonShape

    var body: some View {
        switch shape {
        case .textLine(let width, let height):
            RoundedRectangle(cornerRadius: height / 2)
                .fill(Color(.systemGray5))
                .frame(maxWidth: width == .infinity ? .infinity : width, minHeight: height, maxHeight: height)

        case .card(let height):
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray5))
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)

        case .thumbnail(let width, let height):
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray5))
                .frame(width: width, height: height)

        case .circle(let diameter):
            Circle()
                .fill(Color(.systemGray5))
                .frame(width: diameter, height: diameter)

        case .rectangle(let width, let height, let cornerRadius):
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(.systemGray5))
                .frame(maxWidth: width == .infinity ? .infinity : width, minHeight: height, maxHeight: height)
        }
    }
}

// MARK: - Dashboard Skeleton

/// Skeleton placeholder that mimics the dashboard card grid layout
struct DashboardSkeletonView: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 32) {
                // Quick Actions skeleton
                VStack(spacing: 16) {
                    skeletonSectionHeader
                    HStack(spacing: 12) {
                        SkeletonElement(shape: .card(height: 60))
                        SkeletonElement(shape: .card(height: 60))
                    }
                }
                .padding(.horizontal)

                // Management grid skeleton
                VStack(spacing: 16) {
                    skeletonSectionHeader
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(0..<6, id: \.self) { _ in
                            SkeletonElement(shape: .card(height: 90))
                        }
                    }
                }
                .padding(.horizontal)

                // Quick Stats skeleton
                VStack(spacing: 16) {
                    skeletonSectionHeader
                    HStack(spacing: 12) {
                        ForEach(0..<3, id: \.self) { _ in
                            SkeletonElement(shape: .card(height: 70))
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .shimmer()
        .allowsHitTesting(false)
        .accessibilityLabel("Loading dashboard")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var skeletonSectionHeader: some View {
        HStack(spacing: 8) {
            SkeletonElement(shape: .circle(diameter: 20))
            SkeletonElement(shape: .textLine(width: 120, height: 18))
            Spacer()
        }
    }
}

// MARK: - Video Grid Skeleton

/// Skeleton placeholder that mimics the video clips grid layout
struct VideoGridSkeletonView: View {
    let columns: Int

    init(columns: Int = 2) {
        self.columns = columns
    }

    var body: some View {
        let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: columns)

        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(0..<8, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonElement(shape: .rectangle(width: .infinity, height: 120, cornerRadius: 8))
                        SkeletonElement(shape: .textLine(width: 100, height: 12))
                        SkeletonElement(shape: .textLine(width: 60, height: 10))
                    }
                }
            }
            .padding()
        }
        .shimmer()
        .allowsHitTesting(false)
        .accessibilityLabel("Loading videos")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Generic List Skeleton

/// Skeleton placeholder for list-style layouts
struct ListSkeletonView: View {
    let rowCount: Int

    init(rowCount: Int = 5) {
        self.rowCount = rowCount
    }

    var body: some View {
        VStack(spacing: 16) {
            ForEach(0..<rowCount, id: \.self) { _ in
                HStack(spacing: 12) {
                    SkeletonElement(shape: .circle(diameter: 40))
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonElement(shape: .textLine(width: 180, height: 14))
                        SkeletonElement(shape: .textLine(width: 100, height: 10))
                    }
                    Spacer()
                }
            }
        }
        .padding()
        .shimmer()
        .allowsHitTesting(false)
    }
}

// MARK: - Previews

#Preview("Dashboard Skeleton") {
    DashboardSkeletonView()
}

#Preview("Video Grid Skeleton") {
    VideoGridSkeletonView()
}

#Preview("List Skeleton") {
    ListSkeletonView()
}

#Preview("Individual Elements") {
    VStack(spacing: 20) {
        SkeletonElement(shape: .textLine())
        SkeletonElement(shape: .textLine(width: 200))
        SkeletonElement(shape: .card())
        HStack {
            SkeletonElement(shape: .thumbnail())
            SkeletonElement(shape: .thumbnail())
        }
        SkeletonElement(shape: .circle())
    }
    .padding()
    .shimmer()
}
