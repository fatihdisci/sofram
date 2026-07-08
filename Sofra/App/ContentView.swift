//
//  ContentView.swift
//  Sofra — root: onboarding → tabbed home + scan-flow cover.
//
//  v2 structure:
//   • First launch: onboarding quiz → paywall.
//   • Home: a 3-tab bar — Bugün (daily) · Geçmiş (history) · Ayarlar (settings).
//   • The scan task-flow (camera → analysis → result, or text-log → result)
//     is presented as a full-screen cover over the tabs, driven by
//     NavigationModel.scanFlow. This keeps capture immersive while the home
//     stays a normal, navigable app.
//
//  NOTE: SettingsView lives in this file (rather than its own) so it compiles
//  against the committed .xcodeproj without a `xcodegen generate` step. It can
//  be split into Sofra/Views/Settings/ once the project is regenerated.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(NavigationModel.self) private var nav

    @AppStorage("sofra.onboardingCompleted") private var onboardingCompleted = false

    var body: some View {
        ZStack {
            if !onboardingCompleted {
                OnboardingView()
            } else {
                home
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: onboardingCompleted)
        .onOpenURL { url in
            // Deep links (widget + future lock-screen quick actions):
            //  sofra://daily → Bugün tab, sofra://camera → capture,
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

    // MARK: - Tabbed home + scan-flow cover

    @ViewBuilder
    private var home: some View {
        @Bindable var nav = nav

        TabView(selection: $nav.selectedTab) {
            DailyView()
                .tabItem { Label("Bugün", systemImage: "sun.max.fill") }
                .tag(AppTab.today)

            HistoryView()
                .tabItem { Label("Geçmiş", systemImage: "chart.bar.fill") }
                .tag(AppTab.history)

            SettingsView()
                .tabItem { Label("Ayarlar", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .tint(Color.accentFill)
        .fullScreenCover(isPresented: Binding(
            get: { nav.scanFlow != nil },
            set: { if !$0 { nav.scanFlow = nil } }
        )) {
            ScanFlowContainer()
                .environment(nav)
        }
    }
}

// MARK: - Scan flow container (full-screen cover)

/// Hosts the immersive scan task-flow. Free-scan gating that used to live in
/// the root switch now guards the two entry screens here.
struct ScanFlowContainer: View {
    @Environment(NavigationModel.self) private var nav

    var body: some View {
        Group {
            switch nav.scanFlow {
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

            case .textLog:
                if FreeScanCounter.shared.canScanForFree {
                    TextLogView()
                } else {
                    FreeScanLimitView()
                }

            case .none:
                Color.bgPage.ignoresSafeArea()
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: nav.scanFlow)
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

// MARK: - Settings tab

/// Ayarlar: editable profile, daily targets, subscription, and about.
/// Targets are stored in AppStorage (the same keys DailyView reads), so edits
/// here immediately drive the daily ring and macro cards.
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @AppStorage("sofra.dailyCalorieTarget") private var calorieTarget: Double = 2000
    @AppStorage("sofra.proteinTarget") private var proteinTarget: Double = 0
    @AppStorage("sofra.carbsTarget") private var carbsTarget: Double = 0
    @AppStorage("sofra.fatTarget") private var fatTarget: Double = 0

    @State private var store = StoreKitManager.shared
    @State private var subscriptions = FreeScanCounter.shared
    @State private var showPaywall = false
    @State private var isRestoring = false

    /// The numeric keypad has no system "done" key — this drives a keyboard
    /// toolbar with a dismiss button (see `.toolbar { ... .keyboard }` below).
    private enum TargetField: Hashable {
        case calorie, protein, carbs, fat
    }
    @FocusState private var focusedTargetField: TargetField?

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            Form {
                proSection
                targetsSection
                profileSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.bgPage.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Ayarlar")
            .onAppear { seedTargetsIfNeeded() }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Bitti") { focusedTargetField = nil }
                        .fontWeight(.semibold)
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(onComplete: { showPaywall = false },
                        skipTitle: "Kapat")
        }
        .tint(Color.accentFill)
    }

    // MARK: Pro

    @ViewBuilder
    private var proSection: some View {
        Section {
            if subscriptions.isSubscribed {
                HStack {
                    Label("Sofra Pro", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Color.accentFill)
                    Spacer()
                    Text("Aktif")
                        .font(.sofraCaption)
                        .foregroundStyle(Color.textSecondary)
                }
                Button("Aboneliği Yönet") { store.openManageSubscriptions() }
            } else {
                Button {
                    showPaywall = true
                } label: {
                    HStack {
                        Label {
                            Text("Sofra Pro'ya Geç")
                                .foregroundStyle(Color.textPrimary)
                        } icon: {
                            SofraIconView(icon: .sofra, size: 16)
                                .foregroundStyle(Color.accentFill)
                        }
                        Spacer()
                        Text("\(subscriptions.remainingFreeScans) tarama kaldı")
                            .font(.sofraCaption)
                            .foregroundStyle(Color.textMuted)
                    }
                }
            }

            Button {
                Task { await restore() }
            } label: {
                HStack {
                    Text("Satın Alımları Geri Yükle")
                    if isRestoring {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isRestoring)
        } header: {
            Text("Abonelik")
        }
    }

    // MARK: Targets

    private var targetsSection: some View {
        Section {
            targetRow(title: "Günlük kalori", value: $calorieTarget, unit: "kcal", step: 50, field: .calorie)
            targetRow(title: "Protein", value: $proteinTarget, unit: "g", step: 5, field: .protein)
            targetRow(title: "Karbonhidrat", value: $carbsTarget, unit: "g", step: 5, field: .carbs)
            targetRow(title: "Yağ", value: $fatTarget, unit: "g", step: 1, field: .fat)

            Button("Kaloriden makro dağıt (P25 · K45 · Y30)") {
                distributeMacros()
            }
            .font(.sofraCaption)
        } header: {
            Text("Günlük Hedefler")
        } footer: {
            Text("Değişiklikler Bugün ekranındaki halkaya ve makro kartlarına anında yansır.")
        }
    }

    private func targetRow(title: String, value: Binding<Double>, unit: String, step: Double, field: TargetField) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0)))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 92)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .font(.sofraNumericSmall)
                .focused($focusedTargetField, equals: field)
            Text(unit)
                .font(.sofraCaption)
                .foregroundStyle(Color.textMuted)
            Stepper("", value: value, in: 0...10000, step: step)
                .labelsHidden()
        }
    }

    // MARK: Profile

    @ViewBuilder
    private var profileSection: some View {
        Section {
            if let profile {
                Picker("Hedef", selection: Binding(
                    get: { profile.goal },
                    set: { profile.goal = $0; save() }
                )) {
                    ForEach(Goal.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }

                Picker("Aktivite", selection: Binding(
                    get: { profile.activityLevel },
                    set: { profile.activityLevel = $0; save() }
                )) {
                    ForEach(ActivityLevel.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }

                Stepper(value: Binding(
                    get: { profile.heightCm },
                    set: { profile.heightCm = $0; save() }
                ), in: 100...250, step: 1) {
                    HStack {
                        Text("Boy")
                        Spacer()
                        Text("\(Int(profile.heightCm)) cm")
                            .font(.sofraNumericSmall)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                Stepper(value: Binding(
                    get: { profile.weightKg },
                    set: { profile.weightKg = $0; save() }
                ), in: 30...300, step: 0.5) {
                    HStack {
                        Text("Kilo")
                        Spacer()
                        Text("\(profile.weightKg, specifier: "%.1f") kg")
                            .font(.sofraNumericSmall)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            } else {
                Text("Profil bulunamadı.")
                    .foregroundStyle(Color.textMuted)
            }
        } header: {
            Text("Profil")
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Sürüm")
                Spacer()
                Text(appVersion)
                    .font(.sofraCaption)
                    .foregroundStyle(Color.textMuted)
            }
        } header: {
            Text("Hakkında")
        }
    }

    // MARK: Logic

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(v) (\(b))"
    }

    /// Seed macro targets from the saved profile on first open (they default to 0).
    private func seedTargetsIfNeeded() {
        // Rounded defensively: profiles saved before OnboardingModel started
        // rounding its targets may still carry long decimal tails.
        if calorieTarget <= 0, let p = profile, p.dailyCalorieTarget > 0 {
            calorieTarget = p.dailyCalorieTarget.rounded()
        }
        if proteinTarget <= 0, carbsTarget <= 0, fatTarget <= 0 {
            if let p = profile, p.proteinTargetG > 0 {
                proteinTarget = p.proteinTargetG.rounded()
                carbsTarget = p.carbsTargetG.rounded()
                fatTarget = p.fatTargetG.rounded()
            } else {
                distributeMacros()
            }
        }
    }

    private func distributeMacros() {
        proteinTarget = (calorieTarget * 0.25 / 4).rounded()
        carbsTarget   = (calorieTarget * 0.45 / 4).rounded()
        fatTarget     = (calorieTarget * 0.30 / 9).rounded()
    }

    private func save() {
        try? modelContext.save()
    }

    private func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        _ = await store.restorePurchases()
    }
}
