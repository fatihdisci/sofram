//
//  AnalysisOverlay.swift
//  Sofra — post-capture analysis screen with staggered item reveal.
//
//  No spinner. The captured photo stays visible while recognized items appear
//  one by one (150ms stagger, fade+scale 0.9→1). When all items are revealed,
//  a medium haptic fires and the result screen takes over.
//

import SwiftUI
import UIKit

struct AnalysisOverlay: View {
    @Environment(NavigationModel.self) private var nav

    let imageData: Data
    let uiImage: UIImage

    @State private var revealedItems: [VisionItem] = []
    @State private var revealedCount = 0
    @State private var errorOccurred = false
    @State private var allRevealed = false

    private let client = AIProxyClient()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Captured photo as background
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .ignoresSafeArea()
                .overlay(.black.opacity(0.35))
                .allowsHitTesting(false)

            // Recognized items overlay
            VStack(spacing: Layout.Spacing.md) {
                Spacer()
                ForEach(Array(revealedItems.prefix(revealedCount).enumerated()), id: \.offset) { idx, item in
                    RecognizedItemBadge(item: item, index: idx)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.9).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
                if errorOccurred {
                    Text("Tarama başarısız oldu, lütfen tekrar deneyin.")
                        .font(.sofraBody)
                        .foregroundStyle(.white)
                        .padding()
                        Button("Tekrar dene") {
                            nav.goToCamera()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.accentFill)
                }
                Spacer()
            }
            .padding(Layout.Spacing.xl)

            // Subtle pulsing border during analysis (not a spinner)
            if !allRevealed && !errorOccurred {
                RoundedRectangle(cornerRadius: 0)
                    .stroke(.white.opacity(0.15), lineWidth: 2)
                    .ignoresSafeArea()
                    .opacity(pulsingOpacity ? 0.3 : 0.1)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                               value: pulsingOpacity)
            }
        }
        .task {
            await performScan()
        }
    }

    @State private var pulsingOpacity = false

    private func performScan() async {
        // Subtle pulse during the network call
        pulsingOpacity = true

        do {
            let response = try await client.scan(imageData: imageData)
            await revealItems(response.items)
        } catch {
            withAnimation { errorOccurred = true }
        }
    }

    private func revealItems(_ items: [VisionItem]) async {
        guard !items.isEmpty else {
            // No food detected — go to result with empty items
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            try? await Task.sleep(nanoseconds: 200_000_000)
            nav.showResult(uiImage: uiImage, items: [])
            return
        }

        revealedItems = items
        // Stagger reveal: 150ms per item
        for i in 1...items.count {
            try? await Task.sleep(nanoseconds: 150_000_000)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                revealedCount = i
            }
        }
        allRevealed = true

        // Medium haptic when all items are revealed
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        // Brief pause before transitioning to result
        try? await Task.sleep(nanoseconds: 300_000_000)
        nav.showResult(uiImage: uiImage, items: items)
    }
}

// MARK: - Recognized item badge (on-photo overlay)

struct RecognizedItemBadge: View {
    let item: VisionItem
    let index: Int

    var body: some View {
        HStack(spacing: Layout.Spacing.sm) {
            // Icon based on portion unit
            SofraIconView(icon: item.portionUnit.icon ?? .tabak, size: 28)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.sofraLabel)
                    .foregroundStyle(.white)
                Text("\(String(format: "%.0f", item.calories)) kcal · \(item.householdQuantity, specifier: "%.1f") \(item.householdUnit)")
                    .font(.sofraCaption)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            // Confidence indicator
            if item.confidence < 0.6 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.yellow)
            }
        }
        .padding(Layout.Spacing.md)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
    }
}
