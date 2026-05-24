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
}
