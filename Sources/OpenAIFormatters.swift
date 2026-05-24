import Foundation

enum OpenAIResponseFormatter {
    static func response(for kiro: KiroResponse, model: String) -> [String: Any] {
        let message: [String: Any] = [
            "role": "assistant",
            "content": kiro.toolCalls.isEmpty ? kiro.content : NSNull(),
            "tool_calls": kiro.toolCalls.map(\.openAIObject),
        ]

        return [
            "id": "chatcmpl-\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))",
            "object": "chat.completion",
            "created": Int(Date().timeIntervalSince1970),
            "model": model,
            "choices": [
                [
                    "index": 0,
                    "message": message,
                    "finish_reason": kiro.toolCalls.isEmpty ? "stop" : "tool_calls",
                ],
            ],
            "usage": [
                "prompt_tokens": 0,
                "completion_tokens": max(1, kiro.content.split(separator: " ").count),
                "total_tokens": max(1, kiro.content.split(separator: " ").count),
                "credits_used": kiro.usage ?? 0,
            ],
        ]
    }
}

enum OpenAIStreamFormatter {
    static func events(for kiro: KiroResponse, model: String) -> String {
        let id = "chatcmpl-\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let created = Int(Date().timeIntervalSince1970)
        var events: [String] = []

        events.append(event([
            "id": id,
            "object": "chat.completion.chunk",
            "created": created,
            "model": model,
            "choices": [["index": 0, "delta": ["role": "assistant"], "finish_reason": NSNull()]],
        ]))

        if !kiro.content.isEmpty {
            events.append(event([
                "id": id,
                "object": "chat.completion.chunk",
                "created": created,
                "model": model,
                "choices": [["index": 0, "delta": ["content": kiro.content], "finish_reason": NSNull()]],
            ]))
        }

        if !kiro.toolCalls.isEmpty {
            let calls = kiro.toolCalls.enumerated().map { index, call in
                [
                    "index": index,
                    "id": call.id,
                    "type": "function",
                    "function": [
                        "name": call.name,
                        "arguments": call.arguments,
                    ],
                ] as [String: Any]
            }
            events.append(event([
                "id": id,
                "object": "chat.completion.chunk",
                "created": created,
                "model": model,
                "choices": [["index": 0, "delta": ["tool_calls": calls], "finish_reason": NSNull()]],
            ]))
        }

        events.append(event([
            "id": id,
            "object": "chat.completion.chunk",
            "created": created,
            "model": model,
            "choices": [[
                "index": 0,
                "delta": [:],
                "finish_reason": kiro.toolCalls.isEmpty ? "stop" : "tool_calls",
            ]],
        ]))
        events.append("data: [DONE]\n\n")
        return events.joined()
    }

    private static func event(_ object: [String: Any]) -> String {
        "data: \(JSONUtilities.string(object))\n\n"
    }
}
