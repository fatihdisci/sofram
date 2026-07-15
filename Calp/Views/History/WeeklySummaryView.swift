import SwiftData
import SwiftUI

struct WeeklySummaryView: View {
    /// Paywall presentation is owned by the parent (HistoryView) so the sheet
    /// lives on a stable ancestor. Presenting it from here — a subview whose
    /// body re-renders whenever async health data loads — intermittently
    /// dropped the first tap ("birkaç tıklamada bir açılıyordu").
    var onUpgrade: () -> Void = {}

    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \QuickAddItem.sortOrder)
    private var quickItems: [QuickAddItem]

    @Query private var quickCounts: [QuickAddCount]

    @Query(sort: \ScanEntry.timestamp, order: .reverse)
    private var scanEntries: [ScanEntry]

    @AppStorage("calp.dailyCalorieTarget") private var calorieTarget: Double = 2000
    @State private var activeEnergyKcal: Double?
    @State private var weightChangeKg: Double?
    @State private var subscriptions = FreeScanCounter.shared
    @State private var weeklyReport: WeeklyReport?
    @State private var weeklyReportError: AIProxyError?
    @State private var isLoadingWeeklyReport = false
    @State private var reportTask: Task<Void, Never>?

    private var summary: WeeklySummary {
        WeeklySummaryBuilder.build(
            scans: scanEntries,
            items: quickItems,
            counts: quickCounts,
            dailyCalorieTarget: calorieTarget,
            activeEnergyKcal: activeEnergyKcal,
            weightChangeKg: weightChangeKg
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.lg) {
            Text("HAFTALIK ÖZET")
                .font(.calpEyebrow)
                .tracking(1.2)
                .foregroundStyle(Color.textMuted)

            HStack(spacing: Layout.Spacing.sm) {
                WeeklyMetricCell(value: "\(summary.loggedDayCount)", caption: "kayıtlı gün")
                WeeklyMetricCell(value: "\(Int(summary.averageCalories.rounded()))", caption: "ort. kcal / gün")
                WeeklyMetricCell(value: "\(Int(summary.averageProtein.rounded())) g", caption: "ort. protein / gün")
            }

            HStack(spacing: Layout.Spacing.sm) {
                WeeklyMetricCell(
                    value: "\(summary.targetMetDayCount)/\(summary.days.count)",
                    caption: "hedefe uyan gün"
                )
                WeeklyMetricCell(value: "\(summary.nightMealCount)", caption: "gece öğünü")
                WeeklyMetricCell(value: changeLabel, caption: "önceki haftaya")
            }

            chartCard
            highLowCard

            if activeEnergyKcal != nil || weightChangeKg != nil {
                healthCard
            }

            weeklyReportCard

            Text("Bu temel istatistikler cihazında hesaplanır; AI raporu içermez.")
                .font(.calpCaption)
                .foregroundStyle(Color.textMuted)
                .padding(.horizontal, Layout.Spacing.sm)
        }
        .task {
            await loadHealthData()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await loadHealthData() }
            }
        }
        .onDisappear {
            reportTask?.cancel()
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.md) {
            Text("Kalori dağılımı")
                .font(.calpCaption)
                .foregroundStyle(Color.textSecondary)

            WeekBarChart(summaries: summary.days, target: calorieTarget)
                .frame(height: 150)

            HStack(spacing: 4) {
                Rectangle()
                    .fill(Color.textMuted)
                    .frame(width: 14, height: 1)
                Text("hedef · \(Int(calorieTarget)) kcal")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textMuted)
            }
        }
        .padding(Layout.Spacing.lg)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
        .raisedSurface(cornerRadius: Layout.Radius.card)
    }

    private var highLowCard: some View {
        VStack(spacing: 0) {
            weeklyDayRow(title: "En yüksek gün", day: summary.highestCalorieDay)
            Divider().overlay(Color.borderHairline)
            weeklyDayRow(title: "En düşük gün", day: summary.lowestCalorieDay)
        }
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
        .raisedSurface(cornerRadius: Layout.Radius.card)
    }

    private func weeklyDayRow(title: String, day: DaySummary?) -> some View {
        HStack {
            Text(title)
                .font(.calpBody)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            if let day {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(day.calories.rounded())) kcal")
                        .font(.calpNumericSmall)
                        .foregroundStyle(Color.textPrimary)
                    Text(Self.dateFormatter.string(from: day.date))
                        .font(.calpCaption)
                        .foregroundStyle(Color.textMuted)
                }
            } else {
                Text("—")
                    .font(.calpNumericSmall)
                    .foregroundStyle(Color.textMuted)
            }
        }
        .padding(Layout.Spacing.lg)
    }

    private var healthCard: some View {
        HStack(spacing: Layout.Spacing.md) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.accentFill)
                .frame(width: 38, height: 38)
                .background(Color.accentTintBg, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("Sağlık verileri")
                    .font(.calpLabel)
                    .foregroundStyle(Color.textPrimary)
                if let activeEnergyKcal {
                    Text("\(Int(activeEnergyKcal.rounded())) kcal aktif enerji · 7 gün")
                        .font(.calpCaption)
                        .foregroundStyle(Color.textMuted)
                }
            }

            Spacer()

            if let weightChangeKg {
                Text(String(format: "%+.1f kg", weightChangeKg))
                    .font(.calpNumericSmall)
                    .foregroundStyle(Color.textPrimary)
            }
        }
        .padding(Layout.Spacing.lg)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
        .raisedSurface(cornerRadius: Layout.Radius.card)
    }

    private var weeklyReportCard: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("HAFTALIK AI RAPORU")
                        .font(.calpEyebrow)
                        .tracking(1.2)
                        .foregroundStyle(Color.textMuted)
                    Text("Bu haftanın özetini birlikte yorumla")
                        .font(.calpBody)
                        .foregroundStyle(Color.textPrimary)
                }
                Spacer()
                Image(systemName: subscriptions.isProUnlocked ? "sparkles" : "lock.fill")
                    .foregroundStyle(Color.accentFill)
            }

            if subscriptions.isProUnlocked {
                if let weeklyReport {
                    reportContent(weeklyReport)
                } else {
                    Text("Yalnızca cihazında hesaplanan özet metrikler kullanılır; ham öğün ve sağlık verileri gönderilmez.")
                        .font(.calpCaption)
                        .foregroundStyle(Color.textSecondary)
                }

                if let weeklyReportError {
                    Text(weeklyReportError.localizedDescription)
                        .font(.calpCaption)
                        .foregroundStyle(Color.textSecondary)
                }

                Button {
                    requestWeeklyReport(forceRefresh: weeklyReport != nil)
                } label: {
                    HStack {
                        if isLoadingWeeklyReport {
                            ProgressView()
                                .tint(Color.onAccent)
                        }
                        Text(weeklyReport == nil ? "Raporu oluştur" : "Raporu yenile")
                            .font(.calpLabel)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .foregroundStyle(Color.onAccent)
                    .padding(.horizontal, Layout.Spacing.lg)
                    .padding(.vertical, Layout.Spacing.md)
                    .background(Color.accentFill, in: RoundedRectangle(cornerRadius: Layout.Radius.control))
                }
                .disabled(isLoadingWeeklyReport)
            } else {
                Text("Haftalık AI yorumları Pro özelliğidir. Temel istatistikler ücretsiz ve cihazında hesaplanır.")
                    .font(.calpCaption)
                    .foregroundStyle(Color.textSecondary)

                Button("Pro'yu İncele") {
                    onUpgrade()
                }
                .font(.calpLabel)
                .foregroundStyle(Color.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Layout.Spacing.md)
                .background(Color.accentFill, in: RoundedRectangle(cornerRadius: Layout.Radius.control))
            }
        }
        .padding(Layout.Spacing.lg)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
        .raisedSurface(cornerRadius: Layout.Radius.card)
    }

    private func reportContent(_ report: WeeklyReport) -> some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.md) {
            Text(report.headline)
                .font(.calpHeading)
                .foregroundStyle(Color.textPrimary)

            Text(report.summary)
                .font(.calpBody)
                .foregroundStyle(Color.textSecondary)

            if !report.observations.isEmpty {
                VStack(alignment: .leading, spacing: Layout.Spacing.sm) {
                    ForEach(report.observations, id: \.self) { observation in
                        Label(observation, systemImage: "circle.fill")
                            .font(.calpCaption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: Layout.Spacing.sm) {
                Text("Küçük adımlar")
                    .font(.calpLabel)
                    .foregroundStyle(Color.textPrimary)
                ForEach(report.suggestions, id: \.self) { suggestion in
                    Label(suggestion, systemImage: "arrow.turn.down.right")
                        .font(.calpCaption)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            Text("AI tarafından üretildi · tıbbi tavsiye değildir")
                .font(.system(size: 10))
                .foregroundStyle(Color.textMuted)
        }
    }

    private var changeLabel: String {
        guard let change = summary.calorieChangeFromPreviousWeek else { return "—" }
        if abs(change) < 1 { return "değişim yok" }
        return String(format: "%+.0f kcal", change)
    }

    private func requestWeeklyReport(forceRefresh: Bool) {
        reportTask?.cancel()
        weeklyReportError = nil
        isLoadingWeeklyReport = true
        let currentSummary = summary
        reportTask = Task {
            do {
                let report = try await AIProxyClient().weeklyReport(
                    summary: currentSummary,
                    forceRefresh: forceRefresh
                )
                guard !Task.isCancelled else { return }
                weeklyReport = report
            } catch {
                guard !Task.isCancelled else { return }
                weeklyReportError = (error as? AIProxyError) ?? .scanFailed
            }
            isLoadingWeeklyReport = false
        }
    }

    @MainActor
    private func loadHealthData() async {
        async let energy = HealthKitManager.shared.readActiveEnergyTotal()
        async let weights = HealthKitManager.shared.readWeightHistory(days: 7)
        let (loadedEnergy, loadedWeights) = await (energy, weights)
        guard !Task.isCancelled else { return }

        activeEnergyKcal = loadedEnergy
        let points = HealthKitWeightTrendBuilder.dailyLatest(from: loadedWeights)
        if let first = points.first, let last = points.last, points.count > 1 {
            weightChangeKg = last.kilograms - first.kilograms
        } else {
            weightChangeKg = nil
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter
    }()
}

private struct WeeklyMetricCell: View {
    let value: String
    let caption: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.calpNumericSmall)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.system(size: 10))
                .foregroundStyle(Color.textMuted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Layout.Spacing.md)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
        .raisedSurface(cornerRadius: Layout.Radius.card)
    }
}
