//
//  AnalysisOverlay.swift
//  Calorisor — post-capture analysis screen with staggered item reveal.
//
//  No spinner and no "AI magic" laser sweep. The captured photo stays visible
//  under an honest processing treatment: viewfinder corner brackets framing the
//  plate, a rotating status caption naming the real step (inceleniyor →
//  ölçülüyor → hesaplanıyor) and a flat 3-segment stepped progress that tracks
//  that step. Recognized items appear one by one (150ms stagger, fade+scale
//  0.9→1). When all items are revealed, a medium haptic fires and the result
//  screen takes over.
//
//  Failures land in a bottom card with distinct copy for "the proxy isn't
//  configured yet" vs. a transient error, plus retry-in-place and cancel.
//

import SwiftUI
import UIKit

struct AnalysisOverlay: View {
    @Environment(NavigationModel.self) private var nav

    let imageData: Data
    let uiImage: UIImage

    @State private var revealedItems: [VisionItem] = []
    @State private var revealedCount = 0
    @State private var scanError: AIProxyError?
    @State private var allRevealed = false
    @State private var statusIndex = 0
    @State private var scanTask: Task<Void, Never>?

    private let client = AIProxyClient()

    private let statusCaptions = [
        "Tabak inceleniyor…",
        "Porsiyonlar ölçülüyor…",
        "Kaloriler hesaplanıyor…",
    ]

    private var isScanning: Bool {
        scanError == nil && !allRevealed && revealedCount == 0
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Captured photo, shown in full — .fill was cropping/zooming hard
            // since a 3:4 photo stretched to fill a ~9:19.5 screen loses most
            // of the frame. .fit letterboxes on the black background instead,
            // so the whole plate stays visible (camera capture and gallery
            // picks alike, any aspect ratio).
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(.black.opacity(0.35))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .ignoresSafeArea()

            // Viewfinder treatment while scanning
            if isScanning {
                scanningTreatment
            }

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
                Spacer()
            }
            .padding(Layout.Spacing.xl)

            // Top bar: cancel + demo pill
            VStack {
                HStack {
                    Button {
                        scanTask?.cancel()
                        nav.goToCamera()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(.ultraThinMaterial, in: Circle())
                        .accessibilityLabel(String(localized: "Vazgeç"))
                    }
                    Spacer()
                    if client.isDemoMode {
                        Text("Demo verisi")
                            .font(.calorisorCaption)
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, Layout.Spacing.md)
                            .padding(.vertical, Layout.Spacing.xs)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                .padding(.horizontal, Layout.Spacing.lg)
                .padding(.top, Layout.Spacing.sm)
                Spacer()
            }

            // Error card
            if let scanError {
                VStack {
                    Spacer()
                    errorCard(for: scanError)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .task {
            startScan()
        }
        .onDisappear {
            scanTask?.cancel()
        }
    }

    // MARK: - Scanning treatment

    private var scanningTreatment: some View {
        VStack(spacing: Layout.Spacing.lg) {
            // Honest viewfinder framing — no laser sweep.
            CornerBrackets()
                .stroke(.white.opacity(0.6), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 280, height: 280)

            VStack(spacing: Layout.Spacing.md) {
                // Rotating status caption — names the real step in progress
                Text(statusCaptions[statusIndex])
                    .font(.calorisorLabel)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, Layout.Spacing.md)
                    .padding(.vertical, Layout.Spacing.xs)
                    .background(.black.opacity(0.35), in: Capsule())
                    .contentTransition(.opacity)
                    .id(statusIndex)
                    .transition(.opacity)

                // Flat stepped progress — clear "step k of 3", no glow/gradient
                HStack(spacing: 6) {
                    ForEach(0..<statusCaptions.count, id: \.self) { i in
                        Capsule()
                            .fill(i == statusIndex ? Color.accentFill : Color.white.opacity(0.3))
                            .frame(width: i == statusIndex ? 22 : 14, height: 4)
                            .animation(.calorisorSpring, value: statusIndex)
                    }
                }
            }
        }
        .offset(y: -20)
        .allowsHitTesting(false)
    }

    // MARK: - Error card

    private func errorCard(for error: AIProxyError) -> some View {
        VStack(spacing: Layout.Spacing.md) {
            Image(systemName: errorPresentation(for: error).icon)
                .font(.system(size: 30))
                .foregroundStyle(Color.accentFill)

            Text(errorPresentation(for: error).title)
                .font(.calorisorHeading)
                .foregroundStyle(Color.textPrimary)

            Text(error.localizedDescription)
                .font(.calorisorBody)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Layout.Spacing.md) {
                Button {
                    nav.goToCamera()
                } label: {
                    Text("Vazgeç")
                        .font(.calorisorLabel)
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Layout.Spacing.md)
                        .background(Color.surfaceFlat, in: RoundedRectangle(cornerRadius: Layout.Radius.control))
                }

                Button {
                    startScan()
                } label: {
                    Text("Tekrar dene")
                        .font(.calorisorLabel)
                        .foregroundStyle(Color.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Layout.Spacing.md)
                        .background(Color.accentFill, in: RoundedRectangle(cornerRadius: Layout.Radius.control))
                }
            }
            .padding(.top, Layout.Spacing.xs)
        }
        .padding(Layout.Spacing.xl)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.raisedContainer))
        .raisedSurface(cornerRadius: Layout.Radius.raisedContainer)
        .padding(Layout.Spacing.lg)
        .padding(.bottom, Layout.Spacing.lg)
    }

    private func errorPresentation(for error: AIProxyError) -> (icon: String, title: String) {
        switch error {
        case .notConfigured:
            return ("antenna.radiowaves.left.and.right.slash", "Sunucu bağlı değil")
        case .rateLimited:
            return ("clock.fill", "Biraz bekle")
        case .offline:
            return ("wifi.slash", "Bağlantı yok")
        case .serverError:
            return ("server.rack", "Sunucu sorunu")
        case .invalidConfiguration, .scanFailed:
            return ("wifi.exclamationmark", "Analiz başarısız")
        }
    }

    // MARK: - Scan flow

    private func startScan() {
        scanTask?.cancel()
        withAnimation(.calorisorSpring) { scanError = nil }
        statusIndex = 0

        scanTask = Task {
            // Rotate status captions while the request is in flight
            let captionTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_600_000_000)
                    if Task.isCancelled { break }
                    withAnimation(.calorisorSpring) {
                        statusIndex = (statusIndex + 1) % statusCaptions.count
                    }
                }
            }
            defer { captionTask.cancel() }

            do {
                let result = try await client.scan(imageData: imageData)
                guard !Task.isCancelled else { return }
                if !client.isDemoMode {
                    FreeScanCounter.shared.recordScan()
                }
                captionTask.cancel()
                await revealItems(result.response.items, rawJSON: result.rawJSON)
            } catch {
                guard !Task.isCancelled else { return }
                captionTask.cancel()
                withAnimation(.calorisorSpring) {
                    scanError = (error as? AIProxyError) ?? .scanFailed
                }
            }
        }
    }

    private func revealItems(_ items: [VisionItem], rawJSON: String) async {
        guard !items.isEmpty else {
            // No food detected — go to result with empty items
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            try? await Task.sleep(nanoseconds: 200_000_000)
            nav.showResult(uiImage: uiImage, items: [], rawJSON: rawJSON)
            return
        }

        revealedItems = items
        // Stagger reveal: 150ms per item
        for i in 1...items.count {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                revealedCount = i
            }
        }
        allRevealed = true

        // Medium haptic when all items are revealed
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Brief pause before transitioning to result
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }
        nav.showResult(uiImage: uiImage, items: items, rawJSON: rawJSON)
    }
}

// MARK: - Recognized item badge (on-photo overlay)

struct RecognizedItemBadge: View {
    let item: VisionItem
    let index: Int

    var body: some View {
        HStack(spacing: Layout.Spacing.sm) {
            // Icon based on portion unit
            CalorisorIconView(icon: item.portionUnit.icon ?? .tabak, size: 28)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.calorisorLabel)
                    .foregroundStyle(.white)
                Text("\(String(format: "%.0f", item.calories)) kcal · \(item.householdQuantity, specifier: "%.1f") \(item.householdUnit)")
                    .font(.calorisorCaption)
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
