import UIKit

enum Haptics {
    static let preferenceKey = "hapticsEnabled"

    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let lightImpactGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyImpactGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private static let rigidImpactGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    private static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? true
    }

    static func selection() {
        guard isEnabled else { return }
        selectionGenerator.prepare()
        selectionGenerator.selectionChanged()
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard isEnabled else { return }
        let generator = impactGenerator(for: style)
        generator.prepare()
        generator.impactOccurred()
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(type)
    }

    // MARK: - Semantic Haptics

    /// A satisfying thud for completing a set.
    static func setComplete() {
        guard isEnabled else { return }
        mediumImpactGenerator.prepare()
        mediumImpactGenerator.impactOccurred(intensity: 0.7)
    }

    /// A single semantic success event for finishing a workout.
    static func workoutFinished() {
        notify(.success)
    }

    /// Subtle bump for adding an exercise or set.
    static func added() {
        guard isEnabled else { return }
        lightImpactGenerator.prepare()
        lightImpactGenerator.impactOccurred(intensity: 0.5)
    }

    /// Quick rigid tap for toggling controls, filters, segments.
    static func toggle() {
        guard isEnabled else { return }
        rigidImpactGenerator.prepare()
        rigidImpactGenerator.impactOccurred(intensity: 0.4)
    }

    private static func impactGenerator(
        for style: UIImpactFeedbackGenerator.FeedbackStyle
    ) -> UIImpactFeedbackGenerator {
        switch style {
        case .light, .soft:
            return lightImpactGenerator
        case .medium:
            return mediumImpactGenerator
        case .heavy:
            return heavyImpactGenerator
        case .rigid:
            return rigidImpactGenerator
        @unknown default:
            return lightImpactGenerator
        }
    }
}
