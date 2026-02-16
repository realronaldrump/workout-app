import Foundation

enum OuraAPIClientError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Oura backend URL is not configured."
        case .invalidResponse:
            return "Unexpected response from Oura backend."
        case .serverError(let code, let message):
            return "Oura backend error (\(code)): \(message)"
        }
    }
}

struct OuraAPIClient {
    private let session: URLSession
    private let baseURLProvider: () -> URL?

    init(
        session: URLSession = .shared,
        baseURLProvider: @escaping () -> URL? = {
            let configured = UserDefaults.standard.string(forKey: "ouraBackendBaseURL")
            let fallback = "https://your-worker-domain.example"
            let selected = (configured?.isEmpty == false) ? configured : fallback
            return URL(string: selected ?? fallback)
        }
    ) {
        self.session = session
        self.baseURLProvider = baseURLProvider
    }

    func registerDevice() async throws -> OuraBackendRegisterResponse {
        try await performRequest(path: "/v1/device/register", method: "POST", installToken: nil)
    }

    func fetchConnectURL(installToken: String) async throws -> OuraBackendConnectURLResponse {
        try await performRequest(path: "/v1/oura/connect-url", method: "GET", installToken: installToken)
    }

    func fetchStatus(installToken: String) async throws -> OuraBackendStatusResponse {
        try await performRequest(path: "/v1/oura/status", method: "GET", installToken: installToken)
    }

    func fetchScores(
        installToken: String,
        startDate: Date,
        endDate: Date
    ) async throws -> OuraBackendScoresResponse {
        let formatter = OuraDateCoding.dayFormatter
        let start = formatter.string(from: startDate)
        let end = formatter.string(from: endDate)
        let path = "/v1/oura/scores?start_date=\(start)&end_date=\(end)"
        return try await performRequest(path: path, method: "GET", installToken: installToken)
    }

    func triggerSync(
        installToken: String,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) async throws -> OuraBackendSyncResponse {
        var payload: [String: String] = [:]
        let formatter = OuraDateCoding.dayFormatter
        if let startDate {
            payload["start_date"] = formatter.string(from: startDate)
        }
        if let endDate {
            payload["end_date"] = formatter.string(from: endDate)
        }

        let body = payload.isEmpty ? nil : try JSONSerialization.data(withJSONObject: payload)
        return try await performRequest(path: "/v1/oura/sync", method: "POST", installToken: installToken, body: body)
    }

    func disconnect(installToken: String) async throws {
        let _: EmptyResponse = try await performRequest(path: "/v1/oura/connection", method: "DELETE", installToken: installToken)
    }

    private func performRequest<T: Decodable>(
        path: String,
        method: String,
        installToken: String?,
        body: Data? = nil
    ) async throws -> T {
        guard let baseURL = baseURLProvider() else {
            throw OuraAPIClientError.invalidBaseURL
        }

        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw OuraAPIClientError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let installToken {
            request.setValue("Bearer \(installToken)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OuraAPIClientError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let serverMessage = parseServerMessage(data: data)
            throw OuraAPIClientError.serverError(http.statusCode, serverMessage)
        }

        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }

    private func parseServerMessage(data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? String {
                return error
            }
            if let details = object["details"] as? String {
                return details
            }
        }

        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text
        }
        return "Unknown error"
    }
}

private struct EmptyResponse: Decodable {
    init() {}
}
