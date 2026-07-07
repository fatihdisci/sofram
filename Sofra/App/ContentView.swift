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
        .onOpenURL { url in
            // Deep links (widget + future lock-screen quick actions):
            //  sofra://daily → daily summary, sofra://camera → capture,
            //  sofra://textlog → text logging.
            guard url.scheme == "sofra" else { return }
            switch url.host {
            case "daily":   nav.goToDaily()
            case "camera":  nav.goToCamera()
            case "textlog": nav.goToTextLog(from: .daily)
            default: break
            }
        }
    }

    // MARK: - Main app flow

    private var mainFlow: some View {
        Group {
            switch nav.screen {
            case .camera:
                // Both scan entry points (photo + text) consume the same
                // lifetime free-scan allowance, so both are gated here.
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
                if FreeScanCounter.shared.canScanForFree {
                    TextLogView()
                } else {
                    FreeScanLimitView()
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: nav.screen)
    }
}

// MARK: - Free scan limit → paywall

struct FreeScanLimitView: View {
    @Environment(NavigationModel.self) private var nav
    @State private var counter = FreeScanCounter.shared
    @State private var showPaywall = false

    var body: some View {
        ZStack {
            Color.bgPage.ignoresSafeArea()

            VStack(spacing: Layout.Spacing.lg) {
                // Back to daily — the limit screen must never be a dead end
                HStack {
                    Button {
                        nav.goToDaily()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.textPrimary)
                            .frame(width: 42, height: 42)
                            .background(Color.surfaceRaised, in: Circle())
                            .raisedSurface(cornerRadius: 21)
                    }
                    Spacer()
                }
                .padding(.horizontal, Layout.Spacing.lg)
                .padding(.top, Layout.Spacing.md)

                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.surfaceRaised)
                        .frame(width: 120, height: 120)
                        .raisedSurface(cornerRadius: 60)
                    SofraIconView(icon: .sofra, size: 56)
                        .foregroundStyle(Color.accentFill)
                }

                Text("Ücretsiz taramaların bitti")
                    .font(.sofraTitle)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)

                Text("3 ücretsiz taramanın üçünü de kullandın.\nSınırsız taramayla devam et — istediğin an iptal.")
                    .font(.sofraBody)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)

                Button {
                    showPaywall = true
                } label: {
                    Text("Sınırsız Taramaya Geç")
                        .font(.sofraLabel)
                        .foregroundStyle(Color.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Layout.Spacing.md)
                        .background(Color.accentFill, in: RoundedRectangle(cornerRadius: Layout.Radius.control))
                }
                .padding(.horizontal, Layout.Spacing.xl)
                .padding(.top, Layout.Spacing.sm)

                Spacer()
                Spacer()
            }
            .padding(Layout.Spacing.lg)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(onComplete: { showPaywall = false },
                        skipTitle: "Şimdilik kapat")
        }
    }
}
