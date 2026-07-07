//
//  ContentView.swift
//  Sofra — navigation state machine root.
//
//  First launch: onboarding quiz → paywall placeholder → main flow.
//  Subsequent launches: camera is the root screen.
//
//  Camera is the root (no tab bar). Flow branches:
//   camera → capture → analysis → result → daily
//   camera → textLog → result → daily
//

import SwiftUI

struct ContentView: View {
    @Environment(NavigationModel.self) private var nav

    @AppStorage("sofra.onboardingCompleted") private var onboardingCompleted = false

    var body: some View {
        ZStack {
            if !onboardingCompleted {
                OnboardingView()
            } else {
                mainFlow
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: onboardingCompleted)
    }

    // MARK: - Main app flow

    private var mainFlow: some View {
        Group {
            switch nav.screen {
            case .camera:
                if FreeScanCounter.shared.canScanForFree {
                    CameraView()
                } else {
                    FreeScanLimitView()
                }

            case .analyzing(let imageData, let uiImage):
                AnalysisOverlay(imageData: imageData, uiImage: uiImage)

            case .result(let uiImage, let items, let source):
                ResultView(uiImage: uiImage, items: items, source: source)

            case .daily:
                DailyView()

            case .textLog:
                TextLogView()
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: nav.screen)
    }
}

// MARK: - Free scan limit placeholder

struct FreeScanLimitView: View {
    @State private var counter = FreeScanCounter.shared

    var body: some View {
        ZStack {
            Color.bgPage.ignoresSafeArea()

            VStack(spacing: Layout.Spacing.xl) {
                Spacer()

                Image(systemName: "camera.metering.none")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.textMuted)

                Text("Ücretsiz Tarama Hakkınız Bitti")
                    .font(.sofraHeading)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Sofra'yı kullanmaya devam etmek için\nsınırsız taramaya yükseltin.")
                    .font(.sofraBody)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)

                Button("Yakında") {
                    // No-op — paywall is Phase 3b
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentFill)

                Spacer()
            }
            .padding(Layout.Spacing.xxl)
        }
    }
}
