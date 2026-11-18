import Combine
import Foundation

nonisolated struct BodyWeighIn: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let pounds: Double
    let isHealthCorrection: Bool

    var sample: BodyRawSample { BodyRawSample(id: id, timestamp: timestamp, value: pounds) }

    var isValid: Bool {
        timestamp.timeIntervalSinceReferenceDate.isFinite && BodyTrendEngine.isPlausible(pounds, kind: .weight)
    }
}

private enum BodyWeighInError: LocalizedError {
    case invalidWeight
    case invalidDate
    case unreadableLog

    var errorDescription: String? {
        switch self {
        case .invalidWeight: return "Enter a weight between 20 and 1,000 lb."
        case .invalidDate: return "Choose a date and time in the past or today."
        case .unreadableLog: return "Your saved weigh-ins couldn’t be opened."
        }
    }
}

/// Apple Health supplies scale readings. Manual entries and corrections are saved in the app.
@MainActor
final class BodyStore: ObservableObject {
    static let shared: BodyStore = {
#if DEBUG
        if AnalyticsUITestFixture.isEnabled { return BodyStore(fileURL: nil) }
#endif
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return BodyStore(fileURL: directory.appendingPathComponent("BodyWeighIns.json"))
    }()

    struct Snapshot: Sendable {
        var weight = BodySeries.empty(.weight)
        var bodyFat = BodySeries.empty(.bodyFat)
        var loadedAt: Date?
        var revision: UInt64 = 0
    }

    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var logErrorMessage: String?

    private let fileURL: URL?
    private var didReadLog = false
    private var weighIns: [UUID: BodyWeighIn] = [:]
    private var healthWeights: [BodyRawSample] = []
    private var loadTask: Task<Void, Never>?
    private var generation: UInt64 = 0

    init(fileURL: URL?) {
        self.fileURL = fileURL
        loadLocalLog()
    }

    nonisolated deinit {}

    var hasLoaded: Bool { snapshot.loadedAt != nil }
    var weight: BodySeries { snapshot.weight }
    var bodyFat: BodySeries { snapshot.bodyFat }
    var savedWeighInCount: Int { weighIns.count }

    func savedWeighIn(id: UUID) -> BodyWeighIn? {
        weighIns[id]
    }

    func saveWeighIn(pounds: Double, at timestamp: Date, editing reading: BodyRawSample?) throws {
        guard BodyTrendEngine.isPlausible(pounds, kind: .weight) else { throw BodyWeighInError.invalidWeight }
        guard timestamp.timeIntervalSinceReferenceDate.isFinite, timestamp <= Date() else {
            throw BodyWeighInError.invalidDate
        }
        try readLogIfNeeded()
        let id = reading?.id ?? UUID()
        let entry = BodyWeighIn(
            id: id,
            timestamp: timestamp,
            pounds: pounds,
            isHealthCorrection: weighIns[id]?.isHealthCorrection ?? (reading != nil)
        )
        var updated = weighIns
        updated[id] = entry
        try commit(updated)
    }

    func removeWeighIn(id: UUID) throws {
        try readLogIfNeeded()
        var updated = weighIns
        guard updated.removeValue(forKey: id) != nil else { return }
        try commit(updated)
    }

    func weighInsForBackup() throws -> [BodyWeighIn] {
        try readLogIfNeeded()
        return weighIns.values.sorted { $0.timestamp < $1.timestamp }
    }

    func mergeWeighInsFromBackup(_ entries: [BodyWeighIn]) throws -> Int {
        guard !entries.isEmpty else { return 0 }
        try readLogIfNeeded()
        var updated = weighIns
        for entry in entries where entry.isValid && updated[entry.id] == nil {
            updated[entry.id] = entry
        }
        let inserted = updated.count - weighIns.count
        if inserted > 0 { try commit(updated) }
        return inserted
    }

    func clearSavedWeighIns() throws {
        guard savedWeighInCount > 0 || !didReadLog else { return }
        try commit([:])
        didReadLog = true
        logErrorMessage = nil
    }

    private func loadLocalLog() {
        guard !didReadLog else { return }
        do {
            try readLogIfNeeded()
            if !weighIns.isEmpty { publishWeight() }
        } catch {
            logErrorMessage = BodyWeighInError.unreadableLog.localizedDescription
        }
    }

    private func readLogIfNeeded() throws {
        guard !didReadLog else { return }
        if let fileURL {
            do {
                let data = try Data(contentsOf: fileURL)
                let entries = try JSONDecoder().decode([BodyWeighIn].self, from: data)
                guard entries.allSatisfy(\.isValid) else { throw BodyWeighInError.unreadableLog }
                weighIns = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                // The first launch has no saved weigh-ins.
            } catch {
                throw BodyWeighInError.unreadableLog
            }
        }
        didReadLog = true
        logErrorMessage = nil
    }

    private func commit(_ updated: [UUID: BodyWeighIn]) throws {
        if let fileURL {
            let data = try JSONEncoder().encode(updated.values.sorted { $0.timestamp < $1.timestamp })
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        }
        weighIns = updated
        publishWeight()
    }

    private func publishWeight() {
        var updated = snapshot
        updated.weight = Self.buildWeight(healthWeights, weighIns: weighIns)
        updated.revision &+= 1
        snapshot = updated
    }

    private nonisolated static func buildWeight(
        _ healthWeights: [BodyRawSample],
        weighIns: [UUID: BodyWeighIn]
    ) -> BodySeries {
        // A correction keeps the Health sample's ID, so each reading appears only once.
        let samples = healthWeights.filter { weighIns[$0.id] == nil } + weighIns.values.map(\.sample)
        return BodyTrendEngine.build(samples: samples, kind: .weight, preferredSampleIDs: Set(weighIns.keys))
    }

    /// Refreshes and waits for the result, for pull to refresh.
    func reload(from health: HealthViewStore) async {
        refresh(from: health)
        await loadTask?.value
    }

    /// Fetches both histories and replaces the snapshot in one publish. A newer refresh always
    /// wins, and a failed one keeps the last good snapshot on screen.
    func refresh(from health: HealthViewStore) {
        loadLocalLog()
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
                guard let self else { return }
                let savedEntries = self.weighIns
                let (weightSeries, fatSeries) = await Task.detached(priority: .userInitiated) {
                    (
                        Self.buildWeight(weights, weighIns: savedEntries),
                        BodyTrendEngine.build(samples: fats, kind: .bodyFat)
                    )
                }.value
                guard generation == self.generation, !Task.isCancelled else { return }
                self.healthWeights = weights
                // A weigh-in can be saved while the Health query or analysis is in flight.
                let weight = savedEntries == self.weighIns ? weightSeries : Self.buildWeight(weights, weighIns: self.weighIns)
                self.snapshot = Snapshot(
                    weight: weight,
                    bodyFat: fatSeries,
                    loadedAt: Date(),
                    revision: self.snapshot.revision &+ 1
                )
                self.isLoading = false
            } catch {
                guard let self, generation == self.generation, !(error is CancellationError) else { return }
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}
