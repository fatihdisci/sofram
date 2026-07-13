//
//  TextLogView.swift
//  Sofra — free-text meal logging alternative.
//
//  User types "2 kepçe mercimek, 1 dilim ekmek" style description.
//  Sent through the same AI proxy (mode: "text") — the backend parses
//  and returns the same VisionResponse shape. The ResultView is reused
//  for the output.
//
//  The draft lives on NavigationModel so backing out of a result (or
//  accidentally closing) never loses typed text. The close button returns
//  to whichever screen opened this one (camera or daily).
//

import SwiftUI

enum TextLogInputPolicy {
    static let maxCharacters = 300
    static let counterThreshold = 240

    static func limited(_ text: String) -> String {
        String(text.prefix(maxCharacters))
    }
}

struct TextLogView: View {
    @Environment(NavigationModel.self) private var nav

    @State private var textInput: String = ""
    @State private var isScanning = false
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    private let client = AIProxyClient()

    /// One-tap starters for the most common Turkish quick entries.
    private let suggestions = [
        "1 çay", "1 simit", "2 kepçe mercimek çorbası", "1 dilim ekmek",
        "1 kase yoğurt", "1 su bardağı ayran", "2 adet yumurta", "1 kase salata",
    ]

    var body: some View {
        ZStack {
            Color.bgPage.ignoresSafeArea()

            VStack(spacing: Layout.Spacing.lg) {
                header

                // Text input area — inset "pressed" surface per the neomorphic language
                VStack(alignment: .leading, spacing: Layout.Spacing.sm) {
                    Text("NE YEDİN?")
                        .font(.sofraEyebrow)
                        .tracking(1.2)
                        .foregroundStyle(Color.textMuted)

                    ZStack(alignment: .topLeading) {
                        if textInput.isEmpty {
                            Text("Örn: 2 kepçe mercimek çorbası, 1 dilim ekmek, 1 kase yoğurt")
                                .font(.sofraBody)
                                .foregroundStyle(Color.textMuted)
                                .padding(.horizontal, Layout.Spacing.md)
                                .padding(.vertical, Layout.Spacing.md)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $textInput)
                            .font(.sofraBody)
                            .foregroundStyle(Color.textPrimary)
                            .scrollContentBackground(.hidden)
                            .padding(Layout.Spacing.sm)
                            .focused($isFocused)

                        if textInput.count >= TextLogInputPolicy.counterThreshold {
                            Text("\(textInput.count)/\(TextLogInputPolicy.maxCharacters)")
                                .font(.sofraCaption)
                                .foregroundStyle(Color.textMuted)
                                .frame(
                                    maxWidth: .infinity,
                                    maxHeight: .infinity,
                                    alignment: .bottomTrailing
                                )
                                .padding(Layout.Spacing.md)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(minHeight: 120, maxHeight: 180)
                    .pressedSurface(cornerRadius: Layout.Radius.card)
                }
                .padding(.horizontal, Layout.Spacing.lg)

                // Quick suggestion chips
                suggestionChips

                analyzeButton

                Spacer()
            }
        }
        .onAppear {
            textInput = nav.textLogDraft
            // Slight delay so the screen transition lands before the keyboard rises.
            Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                isFocused = true
            }
        }
        .onChange(of: textInput) { _, newValue in
            let limited = TextLogInputPolicy.limited(newValue)
            if limited != newValue {
                textInput = limited
            }
            nav.textLogDraft = limited
        }
        .alert("Analiz başarısız", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                nav.closeTextLog()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 42, height: 42)
                    .background(Color.surfaceRaised, in: Circle())
                    .raisedSurface(cornerRadius: 21)
            }
            Spacer()
            Text("Yazarak Ekle")
                .font(.sofraHeading)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            // Balance the xmark width
            Color.clear.frame(width: 42, height: 42)
        }
        .padding(.horizontal, Layout.Spacing.lg)
        .padding(.top, Layout.Spacing.md)
    }

    // MARK: - Suggestion chips

    private var suggestionChips: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.sm) {
            Text("HIZLI EKLE")
                .font(.sofraEyebrow)
                .tracking(1.2)
                .foregroundStyle(Color.textMuted)
                .padding(.horizontal, Layout.Spacing.lg)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Layout.Spacing.sm) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            appendSuggestion(suggestion)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(suggestion)
                                    .font(.sofraCaption)
                            }
                            .foregroundStyle(Color.textPrimary)
                            .padding(.horizontal, Layout.Spacing.md)
                            .padding(.vertical, Layout.Spacing.sm)
                            .background(Color.surfaceRaised, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.borderHairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Layout.Spacing.lg)
            }
        }
    }

    private func appendSuggestion(_ suggestion: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let trimmed = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        withAnimation(.sofraSpring) {
            textInput = trimmed.isEmpty ? suggestion : "\(trimmed), \(suggestion)"
        }
    }

    // MARK: - Analyze button

    /// Translucent accentFill over the already-low-contrast bej page nearly
    /// disappeared in the empty state — a flat surfaceFlat/textMuted "neutral
    /// disabled" reads as a real button while still looking inactive, matching
    /// the secondary-button language used elsewhere (e.g. camera's Galeri chip).
    private var isInputEmpty: Bool {
        textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var analyzeButton: some View {
        Button {
            Task { await scan() }
        } label: {
            HStack(spacing: Layout.Spacing.sm) {
                if isScanning {
                    SofraIconView(icon: .kepce, size: 18)
                        .modifier(KepceWobbleModifier())
                } else {
                    SofraIconView(icon: .kepce, size: 18)
                }
                Text(isScanning ? "Analiz ediliyor..." : "Analiz Et")
                    .font(.sofraLabel)
            }
            .foregroundStyle(isInputEmpty ? Color.textMuted : Color.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Layout.Spacing.md)
            .background(
                isInputEmpty ? Color.surfaceFlat : Color.accentFill,
                in: RoundedRectangle(cornerRadius: Layout.Radius.control)
            )
        }
        .disabled(isInputEmpty || isScanning)
        .padding(.horizontal, Layout.Spacing.lg)
    }

    // MARK: - Scan

    private func scan() async {
        let text = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isFocused = false
        isScanning = true
        defer { isScanning = false }

        do {
            let result = try await client.scanText(text)
            if !client.isDemoMode {
                FreeScanCounter.shared.recordScan()
            }
            // Reuse the result screen for text-log results
            nav.showResult(
                uiImage: UIImage(),
                items: result.response.items,
                source: .text,
                rawJSON: result.rawJSON
            )
        } catch {
            errorMessage = (error as? AIProxyError)?.localizedDescription
                ?? AIProxyError.scanFailed.localizedDescription
        }
    }
}

// MARK: - Kepçe wobble (replaces the generic SF sparkles pulse)

/// Gentle side-to-side wobble — "Sofra senin için karıştırıyor" metaphor.
private struct KepceWobbleModifier: ViewModifier {
    @State private var angle: Double = 0

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(angle), anchor: .bottom)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    angle = 8
                }
            }
    }
}
