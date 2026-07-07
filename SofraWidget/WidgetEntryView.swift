//
//  WidgetEntryView.swift
//  SofraWidgetExtension — small and medium widget layouts.
//
//  Design follows the "Yumuşak Sofra" palette but simplified for WidgetKit:
//  - No neomorphic dual-tone shadows (WidgetKit doesn't support complex shadows well)
//  - No animations (WidgetKit renders static snapshots)
//  - Solid bgPage background with containerBackground for system compositing
//  - Progress ring with accentFill arc on surfaceFlat track
//

import SwiftUI
import WidgetKit

struct SofraWidgetEntryView: View {
    let entry: DailyEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallLayout
        case .systemMedium:
            mediumLayout
        default:
            smallLayout
        }
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
        .widgetURL(URL(string: "sofra://daily")!)
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
                    macroRow(label: "Carbs", value: entry.summary.carbs)
                    macroRow(label: "Yağ", value: entry.summary.fat)

                    Spacer().frame(height: Layout.Spacing.xs)

                    // Bread & tea quick counters
                    HStack(spacing: Layout.Spacing.lg) {
                        counterPill(icon: "🍞", count: entry.summary.breadSlices, unit: "dilim")
                        counterPill(icon: "🍵", count: entry.summary.teaGlasses, unit: "bardak")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Layout.Spacing.md)
        }
        .containerBackground(Color.bgPage, for: .widget)
        .widgetURL(URL(string: "sofra://daily")!)
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

    /// Simple color coding for macro rows.
    private func macroColor(for label: String) -> Color {
        switch label {
        case "Protein": return .green
        case "Carbs":   return .orange
        default:        return .red.opacity(0.8)
        }
    }

    /// Bread/tea counter pill with emoji icon.
    private func counterPill(icon: String, count: Int, unit: String) -> some View {
        HStack(spacing: 3) {
            Text(icon)
                .font(.system(size: 11))
            Text("\(count) \(unit)")
                .font(.sofraCaption)
                .foregroundStyle(Color.textSecondary)
        }
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
