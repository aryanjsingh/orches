import Foundation

final class KiroClient {
    private let authManager: KiroAuthManager
    private let parser = KiroStreamParser()

    init(authManager: KiroAuthManager) {
        self.authManager = authManager
    }

    func generate(payload: [String: Any]) async throws -> KiroResponse {
        do {
            return try await send(payload: payload, forceRefresh: false)
        } catch KiroHTTPError.forbidden {
            return try await send(payload: payload, forceRefresh: true)
        }
    }

    private func send(payload: [String: Any], forceRefresh: Bool) async throws -> KiroResponse {
        let token = forceRefresh
            ? try await authManager.forceRefresh()
            : try await authManager.validAccessToken()

        let url = URL(string: "https://runtime.us-east-1.kiro.dev/generateAssistantResponse")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = JSONUtilities.data(payload)

        for (key, value) in headers(accessToken: token) {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProxyError.upstream("Kiro returned no HTTP response.")
        }
        if http.statusCode == 403 {
            throw KiroHTTPError.forbidden
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "empty body"
            throw ProxyError.upstream("Kiro request failed (\(http.statusCode)): \(body)")
        }

        return parser.parse(data)
    }

    private func headers(accessToken: String) -> [String: String] {
        let fingerprint = MachineFingerprint.value
        return [
            "Authorization": "Bearer \(accessToken)",
            "Content-Type": "application/x-amz-json-1.0",
            "x-amz-target": "AmazonCodeWhispererStreamingService.GenerateAssistantResponse",
            "User-Agent": "aws-sdk-js/1.0.27 ua/2.1 os/macos lang/swift api/codewhispererstreaming#1.0.27 Orches KiroIDE-0.7.45-\(fingerprint)",
            "x-amz-user-agent": "aws-sdk-js/1.0.27 Orches KiroIDE-0.7.45-\(fingerprint)",
            "x-amzn-codewhisperer-optout": "true",
            "x-amzn-kiro-agent-mode": "vibe",
            "amz-sdk-invocation-id": UUID().uuidString,
            "amz-sdk-request": "attempt=1; max=2",
        ]
    }
}

private enum KiroHTTPError: Error {
    case forbidden
}
