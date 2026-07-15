import SwiftUI

struct WeightTrendView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var rawPoints: [HealthKitWeightPoint] = []
    /// Most recent measurement of any age — shown when the 30-day window is
    /// empty but Health still holds older weigh-ins.
    @State private var latestKnownWeight: HealthKitWeightPoint?
    @State private var isLoaded = false

    private var points: [HealthKitWeightPoint] {
        HealthKitWeightTrendBuilder.dailyLatest(from: rawPoints)
    }

    private var latest: HealthKitWeightPoint? { points.last }
    private var first: HealthKitWeightPoint? { points.first }

    var body: some View {
        ZStack {
            Color.bgPage.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Layout.Spacing.lg) {
                    if !isLoaded {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, Layout.Spacing.xxl)
                    } else if !points.isEmpty {
                        summaryCard
                        chartCard
                        readingNote
                    } else if let latestKnownWeight {
                        staleWeightCard(latestKnownWeight)
                        readingNote
                    } else {
                        emptyState
                    }

                    Spacer(minLength: Layout.Spacing.xxl)
                }
                .padding(.horizontal, Layout.Spacing.lg)
                .padding(.top, Layout.Spacing.md)
            }
        }
        .navigationTitle("Kilo trendi")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Ask for Health access on entering the screen. If the user reached
            // here without granting weight-read (or granted it only partially in
            // the Settings connect flow), this is where it's actually needed.
            // No-op once authorization has been determined.
            await HealthKitManager.shared.requestAuthorization()
            await loadWeightHistory()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await loadWeightHistory() }
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.md) {
            Text("SON KİLO")
                .font(.calpEyebrow)
                .tracking(1.2)
                .foregroundStyle(Color.textMuted)

            HStack(alignment: .firstTextBaseline) {
                Text("\(latest?.kilograms ?? 0, specifier: "%.1f") kg")
                    .font(.calpDisplayNumeric)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                if let change = weightChange {
                    Text(change)
                        .font(.calpNumericSmall)
                        .foregroundStyle(change.hasPrefix("+") ? Color.textMuted : Color.accentText)
                }
            }

            if let date = latest?.date {
                Text("Son ölçüm: \(Self.dateFormatter.string(from: date))")
                    .font(.calpCaption)
                    .foregroundStyle(Color.textMuted)
            }
        }
        .padding(Layout.Spacing.lg)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
        .raisedSurface(cornerRadius: Layout.Radius.card)
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.md) {
            Text("SON 30 GÜN")
                .font(.calpEyebrow)
                .tracking(1.2)
                .foregroundStyle(Color.textMuted)

            WeightLineChart(points: points)
                .frame(height: 190)

            HStack {
                if let minimum = points.map(\.kilograms).min() {
                    Text("En düşük \(minimum, specifier: "%.1f") kg")
                }
                Spacer()
                if let maximum = points.map(\.kilograms).max() {
                    Text("En yüksek \(maximum, specifier: "%.1f") kg")
                }
            }
            .font(.calpCaption)
            .foregroundStyle(Color.textMuted)
        }
        .padding(Layout.Spacing.lg)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
        .raisedSurface(cornerRadius: Layout.Radius.card)
    }

    private var readingNote: some View {
        Label(
            "Kilo ölçümleri Sağlık uygulamasından okunur ve cihazda kalır.",
            systemImage: "lock.shield"
        )
        .font(.calpCaption)
        .foregroundStyle(Color.textMuted)
        .padding(.horizontal, Layout.Spacing.sm)
    }

    /// Shown when there is no measurement in the last 30 days but Health still
    /// holds an older weigh-in — a connected account simply hasn't logged weight
    /// recently. Avoids the misleading "connect Health" empty state.
    private func staleWeightCard(_ point: HealthKitWeightPoint) -> some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.md) {
            Text("SON KİLO")
                .font(.calpEyebrow)
                .tracking(1.2)
                .foregroundStyle(Color.textMuted)

            Text("\(point.kilograms, specifier: "%.1f") kg")
                .font(.calpDisplayNumeric)
                .foregroundStyle(Color.textPrimary)

            Text("Son ölçüm: \(Self.dateFormatter.string(from: point.date))")
                .font(.calpCaption)
                .foregroundStyle(Color.textMuted)

            Text("Son 30 günde yeni ölçüm yok. Sağlık uygulamasına kilo ekledikçe trend burada oluşur.")
                .font(.calpCaption)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(Layout.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
        .raisedSurface(cornerRadius: Layout.Radius.card)
    }

    private var emptyState: some View {
        VStack(spacing: Layout.Spacing.md) {
            Image(systemName: "scalemass")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(Color.textMuted)
            Text("Kilo verisi görünmüyor")
                .font(.calpBody)
                .foregroundStyle(Color.textSecondary)
            Text("Sağlık uygulamasında kilo ölçümü yoksa ya da Calp’e kilo okuma izni verilmediyse burası boş kalır.")
                .font(.calpCaption)
                .foregroundStyle(Color.textMuted)
                .multilineTextAlignment(.center)

            Button {
                Task {
                    await HealthKitManager.shared.requestAuthorization()
                    await loadWeightHistory()
                }
            } label: {
                Text("Sağlık erişimini aç")
                    .font(.calpLabel)
                    .foregroundStyle(Color.onAccent)
                    .padding(.horizontal, Layout.Spacing.lg)
                    .padding(.vertical, Layout.Spacing.md)
                    .background(Color.accentFill, in: RoundedRectangle(cornerRadius: Layout.Radius.control))
            }
            .padding(.top, Layout.Spacing.xs)

            Text("Zaten bağladıysan: Sağlık uygulaması › Profil › Uygulamalar › Calp’ten “Kilo” okumasına izin ver.")
                .font(.system(size: 11))
                .foregroundStyle(Color.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Layout.Spacing.xl)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
    }

    private var weightChange: String? {
        guard let first, let latest else { return nil }
        let delta = latest.kilograms - first.kilograms
        guard abs(delta) >= 0.05 else { return "Değişim yok" }
        return String(format: "%+.1f kg", delta)
    }

    @MainActor
    private func loadWeightHistory() async {
        let loadedPoints = await HealthKitManager.shared.readWeightHistory()
        guard !Task.isCancelled else { return }
        rawPoints = loadedPoints
        // Only pay for the fallback query when the 30-day window came back empty.
        latestKnownWeight = loadedPoints.isEmpty
            ? await HealthKitManager.shared.latestWeight()
            : nil
        guard !Task.isCancelled else { return }
        isLoaded = true
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("d MMMM")
        return formatter
    }()
}

private struct WeightLineChart: View {
    let points: [HealthKitWeightPoint]

    var body: some View {
        GeometryReader { geometry in
            let minimum = points.map(\.kilograms).min() ?? 0
            let maximum = points.map(\.kilograms).max() ?? 1
            let range = max(maximum - minimum, 0.5)
            let horizontalInset: CGFloat = 8
            let verticalInset: CGFloat = 12
            let width = max(geometry.size.width - horizontalInset * 2, 1)
            let height = max(geometry.size.height - verticalInset * 2, 1)

            ZStack {
                VStack(spacing: 0) {
                    Divider().overlay(Color.borderHairline)
                    Spacer()
                    Divider().overlay(Color.borderHairline)
                    Spacer()
                    Divider().overlay(Color.borderHairline)
                }

                Path { path in
                    for (index, point) in points.enumerated() {
                        let x = horizontalInset + width * CGFloat(index) / CGFloat(max(points.count - 1, 1))
                        let y = verticalInset + height * CGFloat((maximum - point.kilograms) / range)
                        let coordinate = CGPoint(x: x, y: y)
                        if index == 0 {
                            path.move(to: coordinate)
                        } else {
                            path.addLine(to: coordinate)
                        }
                    }
                }
                .stroke(Color.accentFill, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                    let x = horizontalInset + width * CGFloat(index) / CGFloat(max(points.count - 1, 1))
                    let y = verticalInset + height * CGFloat((maximum - point.kilograms) / range)
                    Circle()
                        .fill(Color.surfaceRaised)
                        .overlay(Circle().stroke(Color.accentFill, lineWidth: 2))
                        .frame(width: 9, height: 9)
                        .position(x: x, y: y)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kilo trend grafiği")
    }
}
