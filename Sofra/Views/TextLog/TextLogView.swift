//
//  TextLogView.swift
//  Sofra — free-text meal logging alternative.
//
//  User types "2 kepçe mercimek, 1 dilim ekmek" style description.
//  Sent through the same AI proxy (mode: "text") — the backend parses
//  and returns the same VisionResponse shape. The ResultView is reused
//  for the output.
//

import SwiftUI

struct TextLogView: View {
    @Environment(NavigationModel.self) private var nav

    @State private var textInput: String = ""
    @State private var isScanning = false
    @State private var showError = false
    @FocusState private var isFocused: Bool

    private let client = AIProxyClient()

    var body: some View {
        ZStack {
            Color.bgPage.ignoresSafeArea()

            VStack(spacing: Layout.Spacing.xl) {
                // Header
                HStack {
                    Button {
                        nav.goToCamera()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.textPrimary)
                            .padding(Layout.Spacing.md)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    Spacer()
                    Text("Yazarak Ekle")
                        .font(.sofraHeading)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    // Balance the xmark width
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, Layout.Spacing.lg)
                .padding(.top, 60)

                // Text input area
                VStack(alignment: .leading, spacing: Layout.Spacing.sm) {
                    Text("Ne yedin?")
                        .font(.sofraLabel)
                        .foregroundStyle(Color.textSecondary)

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
                    }
                    .frame(minHeight: 160)
                    .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
                }
                .padding(.horizontal, Layout.Spacing.lg)

                // Send button
                Button {
                    Task { await scan() }
                } label: {
                    HStack(spacing: Layout.Spacing.sm) {
                        if isScanning {
                            ProgressView()
                                .tint(Color.onAccent)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(isScanning ? "Analiz ediliyor..." : "Analiz Et")
                            .font(.sofraLabel)
                    }
                    .foregroundStyle(Color.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Layout.Spacing.md)
                    .background(
                        textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? Color.accentFill.opacity(0.4) : Color.accentFill,
                        in: RoundedRectangle(cornerRadius: Layout.Radius.control)
                    )
                }
                .disabled(textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isScanning)
                .padding(.horizontal, Layout.Spacing.lg)

                // Tips
                VStack(alignment: .leading, spacing: Layout.Spacing.xs) {
                    Text("İpucu:")
                        .font(.sofraCaption)
                        .foregroundStyle(Color.textMuted)
                    Text("Yemek adı + miktar + birim şeklinde yazın.\nBirden fazla öğeyi virgülle ayırın.")
                        .font(.sofraCaption)
                        .foregroundStyle(Color.textMuted)
                }
                .padding(.horizontal, Layout.Spacing.lg)

                Spacer()
            }
        }
        .alert("Hata", isPresented: $showError) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text("Analiz başarısız oldu, lütfen tekrar deneyin.")
        }
        .onAppear { isFocused = true }
    }

    private func scan() async {
        let text = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isScanning = true
        defer { isScanning = false }

        do {
            let response = try await client.scanText(text)
            // Reuse the result screen for text-log results
            nav.showResult(uiImage: UIImage(), items: response.items, source: .text)
        } catch {
            showError = true
        }
    }
}
