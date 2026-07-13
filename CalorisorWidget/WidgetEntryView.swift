//
//  WidgetEntryView.swift
//  CalorisorWidgetExtension — small and medium widget layouts.
//
//  Design follows the flat Calorisor palette, simplified for WidgetKit:
//  - Flat surfaces, no shadows (matches the app's flat design system)
//  - No animations (WidgetKit renders static snapshots)
//  - Solid bgPage background with containerBackground for system compositing
//  - Progress ring with accentFill arc on surfaceFlat track
//

import SwiftUI
import WidgetKit

struct CalorisorWidgetEntryView: View {
    let entry: DailyEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallLayout
        case .systemMedium:
            mediumLayout
        case .accessoryCircular:
            accessoryCircularLayout
        case .accessoryInline:
            accessoryInlineLayout
        default:
            smallLayout
        }
    }

    // MARK: - Lock screen widgets

    private var accessoryCircularLayout: some View {
        ZStack {
            AccessoryWidgetBackground()

            Circle()
                .trim(from: 0, to: CGFloat(entry.summary.progress))
                .stroke(
                    Color.accentFill,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(3)
                .widgetAccentable()

            Text("\(Int(entry.summary.remaining))")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.6)
        }
        .widgetURL(URL(string: "calorisor://daily")!)
    }

    private var accessoryInlineLayout: some View {
        Text("\(formattedRemaining) \(String(localized: "kcal kaldı"))")
            .widgetURL(URL(string: "calorisor://daily")!)
    }

    private var formattedRemaining: String {
        Int(entry.summary.remaining).formatted(
            .number.locale(.autoupdatingCurrent)
        )
    }

    // MARK: - Small Widget (calorie ring + remaining)

    private var smallLayout: some View {
        ZStack {
            Color.bgPage

            VStack(spacing: Layout.Spacing.sm) {
                ringView(ringSize: 110, font: .sofraDisplayNumeric)
                caloriesCaption
            }
            .padding(Layout.Spacing.sm)
        }
        .containerBackground(Color.bgPage, for: .widget)
        .widgetURL(URL(string: "calorisor://daily")!)
    }

    // MARK: - Medium Widget (ring left + macros right)

    private var mediumLayout: some View {
        ZStack {
            Color.bgPage

            HStack(spacing: Layout.Spacing.xl) {
                // Left: calorie ring (smaller)
                VStack(spacing: Layout.Spacing.sm) {
                    ringView(ringSize: 100, font: .system(size: 28, weight: .medium, design: .monospaced))
                    caloriesCaption
                }
                .frame(width: 130)

                // Right: macros + counters
                VStack(alignment: .leading, spacing: Layout.Spacing.sm) {
                    macroRow(label: "Protein", value: entry.summary.protein)
                    macroRow(label: "Karb.", value: entry.summary.carbs)
                    macroRow(label: "Yağ", value: entry.summary.fat)

                    Spacer().frame(height: Layout.Spacing.xs)

                    HStack(spacing: Layout.Spacing.lg) {
                        ForEach(Array(entry.summary.topQuickAdds.prefix(2).enumerated()), id: \.offset) { _, item in
                            counterPill(count: item.count, unit: item.unit)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Layout.Spacing.md)
        }
        .containerBackground(Color.bgPage, for: .widget)
        .widgetURL(URL(string: "calorisor://daily")!)
    }

    // MARK: - Shared components

    /// Calorie progress ring with center remaining text.
    private func ringView(ringSize: CGFloat, font: Font) -> some View {
        let strokeWidth: CGFloat = ringSize * 0.07
        let progress = entry.summary.progress

        return ZStack {
            // Track ring
            Circle()
                .stroke(Color.surfaceFlat, lineWidth: strokeWidth)

            // Progress arc
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(
                    Color.accentFill,
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Center text stack
            VStack(spacing: 1) {
                Text("\(Int(entry.summary.remaining))")
                    .font(font)
                    .foregroundStyle(Color.textPrimary)
                    .minimumScaleFactor(0.6)
                Text("kalan")
                    .font(.sofraCaption)
                    .foregroundStyle(Color.textMuted)
            }
        }
        .frame(width: ringSize, height: ringSize)
    }

    /// Consumed / target kcal caption.
    private var caloriesCaption: some View {
        Text("\(Int(entry.summary.calories)) / \(Int(entry.summary.target)) kcal")
            .font(.sofraNumericSmall)
            .foregroundStyle(Color.textSecondary)
    }

    /// A single macro row: label + value in grams.
    private func macroRow(label: String, value: Double) -> some View {
        HStack(spacing: Layout.Spacing.sm) {
            Circle()
                .fill(macroColor(for: label))
                .frame(width: 8, height: 8)

            Text(label)
                .font(.sofraCaption)
                .foregroundStyle(Color.textMuted)
                .frame(width: 52, alignment: .leading)

            Text("\(Int(value))g")
                .font(.sofraNumericSmall)
                .foregroundStyle(Color.textPrimary)
        }
    }

    /// Color coding for macro rows — same warm hues DailyView uses.
    private func macroColor(for label: String) -> Color {
        switch label {
        case "Protein": return .macroProtein
        case "Karb.":   return .macroCarb
        default:        return .macroFat
        }
    }

    private func counterPill(count: Int, unit: String) -> some View {
        Text("\(count) × \(unit)")
            .font(.sofraCaption)
            .foregroundStyle(Color.textSecondary)
    }
}

// MARK: - Layout constants (mirroring main app's Layout.Spacing for widget use)

private enum Layout {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }
}
