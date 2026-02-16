import Foundation
import Security

final class OuraPersistenceStore {
    private let userDefaults = UserDefaults.standard
    private let installIdKey = "oura.installId"
    private let tokenService = "davis.workout-app.oura"
    private let tokenAccount = "install-token"

    private var scoresFileURL: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("oura_daily_scores.json")
    }

    func saveInstallId(_ installId: String) {
        userDefaults.set(installId, forKey: installIdKey)
    }

    func loadInstallId() -> String? {
        userDefaults.string(forKey: installIdKey)
    }

    func clearInstallId() {
        userDefaults.removeObject(forKey: installIdKey)
    }

    func saveInstallToken(_ token: String) {
        guard let tokenData = token.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tokenService,
            kSecAttrAccount as String: tokenAccount
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: tokenData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = tokenData
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    func loadInstallToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tokenService,
            kSecAttrAccount as String: tokenAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let tokenData = item as? Data,
              let token = String(data: tokenData, encoding: .utf8) else {
            return nil
        }

        return token
    }

    func clearInstallToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tokenService,
            kSecAttrAccount as String: tokenAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    func loadScores() -> [Date: OuraDailyScoreDay] {
        guard FileManager.default.fileExists(atPath: scoresFileURL.path) else {
            return [:]
        }

        do {
            let data = try Data(contentsOf: scoresFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode([OuraDailyScoreDay].self, from: data)
            return Dictionary(uniqueKeysWithValues: decoded.map { ($0.dayStart, $0) })
        } catch {
            print("Failed to load Oura scores: \(error)")
            return [:]
        }
    }

    func saveScores(_ scores: [Date: OuraDailyScoreDay]) {
        let list = scores.values.sorted { $0.dayStart < $1.dayStart }
        let url = scoresFileURL

        Task.detached(priority: .utility) {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(list)
                try data.write(to: url, options: [.atomic, .completeFileProtection])
            } catch {
                print("Failed to save Oura scores: \(error)")
            }
        }
    }

    func clearScores() {
        do {
            if FileManager.default.fileExists(atPath: scoresFileURL.path) {
                try FileManager.default.removeItem(at: scoresFileURL)
            }
        } catch {
            print("Failed to clear Oura score file: \(error)")
        }
    }

    func clearAll() {
        clearInstallId()
        clearInstallToken()
        clearScores()
    }
}
