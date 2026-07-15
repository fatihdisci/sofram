//
//  ContentView.swift
//  Calp — root: onboarding → tabbed home + scan-flow cover.
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
//  be split into Calp/Views/Settings/ once the project is regenerated.
//

import SwiftUI
import SwiftData
import UIKit
import WidgetKit

enum UserDataDeletion {
    static func deleteModels(in modelContext: ModelContext) throws {
        try modelContext.delete(model: LoggedItem.self)
        try modelContext.delete(model: ScanEntry.self)
        try modelContext.delete(model: QuickAddCount.self)
        try modelContext.delete(model: QuickAddItem.self)
        try modelContext.delete(model: DailyQuickCounter.self)
        try modelContext.delete(model: UserProfile.self)
        try modelContext.save()
    }
}

struct ContentView: View {
    @Environment(NavigationModel.self) private var nav

    @AppStorage("calp.onboardingCompleted") private var onboardingCompleted = false

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
            //  calp://daily → Bugün tab, calp://camera → capture,
            //  calp://textlog → text logging.
            guard url.scheme == "calp" else { return }
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
                .tabItem {
                    tabItemLabel("Bugün", icon: .bugun)
                }
                .tag(AppTab.today)
                .transition(.opacity)

            HistoryView()
                .tabItem {
                    tabItemLabel("Geçmiş", icon: .gecmis)
                }
                .tag(AppTab.history)
                .transition(.opacity)

            SettingsView()
                .tabItem {
                    tabItemLabel("Ayarlar", icon: .ayarlar)
                }
                .tag(AppTab.settings)
                .transition(.opacity)
        }
        .tint(Color.accentFill)
        .animation(.calpSpring, value: nav.selectedTab)
        .fullScreenCover(isPresented: Binding(
            get: { nav.scanFlow != nil },
            set: { if !$0 { nav.scanFlow = nil } }
        )) {
            ScanFlowContainer()
                .environment(nav)
        }
    }

    @MainActor
    private func tabItemLabel(_ title: String, icon: CalpIcon) -> some View {
        Label {
            Text(title)
        } icon: {
            tabBarImage(for: icon)
        }
    }

    /// UIKit-backed tab bars extract only `Image` and `Text` from a `tabItem`.
    /// Render the custom Calp shape into a template image so the native tab bar
    /// can display it and apply its selected/unselected tint normally.
    @MainActor
    private func tabBarImage(for icon: CalpIcon) -> Image {
        let renderer = ImageRenderer(
            content: CalpIconView(icon: icon, size: 24)
                .foregroundStyle(Color.black)
        )
        renderer.scale = 3

        guard let image = renderer.uiImage else {
            return Image(uiImage: UIImage())
        }
        return Image(uiImage: image.withRenderingMode(.alwaysTemplate))
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
                if FreeScanCounter.shared.canScan(for: .photo) {
                    CameraView()
                } else {
                    FreeScanLimitView(pool: .photo)
                }

            case .analyzing(let imageData, let uiImage):
                AnalysisOverlay(imageData: imageData, uiImage: uiImage)

            case .result(let uiImage, let items, let source, let rawJSON):
                ResultView(uiImage: uiImage, items: items, source: source, rawJSON: rawJSON)

            case .textLog:
                if FreeScanCounter.shared.canScan(for: .text) {
                    TextLogView()
                } else {
                    FreeScanLimitView(pool: .text)
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
    let pool: FreeScanPool

    init(pool: FreeScanPool) {
        self.pool = pool
    }

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
                    .accessibilityLabel(String(localized: "Kapat"))
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
                    CalpIconView(icon: .calp, size: 56)
                        .foregroundStyle(Color.accentFill)
                        .accessibilityHidden(true)
                }

                Text(pool == .photo ? "Bugünkü fotoğraf hakkın doldu" : "Bugünkü metin ve ses hakkın doldu")
                    .font(.calpTitle)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)

                Text(limitMessage)
                    .font(.calpBody)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)

                Button {
                    showPaywall = true
                } label: {
                    Text("Pro'yu İncele")
                        .font(.calpLabel)
                        .foregroundStyle(Color.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Layout.Spacing.md)
                        .background(Color.accentFill, in: RoundedRectangle(cornerRadius: Layout.Radius.control))
                }
                .padding(.horizontal, Layout.Spacing.xl)
                .padding(.top, Layout.Spacing.sm)

                Button("Manuel ekle") {
                    nav.goToDaily()
                }
                .font(.calpLabel)
                .foregroundStyle(Color.accentText)

                if pool == .text && counter.canScan(for: .photo) {
                    Button("Fotoğrafla devam et") {
                        nav.goToCamera()
                    }
                    .font(.calpLabel)
                    .foregroundStyle(Color.textSecondary)
                }

                Spacer()
                Spacer()
            }
            .padding(Layout.Spacing.lg)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(onComplete: { showPaywall = false },
                        skipTitle: "Şimdilik kapat")
                .presentationCornerRadius(24)
                .presentationBackground(Color.bgPage)
                .presentationDragIndicator(.visible)
        }
    }

    private var limitMessage: String {
        if pool == .photo {
            return "Günlük fotoğraf analiz hakkın doldu. Yarın yenilenir. Öğününü elle ekleyebilirsin — bu her zaman ücretsizdir."
        }
        return "Günlük metin ve ses analiz hakkın doldu. Yarın yenilenir. Öğününü elle ekleyebilirsin — bu her zaman ücretsizdir."
    }

}

// MARK: - Settings tab

/// Ayarlar: editable profile, daily targets, subscription, and about.
/// Targets are stored in AppStorage (the same keys DailyView reads), so edits
/// here immediately drive the daily ring and macro cards.
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query private var profiles: [UserProfile]
    @Query(sort: \ScanEntry.timestamp) private var exportScanEntries: [ScanEntry]

    @AppStorage("calp.dailyCalorieTarget") private var calorieTarget: Double = 2000
    @AppStorage("calp.proteinTarget") private var proteinTarget: Double = 0
    @AppStorage("calp.carbsTarget") private var carbsTarget: Double = 0
    @AppStorage("calp.fatTarget") private var fatTarget: Double = 0
    @AppStorage("calp.onboardingCompleted") private var onboardingCompleted = false

    // Notifications (SF-EX06/07/08) — reactive mirrors of the UserDefaults keys
    // MealReminderService reads. Toggling any of these re-arms the schedule.
    @AppStorage(NotificationPrefs.masterKey) private var notifMaster = false
    @AppStorage(MealSlot.breakfast.enabledKey) private var notifBreakfast = false
    @AppStorage(MealSlot.lunch.enabledKey) private var notifLunch = false
    @AppStorage(MealSlot.snack.enabledKey) private var notifSnack = false
    @AppStorage(MealSlot.dinner.enabledKey) private var notifDinner = false
    @AppStorage(NotificationPrefs.noLogEnabledKey) private var notifNoLog = false
    @AppStorage(NotificationPrefs.summaryEnabledKey) private var notifSummary = false
    @State private var notifAuthorizationDenied = false

    @State private var store = StoreKitManager.shared
    @State private var subscriptions = FreeScanCounter.shared
    @State private var showPaywall = false
    @State private var isRestoring = false
    @State private var showTargetRecomputeConfirmation = false
    @State private var showDeleteAllDataConfirmation = false
    @State private var dataDeletionError: String?
    @State private var exportedFile: ExportedFile?
    @State private var exportError: String?
    @State private var showFeedbackUnavailableAlert = false
    @State private var healthKitPermissionMessage: String?

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
                #if DEBUG
                developerSection
                #endif
                targetsSection
                profileSection
                healthKitSection
                languageSection
                notificationsSection
                dataSection
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
        .sheet(item: $exportedFile) { file in
            ActivityView(activityItems: [file.url])
        }
        .confirmationDialog(
            "Profil değişti. Günlük hedefler yeniden hesaplansın mı?",
            isPresented: $showTargetRecomputeConfirmation,
            titleVisibility: .visible
        ) {
            Button("Evet") {
                guard let profile else { return }
                recomputeAndSyncTargets(for: profile)
            }
            Button("Hayır", role: .cancel) {}
        }
        .confirmationDialog(
            "Tüm verilerimi silmek istiyor musun?",
            isPresented: $showDeleteAllDataConfirmation,
            titleVisibility: .visible
        ) {
            Button("Tüm Verilerimi Sil", role: .destructive) {
                deleteAllData()
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Tüm öğünler, sayaçlar ve profil kalıcı olarak silinir. iCloud kopyası da dahil. Bu geri alınamaz.")
        }
        .alert("Veriler silinemedi", isPresented: Binding(
            get: { dataDeletionError != nil },
            set: { if !$0 { dataDeletionError = nil } }
        )) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(dataDeletionError ?? "Bilinmeyen bir hata oluştu.")
        }
        .alert("Veriler dışa aktarılamadı", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(exportError ?? "Bilinmeyen bir hata oluştu.")
        }
        .alert("E-posta uygulaması açılamadı", isPresented: $showFeedbackUnavailableAlert) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text("Geri bildiriminizi av.fatihdisci@gmail.com adresine gönderebilirsiniz.")
        }
        .tint(Color.accentFill)
    }

    // MARK: Pro

    @ViewBuilder
    private var proSection: some View {
        Section {
            if subscriptions.isProUnlocked {
                HStack {
                    Label("Calp Pro", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentFill)
                    Spacer()
                    Text("Aktif")
                        .font(.calpCaption)
                        .foregroundStyle(Color.textSecondary)
                }
                Button("Aboneliği Yönet") { store.openManageSubscriptions() }
            } else {
                Button {
                    showPaywall = true
                } label: {
                    HStack {
                        Label {
                            Text("Calp Pro'ya Geç")
                                .foregroundStyle(Color.textPrimary)
                        } icon: {
                            CalpIconView(icon: .calp, size: 16)
                                .foregroundStyle(Color.accentFill)
                        }
                        Spacer()
                        Text(String(localized: "Fotoğraf \(subscriptions.remainingPhotoScans) · metin/ses \(subscriptions.remainingTextScans) kaldı"))
                            .font(.calpCaption)
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

    // MARK: Developer (DEBUG only)

    #if DEBUG
    /// Runtime Pro / Ücretsiz switch so Pro-gated surfaces (weekly AI report,
    /// scan badge, paywall) can be exercised without a sandbox subscription.
    /// Flips `FreeScanCounter.debugForcePro`, which drives `isProUnlocked`
    /// everywhere. Compiled out of release builds entirely.
    private var developerSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { subscriptions.debugForcePro },
                set: { subscriptions.debugForcePro = $0 }
            )) {
                Label(
                    subscriptions.debugForcePro ? "Pro (tüm özellikler açık)" : "Ücretsiz",
                    systemImage: subscriptions.debugForcePro ? "crown.fill" : "lock.fill"
                )
            }

            Text(subscriptions.debugForcePro
                 ? "Tüm Pro özellikleri açık — haftalık AI raporu dahil. Gerçek abonelik gerekmez."
                 : "Ücretsiz kullanıcı deneyimi: Pro yüzeyleri kilitli, paywall görünür.")
                .font(.calpCaption)
                .foregroundStyle(Color.textMuted)
        } header: {
            Text("Geliştirici")
        } footer: {
            Text("Yalnızca DEBUG derlemelerinde görünür.")
        }
    }
    #endif

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
            .font(.calpCaption)
        } header: {
            Text("Günlük Hedefler")
        } footer: {
            VStack(alignment: .leading, spacing: Layout.Spacing.sm) {
                Text("Değişiklikler Bugün ekranındaki halkaya ve makro kartlarına anında yansır.")
                // Medical disclaimer (Phase A4) — required wherever a computed
                // calorie target is rendered.
                Text(NutritionConstants.medicalDisclaimer)
                    .foregroundStyle(Color.textMuted)
            }
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
                .font(.calpNumericSmall)
                .focused($focusedTargetField, equals: field)
            Text(unit)
                .font(.calpCaption)
                .foregroundStyle(Color.textMuted)
            Stepper("", value: value, in: 0...10000, step: step)
                .labelsHidden()
                .accessibilityLabel(title)
        }
    }

    // MARK: Profile

    @ViewBuilder
    private var profileSection: some View {
        Section {
            if let profile {
                Picker("Hedef", selection: Binding(
                    get: { profile.goal },
                    set: { newValue in
                        updateProfile(profile) { $0.goal = newValue }
                    }
                )) {
                    ForEach(Goal.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }

                Picker("Aktivite", selection: Binding(
                    get: { profile.activityLevel },
                    set: { newValue in
                        updateProfile(profile) { $0.activityLevel = newValue }
                    }
                )) {
                    ForEach(ActivityLevel.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }

                Stepper(value: Binding(
                    get: { profile.heightCm },
                    set: { newValue in
                        updateProfile(profile) { $0.heightCm = newValue }
                    }
                ), in: 100...250, step: 1) {
                    HStack {
                        Text("Boy")
                        Spacer()
                        Text("\(Int(profile.heightCm)) cm")
                            .font(.calpNumericSmall)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                Stepper(value: Binding(
                    get: { profile.weightKg },
                    set: { newValue in
                        updateProfile(profile) { $0.weightKg = newValue }
                    }
                ), in: 30...300, step: 0.5) {
                    HStack {
                        Text("Kilo")
                        Spacer()
                        Text("\(profile.weightKg, specifier: "%.1f") kg")
                            .font(.calpNumericSmall)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                Stepper(value: Binding(
                    get: { max(profile.age, 10) },
                    set: { newValue in
                        updateProfile(profile) { $0.age = newValue }
                    }
                ), in: 10...100, step: 1) {
                    HStack {
                        Text("Yaş")
                        Spacer()
                        Text(profile.age > 0 ? "\(profile.age)" : "Belirtilmedi")
                            .font(.calpNumericSmall)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                Picker("Biyolojik cinsiyet", selection: Binding(
                    get: { profile.biologicalSex },
                    set: { newValue in
                        updateProfile(profile) { $0.biologicalSex = newValue }
                    }
                )) {
                    ForEach(BiologicalSex.allCases, id: \.self) {
                        Text($0.displayName).tag($0)
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

    // MARK: Language

    @State private var selectedLanguage: AppLanguage = .current

    private var languageSection: some View {
        Section {
            Picker(selection: $selectedLanguage) {
                ForEach(AppLanguage.allCases, id: \.self) { lang in
                    Text(lang.displayName).tag(lang)
                }
            } label: {
                Label(String(localized: "Dil"), systemImage: "globe")
            }
            .onChange(of: selectedLanguage) { _, newValue in
                AppLanguage.current = newValue
            }
        } header: {
            Text("Dil")
        } footer: {
            Text("Değişiklik bir sonraki açılışta uygulanır.")
        }
    }

    // MARK: HealthKit (SF-1501)

    private var healthKitSection: some View {
        Section {
            Button {
                Task { @MainActor in
                    let granted = await HealthKitManager.shared.requestAuthorization()
                    healthKitPermissionMessage = granted
                        ? String(localized: "Sağlık verisi erişimi güncellendi.")
                        : String(localized: "Sağlık verisi izni verilmedi. Uygulama normal şekilde çalışmaya devam eder.")
                }
            } label: {
                Label(String(localized: "Sağlık verilerini bağla"), systemImage: "heart.text.square")
            }

            Text(String(localized: "Calp kilo, boy, aktif enerji ve adım verilerini yalnızca cihazda kullanır; AI servisine göndermez."))
                .font(.calpCaption)
                .foregroundStyle(Color.textMuted)

            if let healthKitPermissionMessage {
                Text(healthKitPermissionMessage)
                    .font(.calpCaption)
                    .foregroundStyle(Color.textSecondary)
            }
        } header: {
            Text("Sağlık")
        }
    }

    // MARK: Notifications (SF-EX06/07/08)

    @ViewBuilder
    private var notificationsSection: some View {
        Section {
            Toggle(isOn: $notifMaster) {
                Label(String(localized: "Bildirimler"), systemImage: "bell.badge")
            }
            .onChange(of: notifMaster) { _, isOn in
                if isOn { requestNotificationAuthorization() }
                rescheduleNotifications()
            }

            if notifMaster {
                if notifAuthorizationDenied {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label(String(localized: "Bildirim izni kapalı — Ayarlar'dan aç"), systemImage: "exclamationmark.circle")
                            .foregroundStyle(Color.accentText)
                    }
                }

                // Meal reminders (SF-EX06)
                mealReminderRow(.breakfast, isOn: $notifBreakfast)
                mealReminderRow(.lunch, isOn: $notifLunch)
                mealReminderRow(.snack, isOn: $notifSnack)
                mealReminderRow(.dinner, isOn: $notifDinner)

                // No-log reminder (SF-EX07)
                Toggle(String(localized: "Hiç kayıt yoksa akşam hatırlat"), isOn: $notifNoLog)
                    .onChange(of: notifNoLog) { _, _ in rescheduleNotifications() }
                if notifNoLog {
                    DatePicker(
                        String(localized: "Saat"),
                        selection: notifTime(
                            hourKey: NotificationPrefs.noLogHourKey,
                            minuteKey: NotificationPrefs.noLogMinuteKey,
                            defaultHour: NotificationPrefs.defaultNoLogHour
                        ),
                        displayedComponents: .hourAndMinute
                    )
                }

                // Nightly summary (SF-EX08)
                Toggle(String(localized: "Gece özeti"), isOn: $notifSummary)
                    .onChange(of: notifSummary) { _, _ in rescheduleNotifications() }
                if notifSummary {
                    DatePicker(
                        String(localized: "Saat"),
                        selection: notifTime(
                            hourKey: NotificationPrefs.summaryHourKey,
                            minuteKey: NotificationPrefs.summaryMinuteKey,
                            defaultHour: NotificationPrefs.defaultSummaryHour
                        ),
                        displayedComponents: .hourAndMinute
                    )
                }

                Button(role: .destructive) {
                    turnOffAllNotifications()
                } label: {
                    Text("Tüm bildirimleri kapat")
                }
            }
        } header: {
            Text("Bildirimler")
        } footer: {
            Text("Hepsi isteğe bağlı ve kapalı gelir. Bir öğün kaydedildiğinde o öğünün hatırlatması iptal olur; gece özeti yalnızca bilgi verir.")
        }
    }

    private func mealReminderRow(_ slot: MealSlot, isOn: Binding<Bool>) -> some View {
        Group {
            Toggle(slot.displayName, isOn: isOn)
                .onChange(of: isOn.wrappedValue) { _, _ in rescheduleNotifications() }
            if isOn.wrappedValue {
                DatePicker(
                    String(localized: "Saat"),
                    selection: notifTime(
                        hourKey: slot.hourKey,
                        minuteKey: slot.minuteKey,
                        defaultHour: slot.defaultHour
                    ),
                    displayedComponents: .hourAndMinute
                )
            }
        }
    }

    /// A DatePicker binding that stores the chosen hour/minute in UserDefaults
    /// and re-arms the schedule.
    private func notifTime(hourKey: String, minuteKey: String, defaultHour: Int) -> Binding<Date> {
        Binding(
            get: {
                let h = UserDefaults.standard.object(forKey: hourKey) as? Int ?? defaultHour
                let m = UserDefaults.standard.object(forKey: minuteKey) as? Int ?? 0
                return Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                UserDefaults.standard.set(comps.hour ?? defaultHour, forKey: hourKey)
                UserDefaults.standard.set(comps.minute ?? 0, forKey: minuteKey)
                rescheduleNotifications()
            }
        )
    }

    private func requestNotificationAuthorization() {
        Task { @MainActor in
            let granted = await MealReminderService.shared.requestAuthorization()
            notifAuthorizationDenied = !granted
            rescheduleNotifications()
        }
    }

    private func rescheduleNotifications() {
        MealReminderService.shared.reschedule(modelContext: modelContext)
    }

    private func turnOffAllNotifications() {
        notifMaster = false
        notifBreakfast = false
        notifLunch = false
        notifSnack = false
        notifDinner = false
        notifNoLog = false
        notifSummary = false
        rescheduleNotifications()
    }

    // MARK: Data

    private var dataSection: some View {
        Section {
            Button {
                exportData()
            } label: {
                Label("Verilerimi Dışa Aktar", systemImage: "square.and.arrow.up")
            }

            Button("Tüm Verilerimi Sil", role: .destructive) {
                showDeleteAllDataConfirmation = true
            }
        } header: {
            Text("Veri")
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section {
            Button {
                sendFeedback()
            } label: {
                Label("Geri Bildirim Gönder", systemImage: "envelope")
            }

            Link(destination: LegalLinks.privacyPolicy) {
                Label("Gizlilik Politikası", systemImage: "hand.raised")
            }

            Link(destination: LegalLinks.termsOfUse) {
                Label("Kullanım Koşulları", systemImage: "doc.text")
            }

            HStack {
                Text("Sürüm")
                Spacer()
                Text(appVersion)
                    .font(.calpCaption)
                    .foregroundStyle(Color.textMuted)
            }
        } header: {
            Text("Hakkında")
        }
    }

    // MARK: Logic

    private var appVersion: String {
        let v = appShortVersion
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(v) (\(b))"
    }

    private var appShortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
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

    private func updateProfile(
        _ profile: UserProfile,
        mutation: (UserProfile) -> Void
    ) {
        let targetsWereCustomized = appTargetsDiffer(from: profile)
        mutation(profile)

        guard profile.age > 0 else {
            save()
            return
        }

        if targetsWereCustomized {
            save()
            showTargetRecomputeConfirmation = true
        } else {
            recomputeAndSyncTargets(for: profile)
        }
    }

    private func appTargetsDiffer(from profile: UserProfile) -> Bool {
        abs(calorieTarget - profile.dailyCalorieTarget) > 0.5
            || abs(proteinTarget - profile.proteinTargetG) > 0.5
            || abs(carbsTarget - profile.carbsTargetG) > 0.5
            || abs(fatTarget - profile.fatTargetG) > 0.5
    }

    private func recomputeAndSyncTargets(for profile: UserProfile) {
        profile.recomputeDailyTarget()
        calorieTarget = profile.dailyCalorieTarget
        proteinTarget = profile.proteinTargetG
        carbsTarget = profile.carbsTargetG
        fatTarget = profile.fatTargetG
        save()
    }

    private func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        _ = await store.restorePurchases()
    }

    private func deleteAllData() {
        do {
            try UserDataDeletion.deleteModels(in: modelContext)

            let defaults = UserDefaults.standard
            [
                "calp.dailyCalorieTarget",
                "calp.proteinTarget",
                "calp.carbsTarget",
                "calp.fatTarget",
                "calp.onboardingCompleted",
            ].forEach(defaults.removeObject(forKey:))

            WidgetDataStore.save(.empty)
            WidgetCenter.shared.reloadAllTimelines()
            onboardingCompleted = false
        } catch {
            modelContext.rollback()
            dataDeletionError = "Lütfen tekrar deneyin. (\(error.localizedDescription))"
        }
    }

    private func exportData() {
        do {
            exportedFile = ExportedFile(
                url: try DataExporter.writeTemporaryCSV(scans: exportScanEntries)
            )
        } catch {
            exportError = "Lütfen tekrar deneyin. (\(error.localizedDescription))"
        }
    }

    private func sendFeedback() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "av.fatihdisci@gmail.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Calp Geri Bildirim v\(appShortVersion)")
        ]

        guard let url = components.url else {
            showFeedbackUnavailableAlert = true
            return
        }
        openURL(url) { accepted in
            if !accepted {
                showFeedbackUnavailableAlert = true
            }
        }
    }
}

private struct ExportedFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
