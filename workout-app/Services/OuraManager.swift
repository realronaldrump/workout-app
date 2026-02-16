import Foundation
import Combine

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

@MainActor
final class OuraManager: ObservableObject {
    @Published var connectionStatus: OuraConnectionStatus = .notConnected
    @Published var dailyScoreStore: [Date: OuraDailyScoreDay] = [:]
    @Published var lastSyncDate: Date?
    @Published var lastError: String?
    @Published var isSyncing = false

    private let persistenceStore: OuraPersistenceStore
    private let apiClient: OuraAPIClient
    private var installId: String?
    private var installToken: String?
    private var periodicRefreshTask: Task<Void, Never>?

    convenience init() {
        self.init(
            persistenceStore: OuraPersistenceStore(),
            apiClient: OuraAPIClient()
        )
    }

    init(
        persistenceStore: OuraPersistenceStore,
        apiClient: OuraAPIClient
    ) {
        self.persistenceStore = persistenceStore
        self.apiClient = apiClient
        self.installId = persistenceStore.loadInstallId()
        self.installToken = persistenceStore.loadInstallToken()
        self.dailyScoreStore = persistenceStore.loadScores()

        periodicRefreshTask = Task { [weak self] in
            await self?.runPeriodicRefreshLoop()
        }

        Task {
            await refreshConnectionStatus()
        }
    }

    deinit {
        periodicRefreshTask?.cancel()
    }

    var isConnected: Bool {
        if case .connected = connectionStatus { return true }
        if case .syncing = connectionStatus { return true }
        return false
    }

    func scores(in range: DateInterval) -> [OuraDailyScoreDay] {
        dailyScoreStore.values
            .filter { range.contains($0.dayStart) }
            .sorted { $0.dayStart < $1.dayStart }
    }

    func score(for dayStart: Date) -> OuraDailyScoreDay? {
        let normalized = Calendar.current.startOfDay(for: dayStart)
        return dailyScoreStore[normalized]
    }

    func startConnectionFlow() async {
        guard !isSyncing else { return }
        connectionStatus = .connecting
        lastError = nil

        do {
            try await ensureInstallIdentity()
            guard let installToken else {
                throw OuraAPIClientError.invalidResponse
            }

            let payload = try await apiClient.fetchConnectURL(installToken: installToken)
            guard let url = URL(string: payload.url) else {
                throw OuraAPIClientError.invalidResponse
            }

            openConnectURL(url)
        } catch {
            let message = error.localizedDescription
            lastError = message
            connectionStatus = .error(message)
        }
    }

    func handleIncomingURL(_ url: URL) {
        guard url.scheme == "workoutapp", url.host == "oura" else { return }

        let params = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let status = params.first(where: { $0.name == "status" })?.value ?? "error"

        if status == "success" {
            Task {
                await refreshConnectionStatus()
                await pullScores(startDate: historicalStartDate(), endDate: Date())
            }
        } else {
            let reason = params.first(where: { $0.name == "reason" })?.value ?? "authorization_failed"
            let message = "Oura authorization failed: \(reason)"
            lastError = message
            connectionStatus = .error(message)
        }
    }

    func refreshConnectionStatus() async {
        guard let installToken else {
            connectionStatus = .notConnected
            return
        }

        do {
            let status = try await apiClient.fetchStatus(installToken: installToken)
            if status.connected {
                connectionStatus = isSyncing ? .syncing : .connected
                lastSyncDate = status.lastSyncAt
                lastError = status.lastError
            } else {
                connectionStatus = .notConnected
                if let statusError = status.lastError {
                    lastError = statusError
                }
            }
        } catch {
            let message = error.localizedDescription
            lastError = message
            connectionStatus = .error(message)
        }
    }

    func manualRefresh(range: DateInterval? = nil) async {
        guard let installToken else {
            await refreshConnectionStatus()
            return
        }

        let targetRange = range ?? DateInterval(start: historicalStartDate(), end: Date())
        guard !isSyncing else { return }

        isSyncing = true
        connectionStatus = .syncing
        defer {
            isSyncing = false
            if case .error = connectionStatus {
                // keep error state
            } else {
                connectionStatus = .connected
            }
        }

        do {
            _ = try await apiClient.triggerSync(
                installToken: installToken,
                startDate: targetRange.start,
                endDate: targetRange.end
            )

            try? await Task.sleep(nanoseconds: 400_000_000)
            await pullScores(startDate: targetRange.start, endDate: targetRange.end)
            await refreshConnectionStatus()
        } catch {
            let message = error.localizedDescription
            lastError = message
            connectionStatus = .error(message)
        }
    }

    func autoRefreshOnForeground() async {
        guard installToken != nil else { return }
        await refreshConnectionStatus()
        guard isConnected else { return }

        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -120, to: end) ?? end
        await pullScores(startDate: start, endDate: end)
    }

    func pullScores(startDate: Date, endDate: Date) async {
        guard let installToken else { return }

        do {
            let response = try await apiClient.fetchScores(
                installToken: installToken,
                startDate: startDate,
                endDate: endDate
            )

            var updated = dailyScoreStore
            for backendDay in response.data {
                guard let mapped = backendDay.asDailyScoreDay() else { continue }
                updated[mapped.dayStart] = mapped
            }

            dailyScoreStore = updated
            persistenceStore.saveScores(updated)
            lastSyncDate = Date()
            if case .error = connectionStatus {
                connectionStatus = .connected
            }
        } catch {
            let message = error.localizedDescription
            lastError = message
            connectionStatus = .error(message)
        }
    }

    func disconnect() async {
        if let installToken {
            do {
                try await apiClient.disconnect(installToken: installToken)
            } catch {
                // Continue to local clear so the app can recover even if server call fails.
                lastError = error.localizedDescription
            }
        }

        clearLocalCacheOnly()
        connectionStatus = .notConnected
        lastError = nil
        lastSyncDate = nil
    }

    func clearLocalCacheOnly() {
        persistenceStore.clearAll()
        installId = nil
        installToken = nil
        dailyScoreStore.removeAll()
    }

    private func ensureInstallIdentity() async throws {
        if installId != nil, installToken != nil {
            return
        }

        let registered = try await apiClient.registerDevice()
        installId = registered.installId
        installToken = registered.installToken
        persistenceStore.saveInstallId(registered.installId)
        persistenceStore.saveInstallToken(registered.installToken)
    }

    private func historicalStartDate() -> Date {
        OuraDateCoding.dayFormatter.date(from: "2015-01-01") ?? Date(timeIntervalSince1970: 0)
    }

    private func runPeriodicRefreshLoop() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: 4 * 60 * 60 * 1_000_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            await autoRefreshOnForeground()
        }
    }

    private func openConnectURL(_ url: URL) {
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #elseif canImport(AppKit)
        NSWorkspace.shared.open(url)
        #else
        print("Unable to open Oura authorization URL on this platform: \(url)")
        #endif
    }
}
