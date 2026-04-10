import UIKit

enum Haptics {
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }

    // MARK: - Semantic Haptics

    /// A satisfying thud for completing a set.
    static func setComplete() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred(intensity: 0.7)
    }

    /// Double-tap feel for finishing a workout.
    static func workoutFinished() {
        let first = UIImpactFeedbackGenerator(style: .heavy)
        first.prepare()
        first.impactOccurred(intensity: 0.8)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let second = UINotificationFeedbackGenerator()
            second.prepare()
            second.notificationOccurred(.success)
        }
    }

    /// Subtle bump for adding an exercise or set.
    static func added() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.5)
    }

    /// Quick rigid tap for toggling controls, filters, segments.
    static func toggle() {
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        generator.impactOccurred(intensity: 0.4)
    }
}
