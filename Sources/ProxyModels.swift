import Foundation

struct ProxyHTTPResponse {
    let status: Int
    let headers: [(String, String)]
    let body: Data

    static func json(status: Int = 200, _ object: Any) -> ProxyHTTPResponse {
        ProxyHTTPResponse(
            status: status,
            headers: [("Content-Type", "application/json")],
            body: JSONUtilities.data(object)
        )
    }

    static func text(status: Int, _ message: String) -> ProxyHTTPResponse {
        ProxyHTTPResponse(
            status: status,
            headers: [("Content-Type", "text/plain; charset=utf-8")],
            body: Data(message.utf8)
        )
    }

    static func sse(_ events: String) -> ProxyHTTPResponse {
        ProxyHTTPResponse(
            status: 200,
            headers: [
                ("Content-Type", "text/event-stream; charset=utf-8"),
                ("Cache-Control", "no-cache"),
                ("X-Accel-Buffering", "no"),
            ],
            body: Data(events.utf8)
        )
    }
}

struct OpenAIChatRequest {
    let model: String
    let messages: [OpenAIMessage]
    let stream: Bool
    let tools: [OpenAITool]

    init(json: [String: Any]) throws {
        guard let model = json["model"] as? String, !model.isEmpty else {
            throw ProxyError.badRequest("Missing required field: model.")
        }
        guard let rawMessages = json["messages"] as? [[String: Any]], !rawMessages.isEmpty else {
            throw ProxyError.badRequest("Missing required field: messages.")
        }

        self.model = model
        self.messages = try rawMessages.map(OpenAIMessage.init(json:))
        self.stream = (json["stream"] as? Bool) ?? false
        self.tools = (json["tools"] as? [[String: Any]] ?? []).compactMap(OpenAITool.init(json:))
    }
}

struct OpenAIMessage {
    let role: String
    let content: Any?
    let toolCallID: String?
    let toolCalls: [[String: Any]]

    init(json: [String: Any]) throws {
        guard let role = json["role"] as? String, !role.isEmpty else {
            throw ProxyError.badRequest("Message missing role.")
        }
        self.role = role
        self.content = json["content"]
        self.toolCallID = json["tool_call_id"] as? String
        self.toolCalls = json["tool_calls"] as? [[String: Any]] ?? []
    }
}

struct OpenAITool {
    let name: String
    let description: String
    let parameters: [String: Any]

    init?(json: [String: Any]) {
        guard (json["type"] as? String) == "function",
              let function = json["function"] as? [String: Any],
              let name = function["name"] as? String,
              !name.isEmpty else {
            return nil
        }
        self.name = name
        self.description = (function["description"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Tool: \(name)"
        self.parameters = function["parameters"] as? [String: Any] ?? ["type": "object", "properties": [:]]
    }
}

struct KiroToolCall {
    let id: String
    let name: String
    let arguments: String

    var openAIObject: [String: Any] {
        [
            "id": id,
            "type": "function",
            "function": [
                "name": name,
                "arguments": arguments,
            ],
        ]
    }
}

struct KiroResponse {
    var content: String
    var toolCalls: [KiroToolCall]
    var usage: Int?
}
