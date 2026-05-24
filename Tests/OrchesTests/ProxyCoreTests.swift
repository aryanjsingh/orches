import XCTest
@testable import Orches

final class ProxyCoreTests: XCTestCase {
    func testKiroPayloadBuilderIncludesCurrentMessageAndTools() throws {
        let request = try OpenAIChatRequest(json: [
            "model": "claude-sonnet-4-5",
            "messages": [
                ["role": "system", "content": "Be brief."],
                ["role": "user", "content": "Hello"],
            ],
            "tools": [
                [
                    "type": "function",
                    "function": [
                        "name": "lookup",
                        "description": "Lookup value",
                        "parameters": ["type": "object", "properties": ["q": ["type": "string"]]],
                    ],
                ],
            ],
        ])

        let payload = try KiroPayloadBuilder().payload(for: request, profileArn: "arn:test")
        let state = try XCTUnwrap(payload["conversationState"] as? [String: Any])
        let current = try XCTUnwrap(state["currentMessage"] as? [String: Any])
        let user = try XCTUnwrap(current["userInputMessage"] as? [String: Any])

        XCTAssertEqual(user["modelId"] as? String, "claude-sonnet-4.5")
        XCTAssertTrue((user["content"] as? String ?? "").contains("Be brief."))
        XCTAssertNotNil((user["userInputMessageContext"] as? [String: Any])?["tools"])
        XCTAssertEqual(payload["profileArn"] as? String, "arn:test")
    }

    func testStreamParserExtractsContentAndToolCall() {
        let raw = """
        noise{"content":"Hi "}noise{"content":"there"}noise{"name":"lookup","toolUseId":"call_1","input":{}}noise{"input":"{\\"q\\":\\"x\\"}"}noise{"stop":true}
        """
        let parsed = KiroStreamParser().parse(Data(raw.utf8))

        XCTAssertEqual(parsed.content, "Hi there")
        XCTAssertEqual(parsed.toolCalls.first?.id, "call_1")
        XCTAssertEqual(parsed.toolCalls.first?.name, "lookup")
        XCTAssertEqual(parsed.toolCalls.first?.arguments, #"{"q":"x"}"#)
    }

    func testSSEFormatterEmitsDoneMarker() {
        let response = KiroResponse(content: "Hello", toolCalls: [], usage: nil)
        let events = OpenAIStreamFormatter.events(for: response, model: "auto")

        XCTAssertTrue(events.contains("chat.completion.chunk"))
        XCTAssertTrue(events.contains("Hello"))
        XCTAssertTrue(events.contains("data: [DONE]"))
    }

    func testKeychainRoundTrip() throws {
        let account = "token-\(UUID().uuidString)"
        let store = KeychainStore(service: "studio.ships.Orches.Tests")
        defer { store.delete(account: account) }

        try store.set("secret-value", for: account)
        XCTAssertEqual(store.string(for: account), "secret-value")
    }

    func testKiroCLIKeychainCredentialDecodesSnakeCaseFields() throws {
        let raw = """
        {
          "access_token": "access",
          "expires_at": "2099-01-01T00:00:00.000Z",
          "refresh_token": "refresh",
          "provider": "social",
          "profile_arn": "arn:test"
        }
        """

        let credential = try KiroCLIKeychainCredential.decode(raw)

        XCTAssertEqual(credential.accessToken, "access")
        XCTAssertEqual(credential.refreshToken, "refresh")
        XCTAssertEqual(credential.provider, "social")
        XCTAssertEqual(credential.profileArn, "arn:test")
        XCTAssertNotNil(KiroCLIKeychainCredential.parseExpiry(credential.expiresAt ?? ""))
    }

    func testLiveKiroKeychainImportAndLocalProxyWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["ORCHES_LIVE_KIRO"] == "1" else {
            throw XCTSkip("Set ORCHES_LIVE_KIRO=1 to verify local Kiro Keychain auth.")
        }

        let store = KeychainStore(service: "studio.ships.Orches.LiveTests")
        defer {
            store.delete(account: "kiro-refresh-token")
            store.delete(account: "proxy-api-key")
        }

        let authManager = KiroAuthManager(keychain: store)
        let summary = try await authManager.importFromKiroKeychain()
        XCTAssertNotNil(summary.profileArn)
        let refreshedAccessToken = try await authManager.forceRefresh()
        XCTAssertFalse(refreshedAccessToken.isEmpty)

        let apiKey = try await authManager.apiKey()
        let router = OpenAICompatRouter(apiKey: apiKey, authManager: authManager)
        let server = EmbeddedProxyServer()
        let port = try server.start(router: router)
        defer { server.stop() }

        let healthURL = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/health"))
        let (healthData, healthResponse) = try await URLSession.shared.data(from: healthURL)
        XCTAssertEqual((healthResponse as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue((String(data: healthData, encoding: .utf8) ?? "").contains("healthy"))

        let modelsURL = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/models"))
        var modelsRequest = URLRequest(url: modelsURL)
        modelsRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (_, modelsResponse) = try await URLSession.shared.data(for: modelsRequest)
        XCTAssertEqual((modelsResponse as? HTTPURLResponse)?.statusCode, 200)

        var invalidRequest = URLRequest(url: modelsURL)
        invalidRequest.setValue("Bearer invalid", forHTTPHeaderField: "Authorization")
        let (_, invalidResponse) = try await URLSession.shared.data(for: invalidRequest)
        XCTAssertEqual((invalidResponse as? HTTPURLResponse)?.statusCode, 401)
    }
}
