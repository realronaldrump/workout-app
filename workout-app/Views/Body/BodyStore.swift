import Combine
import Foundation

/// Loads the whole weight and body-fat history once, analyzes it off the main actor, and keeps
/// the result for both the Body tab and the Health hub's Body row. Changing the chart range is a
/// slice of the analyzed series, so it never goes back to Apple Health.
@MainActor
final class BodyStore: ObservableObject {
    struct Snapshot: Sendable {
        var weight = BodySeries.empty(.weight)
        var bodyFat = BodySeries.empty(.bodyFat)
        var loadedAt: Date?
    }

    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private var loadTask: Task<Void, Never>?
    private var generation: UInt64 = 0

    nonisolated deinit {}

    var hasLoaded: Bool { snapshot.loadedAt != nil }
    var weight: BodySeries { snapshot.weight }
    var bodyFat: BodySeries { snapshot.bodyFat }

    /// Refreshes and waits for the result, for pull to refresh.
    func reload(from health: HealthViewStore) async {
        refresh(from: health)
        await loadTask?.value
    }

    /// Fetches both histories and replaces the snapshot in one publish. A newer refresh always
    /// wins, and a failed one keeps the last good snapshot on screen.
    func refresh(from health: HealthViewStore) {
        guard health.authorizationStatus == .authorized else { return }
        loadTask?.cancel()
        generation &+= 1
        let generation = generation
        isLoading = true
        errorMessage = nil

        loadTask = Task { [weak self] in
            do {
                let range = DateInterval(start: .distantPast, end: Date())
                let weightSamples = try await health.fetchMetricSamples(metric: .bodyMass, range: range)
                let fatSamples = try await health.fetchMetricSamples(metric: .bodyFatPercentage, range: range)
                try Task.checkCancellation()
                let weights = weightSamples.map {
                    BodyRawSample(id: $0.id, timestamp: $0.timestamp, value: HealthMetric.bodyMass.displayValue(from: $0.value))
                }
                let fats = fatSamples.map {
                    BodyRawSample(
                        id: $0.id,
                        timestamp: $0.timestamp,
                        value: HealthMetric.bodyFatPercentage.displayValue(from: $0.value)
                    )
                }
                let built = await Task.detached(priority: .userInitiated) {
                    Snapshot(
                        weight: BodyTrendEngine.build(samples: weights, kind: .weight),
                        bodyFat: BodyTrendEngine.build(samples: fats, kind: .bodyFat),
                        loadedAt: Date()
                    )
                }.value
                guard let self, generation == self.generation, !Task.isCancelled else { return }
                self.snapshot = built
                self.isLoading = false
            } catch {
                guard let self, generation == self.generation, !(error is CancellationError) else { return }
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}
