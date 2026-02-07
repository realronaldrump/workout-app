import SwiftUI

struct WorkoutAnnotationCard: View {
    @EnvironmentObject var annotationsManager: WorkoutAnnotationsManager
    let workout: Workout

    @State private var stress: StressLevel?
    @State private var soreness: SorenessLevel?
    @State private var caffeine: CaffeineIntake?
    @State private var mood: MoodLevel?
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Check-in")
                    .font(Theme.Typography.title3)
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                Button("Clear") {
                    stress = nil
                    soreness = nil
                    caffeine = nil
                    mood = nil
                    annotationsManager.clearNonGymFields(for: workout.id)
                }
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textTertiary)
            }

            HStack(spacing: Theme.Spacing.sm) {
                AnnotationMenu(label: "Stress", value: stress?.label, tint: stress?.tint ?? Theme.Colors.textSecondary) {
                    ForEach(StressLevel.allCases, id: \.self) { level in
                        Button(level.label) { stress = level }
                    }
                    Button("None", role: .destructive) { stress = nil }
                }

                AnnotationMenu(label: "Soreness", value: soreness?.label, tint: soreness?.tint ?? Theme.Colors.textSecondary) {
                    ForEach(SorenessLevel.allCases, id: \.self) { level in
                        Button(level.label) { soreness = level }
                    }
                    Button("None", role: .destructive) { soreness = nil }
                }

                AnnotationMenu(label: "Caffeine", value: caffeine?.label, tint: caffeine?.tint ?? Theme.Colors.textSecondary) {
                    ForEach(CaffeineIntake.allCases, id: \.self) { level in
                        Button(level.label) { caffeine = level }
                    }
                    Button("None", role: .destructive) { caffeine = nil }
                }

                AnnotationMenu(label: "Mood", value: mood?.label, tint: mood?.tint ?? Theme.Colors.textSecondary) {
                    ForEach(MoodLevel.allCases, id: \.self) { level in
                        Button(level.label) { mood = level }
                    }
                    Button("None", role: .destructive) { mood = nil }
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .softCard(elevation: 2)
        .onAppear { loadIfNeeded() }
        .onChange(of: stress) { _, _ in save() }
        .onChange(of: soreness) { _, _ in save() }
        .onChange(of: caffeine) { _, _ in save() }
        .onChange(of: mood) { _, _ in save() }
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        if let annotation = annotationsManager.annotation(for: workout.id) {
            stress = annotation.stress
            soreness = annotation.soreness
            caffeine = annotation.caffeine
            mood = annotation.mood
        }
        didLoad = true
    }

    private func save() {
        let existingGym = annotationsManager.annotation(for: workout.id)?.gymProfileId
        let hasNonGymFields = stress != nil || soreness != nil || caffeine != nil || mood != nil

        if !hasNonGymFields && existingGym == nil {
            annotationsManager.removeAnnotation(for: workout.id)
            return
        }

        annotationsManager.upsertAnnotation(
            for: workout.id,
            stress: stress,
            soreness: soreness,
            caffeine: caffeine,
            mood: mood
        )
    }
}

private struct AnnotationMenu<Content: View>: View {
    let label: String
    let value: String?
    let tint: Color
    let content: () -> Content

    init(label: String, value: String?, tint: Color, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.value = value
        self.tint = tint
        self.content = content
    }

    var body: some View {
        Menu(content: content) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
                Text(value ?? "Set")
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(tint)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Theme.Colors.surface.opacity(0.6))
            .cornerRadius(Theme.CornerRadius.small)
        }
    }
}
