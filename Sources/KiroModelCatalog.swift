import Foundation

actor KiroModelCatalog {
    private let authManager: KiroAuthManager
    private let cacheTTL: TimeInterval
    private var cachedModels: [String] = []
    private var cachedAt: Date?

    init(authManager: KiroAuthManager, cacheTTL: TimeInterval = 3600) {
        self.authManager = authManager
        self.cacheTTL = cacheTTL
    }

    func models() async throws -> [String] {
        if let cachedAt,
           !cachedModels.isEmpty,
           Date().timeIntervalSince(cachedAt) < cacheTTL {
            return cachedModels
        }

        do {
            let fetched = try await fetchModels()
            cachedModels = fetched
            cachedAt = Date()
            return fetched
        } catch {
            if !cachedModels.isEmpty {
                return cachedModels
            }
            return KiroModelFallback.visible
        }
    }

    private func fetchModels() async throws -> [String] {
        let accessToken = try await authManager.validAccessToken()
        let profileArn = await authManager.currentProfileArn()

        var components = URLComponents(string: "https://q.us-east-1.amazonaws.com/ListAvailableModels")!
        var queryItems = [URLQueryItem(name: "origin", value: "AI_EDITOR")]
        if let profileArn, !profileArn.isEmpty {
            queryItems.append(URLQueryItem(name: "profileArn", value: profileArn))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw ProxyError.upstream("Could not build Kiro model list URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "aws-sdk-js/1.0.27 ua/2.1 os/macos lang/swift api/codewhispererstreaming#1.0.27 Orches KiroIDE-0.7.45-\(MachineFingerprint.value)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(
            "aws-sdk-js/1.0.27 Orches KiroIDE-0.7.45-\(MachineFingerprint.value)",
            forHTTPHeaderField: "x-amz-user-agent"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProxyError.upstream("Kiro models returned no HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "empty body"
            throw ProxyError.upstream("Kiro models failed (\(http.statusCode)): \(body)")
        }

        let object = try JSONUtilities.object(from: data)
        guard let modelObjects = object["models"] as? [[String: Any]] else {
            throw ProxyError.upstream("Kiro models response missing models.")
        }

        let ids = modelObjects.compactMap { $0["modelId"] as? String }
            .filter { !$0.isEmpty }
        guard !ids.isEmpty else {
            throw ProxyError.upstream("Kiro models response was empty.")
        }
        return ids
    }
}

enum KiroModelFallback {
    static let visible = [
        "auto",
        "claude-opus-4.7",
        "claude-opus-4.6",
        "claude-sonnet-4.6",
        "claude-opus-4.5",
        "claude-sonnet-4.5",
        "claude-sonnet-4",
        "claude-haiku-4.5",
        "deepseek-3.2",
        "minimax-m2.5",
        "minimax-m2.1",
        "glm-5",
        "qwen3-coder-next",
    ]
}
