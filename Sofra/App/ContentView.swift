//
//  ContentView.swift
//  Sofra — placeholder root view for Phase 1.
//
//  No real UI yet (camera, scanning, onboarding, paywall are later phases). This
//  view exists to confirm the app builds and to smoke-test that the design system
//  links: it exercises a color token, a font token, the raised-surface modifier,
//  and a custom Sofra icon in one place.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            Color.bgPage
                .ignoresSafeArea()

            VStack(spacing: Layout.Spacing.lg) {
                SofraIconView(icon: .sofra, size: 56)
                    .foregroundStyle(Color.accentFill)

                Text("Sofra")
                    .font(.sofraTitle)
                    .foregroundStyle(Color.textPrimary)

                Text("Phase 1 · foundation")
                    .font(.sofraCaption)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(Layout.Spacing.xxl)
            .raisedSurface()
        }
    }
}

#Preview {
    ContentView()
}
