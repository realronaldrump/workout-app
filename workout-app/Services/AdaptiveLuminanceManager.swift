import SwiftUI
import Combine
import UIKit

final class AdaptiveLuminanceManager: ObservableObject {
    @Published private(set) var luminance: Double = 0.3
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init() {
        updateLuminance()

        NotificationCenter.default.publisher(for: UIScreen.brightnessDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateLuminance()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateLuminance()
            }
            .store(in: &cancellables)

        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            self?.updateLuminance()
        }
    }

    deinit {
        timer?.invalidate()
    }

    /// Calculates an adaptive luminance value based on the user's screen brightness
    /// and time of day. Note: This uses the screen brightness slider value as a proxy
    /// for ambient light conditions, not the actual ambient light sensor data (iOS
    /// does not provide public API for raw ambient light). When the user has auto-
    /// brightness enabled, this serves as a reasonable approximation.
    private func updateLuminance() {
        // UIScreen.main.brightness is 0.0-1.0 representing the brightness slider
        // This acts as a reasonable proxy when the user has auto-brightness enabled
        let ambient = Double(UIScreen.main.brightness)
        let timeFactor = timeOfDayFactor(for: Date())
        let blended = 0.18 + (ambient * 0.38) + (timeFactor * 0.32)
        let clamped = min(max(blended, 0.12), 0.7)

        if abs(luminance - clamped) > 0.01 {
            luminance = clamped
        }
    }

    private func timeOfDayFactor(for date: Date) -> Double {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let normalized = (Double(hour) + Double(minute) / 60.0) / 24.0
        let curve = (sin((normalized - 0.25) * 2 * Double.pi) + 1) / 2
        return curve
    }
}
