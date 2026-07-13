//
//  OnboardingView.swift
//  Calorisor — onboarding quiz: goal → height → weight → activity → age → sex → result → paywall.
//
//  One question per page using TabView page-style. Flat design tokens throughout.
//  Flat bordered cards, spring transitions, accent progress indicator. The result
//  step foregrounds the core value — capture is all it takes — before the paywall.
//

import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var model = OnboardingModel()

    @AppStorage("calorisor.onboardingCompleted") private var onboardingCompleted = false

    var body: some View {
        ZStack {
            Color.bgPage.ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress indicator
                progressBar
                    .padding(.horizontal, Layout.Spacing.lg)
                    .padding(.top, 60)

                // Page content
                TabView(selection: $model.currentStep) {
                    GoalStepView(model: model)
                        .tag(OnboardingStep.goal)
                    HeightStepView(model: model)
                        .tag(OnboardingStep.height)
                    WeightStepView(model: model)
                        .tag(OnboardingStep.weight)
                    ActivityStepView(model: model)
                        .tag(OnboardingStep.activity)
                    AgeStepView(model: model)
                        .tag(OnboardingStep.age)
                    SexStepView(model: model)
                        .tag(OnboardingStep.sex)
                    ResultStepView(model: model) {
                        model.saveProfile(to: modelContext)
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            model.goToNext()
                        }
                    }
                        .tag(OnboardingStep.result)
                    PaywallView {
                        model.completeOnboarding()
                        let notification = UINotificationFeedbackGenerator()
                        notification.notificationOccurred(.success)
                        onboardingCompleted = true
                    }
                        .tag(OnboardingStep.paywall)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: model.currentStep)

                // Bottom navigation
                bottomNavigation
            }
        }
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        let total = Double(OnboardingStep.allCases.count)
        let current = Double(model.currentStep.rawValue)
        let progress = (current + 1) / total
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.surfaceFlat)
                    .frame(height: 4)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentFill)
                    .frame(width: geo.size.width * progress, height: 4)
                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: progress)
            }
        }
        .frame(height: 4)
    }

    // MARK: - Bottom navigation

    private var bottomNavigation: some View {
        HStack(spacing: Layout.Spacing.md) {
            // Back button
            if model.currentStep.rawValue > 0 && model.currentStep != .paywall {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        model.goToPrevious()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .medium))
                        Text("Geri")
                            .font(.sofraLabel)
                    }
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, Layout.Spacing.lg)
                    .padding(.vertical, Layout.Spacing.md)
                }
            }

            Spacer()

            // Next / complete button
            if model.currentStep != .paywall && model.currentStep != .result {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        model.goToNext()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("İleri")
                            .font(.sofraLabel)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(Color.onAccent)
                    .padding(.horizontal, Layout.Spacing.xl)
                    .padding(.vertical, Layout.Spacing.md)
                    .background(Color.accentFill, in: RoundedRectangle(cornerRadius: Layout.Radius.control))
                }
            }
        }
        .padding(.horizontal, Layout.Spacing.lg)
        .padding(.bottom, 40)
    }
}

// MARK: - Step card wrapper

struct StepCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: Layout.Spacing.xl) {
            VStack(spacing: Layout.Spacing.sm) {
                Text(title)
                    .font(.sofraTitle)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.sofraBody)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            content
        }
        .padding(.horizontal, Layout.Spacing.xl)
    }
}

// MARK: - Goal step

struct GoalStepView: View {
    let model: OnboardingModel

    var body: some View {
        StepCard(title: OnboardingStep.goal.title, subtitle: OnboardingStep.goal.subtitle) {
            VStack(spacing: Layout.Spacing.md) {
                ForEach(Goal.allCases, id: \.self) { goal in
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            model.goal = goal
                        }
                    } label: {
                        HStack(spacing: Layout.Spacing.md) {
                            Text(goal.displayName)
                                .font(.sofraHeading)
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            if model.goal == goal {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Color.accentFill)
                            } else {
                                Circle()
                                    .strokeBorder(Color.borderHairline, lineWidth: 1.5)
                                    .frame(width: 22, height: 22)
                            }
                        }
                        .padding(Layout.Spacing.lg)
                        .background(
                            model.goal == goal ? Color.accentTintBg : Color.surfaceRaised,
                            in: RoundedRectangle(cornerRadius: Layout.Radius.card)
                        )
                        .raisedSurface(cornerRadius: Layout.Radius.card)
                    }
                    .buttonStyle(SofraPressButtonStyle(cornerRadius: Layout.Radius.card))
                }
            }
        }
    }
}

// MARK: - Height step

struct HeightStepView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        StepCard(title: OnboardingStep.height.title, subtitle: OnboardingStep.height.subtitle) {
            VStack(spacing: Layout.Spacing.lg) {
                Text("\(Int(model.heightCm))")
                    .font(.sofraDisplayNumeric)
                    .foregroundStyle(Color.accentText)

                Slider(value: $model.heightCm, in: 130...220, step: 1)
                    .tint(Color.accentFill)
                    .accessibilityValue("\(Int(model.heightCm)) cm")

                HStack {
                    Text("130 cm")
                        .font(.sofraCaption)
                        .foregroundStyle(Color.textMuted)
                    Spacer()
                    Text("220 cm")
                        .font(.sofraCaption)
                        .foregroundStyle(Color.textMuted)
                }
            }
        }
    }
}

// MARK: - Weight step

struct WeightStepView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        StepCard(title: OnboardingStep.weight.title, subtitle: OnboardingStep.weight.subtitle) {
            VStack(spacing: Layout.Spacing.lg) {
                Text("\(Int(model.weightKg))")
                    .font(.sofraDisplayNumeric)
                    .foregroundStyle(Color.accentText)

                Slider(value: $model.weightKg, in: 35...200, step: 0.5)
                    .tint(Color.accentFill)
                    .accessibilityValue("\(Int(model.weightKg)) kg")

                HStack {
                    Text("35 kg")
                        .font(.sofraCaption)
                        .foregroundStyle(Color.textMuted)
                    Spacer()
                    Text("200 kg")
                        .font(.sofraCaption)
                        .foregroundStyle(Color.textMuted)
                }
            }
        }
    }
}

// MARK: - Activity step

struct ActivityStepView: View {
    let model: OnboardingModel

    var body: some View {
        StepCard(title: OnboardingStep.activity.title, subtitle: OnboardingStep.activity.subtitle) {
            VStack(spacing: Layout.Spacing.md) {
                ForEach(ActivityLevel.allCases, id: \.self) { level in
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            model.activityLevel = level
                        }
                    } label: {
                        HStack(spacing: Layout.Spacing.md) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(level.displayName)
                                    .font(.sofraLabel)
                                    .foregroundStyle(Color.textPrimary)
                                Text(level.description)
                                    .font(.sofraCaption)
                                    .foregroundStyle(Color.textMuted)
                            }
                            Spacer()
                            if model.activityLevel == level {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Color.accentFill)
                            } else {
                                Circle()
                                    .strokeBorder(Color.borderHairline, lineWidth: 1.5)
                                    .frame(width: 22, height: 22)
                            }
                        }
                        .padding(Layout.Spacing.md)
                        .background(
                            model.activityLevel == level ? Color.accentTintBg : Color.surfaceRaised,
                            in: RoundedRectangle(cornerRadius: Layout.Radius.card)
                        )
                        .raisedSurface(cornerRadius: Layout.Radius.card)
                    }
                    .buttonStyle(SofraPressButtonStyle(cornerRadius: Layout.Radius.card))
                }
            }
        }
    }
}

// MARK: - Age step

struct AgeStepView: View {
    let model: OnboardingModel

    var body: some View {
        StepCard(title: OnboardingStep.age.title, subtitle: OnboardingStep.age.subtitle) {
            VStack(spacing: Layout.Spacing.lg) {
                Text("\(model.age)")
                    .font(.sofraDisplayNumeric)
                    .foregroundStyle(Color.accentText)

                Slider(value: Binding(
                    get: { Double(model.age) },
                    set: { model.age = Int($0) }
                ), in: 14...100, step: 1)
                .tint(Color.accentFill)
                .accessibilityValue("\(model.age)")

                HStack {
                    Text("14")
                        .font(.sofraCaption)
                        .foregroundStyle(Color.textMuted)
                    Spacer()
                    Text("100")
                        .font(.sofraCaption)
                        .foregroundStyle(Color.textMuted)
                }
            }
        }
    }
}

// MARK: - Sex step

struct SexStepView: View {
    let model: OnboardingModel

    var body: some View {
        StepCard(title: OnboardingStep.sex.title, subtitle: OnboardingStep.sex.subtitle) {
            VStack(spacing: Layout.Spacing.md) {
                ForEach(BiologicalSex.allCases, id: \.self) { sex in
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            model.biologicalSex = sex
                        }
                    } label: {
                        HStack(spacing: Layout.Spacing.md) {
                            Image(systemName: sex == .male ? "figure.stand" : "figure.stand.dress")
                                .font(.system(size: 24))
                                .foregroundStyle(Color.accentFill)
                                .frame(width: 40)
                            Text(sex.displayName)
                                .font(.sofraHeading)
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            if model.biologicalSex == sex {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Color.accentFill)
                            } else {
                                Circle()
                                    .strokeBorder(Color.borderHairline, lineWidth: 1.5)
                                    .frame(width: 22, height: 22)
                            }
                        }
                        .padding(Layout.Spacing.lg)
                        .background(
                            model.biologicalSex == sex ? Color.accentTintBg : Color.surfaceRaised,
                            in: RoundedRectangle(cornerRadius: Layout.Radius.card)
                        )
                        .raisedSurface(cornerRadius: Layout.Radius.card)
                    }
                    .buttonStyle(SofraPressButtonStyle(cornerRadius: Layout.Radius.card))
                }
            }
        }
    }
}

// MARK: - Result step

struct ResultStepView: View {
    let model: OnboardingModel
    var onSave: (() -> Void)?
    @State private var showsCalculationDetails = false

    var body: some View {
        VStack(spacing: Layout.Spacing.xl) {
            Spacer()

            Text("Günlük Hedefin")
                .font(.sofraTitle)
                .foregroundStyle(Color.textPrimary)

            // Calorie target
            VStack(spacing: 0) {
                Text("\(Int(model.dailyCalorieTarget))")
                    .font(.sofraDisplayNumeric)
                    .foregroundStyle(Color.accentText)
                Text("kalori/gün")
                    .font(.sofraCaption)
                    .foregroundStyle(Color.textMuted)
            }
            .frame(width: 180, height: 180)
            .background(Color.surfaceRaised, in: Circle())
            .raisedSurface(cornerRadius: 999)

            // Foreground the core value: from here, capture is all it takes.
            Text("Hazırsın. Bundan sonra tek yapman gereken tabağını çekmek.")
                .font(.sofraCaption)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // Floor-applied hint (Phase A4): shown only when the sex-aware
            // safety minimum clipped the raw target upward.
            if model.dailyTargetResult.floorApplied {
                HStack(alignment: .top, spacing: Layout.Spacing.sm) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.accentFill)
                    Text(floorHintText)
                        .font(.sofraCaption)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Layout.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentTintBg, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
            }

            // Macro breakdown
            VStack(spacing: Layout.Spacing.md) {
                Text("Makro Dağılımı")
                    .font(.sofraLabel)
                    .foregroundStyle(Color.textSecondary)

                HStack(spacing: Layout.Spacing.xl) {
                    macroPill(label: "Protein", value: model.proteinTargetG, color: .macroProtein)
                    macroPill(label: "Karb.", value: model.carbsTargetG, color: .macroCarb)
                    macroPill(label: "Yağ", value: model.fatTargetG, color: .macroFat)
                }
            }
            .padding(Layout.Spacing.lg)
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Layout.Radius.card))
            .raisedSurface(cornerRadius: Layout.Radius.card)

            // Start button
            Button {
                onSave?()
            } label: {
                Text("Devam Et")
                    .font(.sofraLabel)
                    .foregroundStyle(Color.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Layout.Spacing.md)
                    .background(Color.accentFill, in: RoundedRectangle(cornerRadius: Layout.Radius.control))
            }

            DisclosureGroup(isExpanded: $showsCalculationDetails) {
                VStack(alignment: .leading, spacing: Layout.Spacing.sm) {
                    calculationDetail("BMR (Mifflin-St Jeor)", value: "\(Int(model.bmr)) kcal")
                    calculationDetail(
                        "Aktivite çarpanı",
                        value: "×\(model.activityMultiplier.formatted(.number.precision(.fractionLength(2))))"
                    )
                    calculationDetail("Hedef düzeltmesi", value: formattedGoalDelta)
                }
                .padding(.top, Layout.Spacing.sm)
            } label: {
                Text("Nasıl hesapladık?")
                    .font(.sofraCaption)
                    .foregroundStyle(Color.textSecondary)
            }
            .tint(Color.accentFill)

            // Medical disclaimer (Phase A4): required alongside every computed
            // target. Sits below the fold but above the final spacer.
            Text(NutritionConstants.medicalDisclaimer)
                .font(.sofraCaption)
                .foregroundStyle(Color.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Layout.Spacing.sm)

            Spacer()
        }
        .padding(.horizontal, Layout.Spacing.xl)
    }

    /// Hint shown when the sex-aware floor clipped the raw target. Always
    /// references the actual minimum applied so future floor tweaks don't
    /// silently change copy.
    private var floorHintText: String {
        let min = Int(model.dailyTargetResult.minCalories)
        let target = Int(model.dailyTargetResult.target)
        return "Bilgi: Hesaplanan hedefin klinik alt sınırın altına düşüyordu. " +
               "Güvenliğin için hedefin \(target) kcal'de sabitlendi (alt sınır: \(min) kcal)."
    }

    private func macroPill(label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(Int(value))g")
                .font(.sofraNumericSmall)
                .foregroundStyle(Color.textPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Layout.Spacing.sm)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private var formattedGoalDelta: String {
        let delta = Int(NutritionConstants.goalDelta(model.goal))
        if delta > 0 { return "+\(delta) kcal" }
        if delta < 0 { return "\(delta) kcal" }
        return "0 kcal"
    }

    private func calculationDetail(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .font(.sofraNumericSmall)
                .foregroundStyle(Color.textPrimary)
        }
        .font(.sofraCaption)
        .foregroundStyle(Color.textMuted)
    }
}

// MARK: - Paywall placeholder
