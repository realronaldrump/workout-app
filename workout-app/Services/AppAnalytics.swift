import CryptoKit
import Foundation
import OSLog
import SwiftUI
import UIKit

enum AnalyticsSignal {
    static let appLaunched = "App.lifecycle.launched"
    static let appForegrounded = "App.lifecycle.foregrounded"
    static let appBackgrounded = "App.lifecycle.backgrounded"
    static let screenViewed = "Navigation.screen.viewed"
    static let tabSelected = "Navigation.tab.selected"

    static let onboardingStarted = "Onboarding.started"
    static let onboardingStepViewed = "Onboarding.step.viewed"
    static let onboardingSkipped = "Onboarding.skipped"
    static let onboardingImportSelected = "Onboarding.import.selected"
    static let onboardingStartFreshSelected = "Onboarding.startFresh.selected"
    static let onboardingCompleted = "Onboarding.completed"

    static let importWizardViewed = "Import.wizard.viewed"
    static let importWizardStepViewed = "Import.wizard.step.viewed"
    static let importFileSelectionStarted = "Import.fileSelection.started"
    static let importCompleted = "Import.completed"
    static let importFailed = "Import.failed"

    static let healthAuthorizationStarted = "Health.authorization.started"
    static let healthAuthorizationCompleted = "Health.authorization.completed"
    static let healthAuthorizationFailed = "Health.authorization.failed"
    static let healthSyncWizardViewed = "Health.syncWizard.viewed"
    static let healthSyncStarted = "Health.sync.started"
    static let healthSyncCompleted = "Health.sync.completed"
    static let healthSyncFailed = "Health.sync.failed"

    static let sessionStarted = "Session.started"
    static let sessionExerciseAdded = "Session.exercise.added"
    static let sessionSetAdded = "Session.set.added"
    static let sessionSetCompleted = "Session.set.completed"
    static let sessionFinished = "Session.finished"
    static let sessionFinishFailed = "Session.finish.failed"
    static let sessionDiscarded = "Session.discarded"

    static let exportStarted = "Export.started"
    static let exportCompleted = "Export.completed"
    static let exportFailed = "Export.failed"

    static let analyticsEnabled = "Settings.analytics.enabled"
}

private struct AnalyticsRemoteConfiguration: Sendable {
    let appID: String
    let namespace: String
    let clientUser: String
    let isTestMode: Bool
}

private struct AnalyticsEnvelope: Sendable {
    let name: String
    let sessionID: String
    let payload: [String: String]
    let floatValue: Double?
}

final class AppAnalytics {
    static let shared = AppAnalytics()

    static let collectionEnabledKey = "analyticsCollectionEnabled"

    private static let installIDKey = "analyticsInstallID"
    private static let telemetryDeckAppIDKey = "BBWTelemetryDeckAppID"
    private static let telemetryDeckNamespaceKey = "BBWTelemetryDeckNamespace"
    private static let debugLoggingKey = "BBWAnalyticsDebugLogging"

    private let userDefaults = UserDefaults.standard
    private let queue = DispatchQueue(label: "davis.workout-app.analytics", qos: .utility)
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "davis.workout-app", category: "Analytics")

    private var didConfigure = false
    private var hasSeenActivePhase = false
    private var sessionID = UUID().uuidString
    private var sessionStartedAt = Date()
    private var defaultPayload: [String: String] = [:]
    private var collectionEnabled = true
    private var debugLogging = false
    private var remoteConfiguration: AnalyticsRemoteConfiguration?

    private init() {}

    var isRemoteConfigured: Bool {
        queue.sync {
            remoteConfiguration != nil
        }
    }

    var statusSummary: String {
        queue.sync {
            if remoteConfiguration != nil {
                return collectionEnabled ? "Anonymous analytics on" : "Anonymous analytics off"
            }
            return "Add TelemetryDeck keys to enable uploads"
        }
    }

    func configureIfNeeded() {
        queue.sync {
            guard !didConfigure else { return }
            didConfigure = true
            collectionEnabled = readCollectionEnabled()
            debugLogging = readBoolFromInfoDictionary(Self.debugLoggingKey)

            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
            let build = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "unknown"
            defaultPayload = [
                "App.version": version,
                "App.build": build,
                "App.platform": "iOS",
                "Device.systemVersion": UIDevice.current.systemVersion,
                "User.locale": Locale.current.identifier
            ]

            let appID = readTrimmedInfoString(Self.telemetryDeckAppIDKey)
            let namespace = readTrimmedInfoString(Self.telemetryDeckNamespaceKey)
            guard !appID.isEmpty, !namespace.isEmpty else {
                if debugLogging {
                    logger.notice("Analytics remote sink is not configured. Add Info.plist keys to enable uploads.")
                }
                return
            }

            remoteConfiguration = AnalyticsRemoteConfiguration(
                appID: appID,
                namespace: namespace,
                clientUser: hashedInstallIdentifier(),
                isTestMode: isDebugBuild
            )
        }
    }

    func setCollectionEnabled(_ enabled: Bool) {
        userDefaults.set(enabled, forKey: Self.collectionEnabledKey)
        queue.async {
            self.collectionEnabled = enabled
            if enabled {
                self.enqueue(
                    name: AnalyticsSignal.analyticsEnabled,
                    payload: ["Settings.destination": self.remoteConfiguration == nil ? "unconfigured" : "telemetrydeck"],
                    floatValue: nil
                )
            }
        }
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        configureIfNeeded()

        queue.async {
            switch phase {
            case .active:
                let eventName = self.hasSeenActivePhase ? AnalyticsSignal.appForegrounded : AnalyticsSignal.appLaunched
                self.hasSeenActivePhase = true
                self.sessionID = UUID().uuidString
                self.sessionStartedAt = Date()
                self.enqueue(name: eventName, payload: [:], floatValue: nil)
            case .background:
                let duration = max(0, Date().timeIntervalSince(self.sessionStartedAt))
                self.enqueue(
                    name: AnalyticsSignal.appBackgrounded,
                    payload: [:],
                    floatValue: duration
                )
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }

    func track(_ name: String, payload: [String: String] = [:], floatValue: Double? = nil) {
        configureIfNeeded()
        queue.async {
            self.enqueue(name: name, payload: payload, floatValue: floatValue)
        }
    }

    func trackScreen(_ screenName: String, source: String? = nil) {
        var payload = ["Navigation.screen": screenName]
        if let source, !source.isEmpty {
            payload["Context.source"] = source
        }
        track(AnalyticsSignal.screenViewed, payload: payload)
    }

    private func enqueue(name: String, payload: [String: String], floatValue: Double?) {
        guard collectionEnabled else { return }
        guard let remoteConfiguration else { return }

        let mergedPayload = defaultPayload.merging(payload.filter { !$0.value.isEmpty }) { _, new in new }
        let envelope = AnalyticsEnvelope(
            name: name,
            sessionID: sessionID,
            payload: mergedPayload,
            floatValue: floatValue
        )

        let logger = self.logger
        Task.detached(priority: .utility) {
            await Self.sendToTelemetryDeck(envelope, configuration: remoteConfiguration, logger: logger)
        }
    }

    private func readCollectionEnabled() -> Bool {
        if userDefaults.object(forKey: Self.collectionEnabledKey) == nil {
            return true
        }
        return userDefaults.bool(forKey: Self.collectionEnabledKey)
    }

    private func readTrimmedInfoString(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func readBoolFromInfoDictionary(_ key: String) -> Bool {
        Bundle.main.object(forInfoDictionaryKey: key) as? Bool ?? false
    }

    private func hashedInstallIdentifier() -> String {
        let installID: String
        if let existing = userDefaults.string(forKey: Self.installIDKey), !existing.isEmpty {
            installID = existing
        } else {
            let created = UUID().uuidString
            userDefaults.set(created, forKey: Self.installIDKey)
            installID = created
        }

        let digest = SHA256.hash(data: Data(installID.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func sendToTelemetryDeck(
        _ envelope: AnalyticsEnvelope,
        configuration: AnalyticsRemoteConfiguration,
        logger: Logger
    ) async {
        guard let url = URL(string: "https://nom.telemetrydeck.com/v2/namespace/\(configuration.namespace)/") else {
            logger.error("Analytics endpoint URL could not be constructed.")
            return
        }

        var signal: [String: Any] = [
            "appID": configuration.appID,
            "clientUser": configuration.clientUser,
            "type": envelope.name,
            "sessionID": envelope.sessionID,
            "isTestMode": configuration.isTestMode,
            "payload": envelope.payload
        ]

        if let floatValue = envelope.floatValue {
            signal["floatValue"] = floatValue
        }

        guard JSONSerialization.isValidJSONObject([signal]) else {
            logger.error("Analytics payload was not valid JSON for signal \(envelope.name, privacy: .public)")
            return
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [signal], options: [])

            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                logger.error("Analytics request failed with status \(status, privacy: .public) for signal \(envelope.name, privacy: .public)")
                return
            }
        } catch {
            logger.error("Analytics request error for signal \(envelope.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

private var isDebugBuild: Bool {
    #if DEBUG
    true
    #else
    false
    #endif
}

private struct AnalyticsScreenModifier: ViewModifier {
    let screenName: String
    let source: String?

    func body(content: Content) -> some View {
        content.onAppear {
            AppAnalytics.shared.trackScreen(screenName, source: source)
        }
    }
}

extension View {
    func analyticsScreen(_ screenName: String, source: String? = nil) -> some View {
        modifier(AnalyticsScreenModifier(screenName: screenName, source: source))
    }
}
