import Foundation

struct KiroPayloadBuilder {
    func payload(for request: OpenAIChatRequest, profileArn: String?) throws -> [String: Any] {
        let modelID = normalizeModelID(request.model)
        let normalized = normalize(messages: request.messages)
        guard !normalized.isEmpty else {
            throw ProxyError.badRequest("No messages to send.")
        }

        let historyMessages = Array(normalized.dropLast())
        var current = normalized.last!
        var history = historyMessages.map { historyEntry(from: $0, modelID: modelID) }

        if current.role == "assistant" {
            history.append(historyEntry(from: current, modelID: modelID))
            current = KiroMessage(role: "user", content: "(empty placeholder)")
        }

        var userInput: [String: Any] = [
            "content": current.content.isEmpty ? "(empty placeholder)" : current.content,
            "modelId": modelID,
            "origin": "AI_EDITOR",
        ]

        var context: [String: Any] = [:]
        let tools = request.tools.map(toolSpecification)
        if !tools.isEmpty {
            context["tools"] = tools
        }
        if !current.toolResults.isEmpty {
            context["toolResults"] = current.toolResults
        }
        if !context.isEmpty {
            userInput["userInputMessageContext"] = context
        }

        var conversationState: [String: Any] = [
            "chatTriggerType": "MANUAL",
            "conversationId": UUID().uuidString,
            "currentMessage": ["userInputMessage": userInput],
        ]
        if !history.isEmpty {
            conversationState["history"] = history
        }

        var payload: [String: Any] = ["conversationState": conversationState]
        if let profileArn, !profileArn.isEmpty {
            payload["profileArn"] = profileArn
        }
        return payload
    }

    private func normalizeModelID(_ model: String) -> String {
        if model == "auto-kiro" {
            return "auto"
        }

        let parts = model.split(separator: "-").map(String.init)
        guard parts.count >= 4,
              parts.first == "claude",
              ["haiku", "sonnet", "opus"].contains(parts[1]),
              let major = Int(parts[2]),
              let minor = Int(parts[3]),
              parts[3].count <= 2 else {
            return model
        }

        return "claude-\(parts[1])-\(major).\(minor)"
    }

    private func normalize(messages: [OpenAIMessage]) -> [KiroMessage] {
        var systemParts: [String] = []
        var converted: [KiroMessage] = []
        var pendingToolResults: [[String: Any]] = []

        for message in messages {
            switch message.role {
            case "system", "developer":
                let text = JSONUtilities.text(from: message.content)
                if !text.isEmpty { systemParts.append(text) }
            case "tool":
                pendingToolResults.append([
                    "content": [["text": JSONUtilities.text(from: message.content).isEmpty ? "(empty result)" : JSONUtilities.text(from: message.content)]],
                    "status": "success",
                    "toolUseId": message.toolCallID ?? "",
                ])
            default:
                if !pendingToolResults.isEmpty {
                    converted.append(KiroMessage(role: "user", content: "", toolResults: pendingToolResults))
                    pendingToolResults.removeAll()
                }
                converted.append(
                    KiroMessage(
                        role: message.role == "assistant" ? "assistant" : "user",
                        content: JSONUtilities.text(from: message.content),
                        toolUses: toolUses(from: message.toolCalls)
                    )
                )
            }
        }

        if !pendingToolResults.isEmpty {
            converted.append(KiroMessage(role: "user", content: "", toolResults: pendingToolResults))
        }
        if converted.isEmpty {
            converted.append(KiroMessage(role: "user", content: "(empty placeholder)"))
        }
        if converted.first?.role != "user" {
            converted.insert(KiroMessage(role: "user", content: "(empty placeholder)"), at: 0)
        }
        if !systemParts.isEmpty {
            let system = systemParts.joined(separator: "\n\n")
            converted[0].content = "\(system)\n\n\(converted[0].content)"
        }

        return mergeAdjacent(converted)
    }

    private func mergeAdjacent(_ messages: [KiroMessage]) -> [KiroMessage] {
        var result: [KiroMessage] = []
        for message in messages {
            guard var previous = result.last, previous.role == message.role else {
                result.append(message)
                continue
            }

            previous.content = [previous.content, message.content]
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            previous.toolUses.append(contentsOf: message.toolUses)
            previous.toolResults.append(contentsOf: message.toolResults)
            result[result.count - 1] = previous
        }
        return result
    }

    private func historyEntry(from message: KiroMessage, modelID: String) -> [String: Any] {
        if message.role == "assistant" {
            var response: [String: Any] = ["content": message.content.isEmpty ? "(empty placeholder)" : message.content]
            if !message.toolUses.isEmpty {
                response["toolUses"] = message.toolUses
            }
            return ["assistantResponseMessage": response]
        }

        var userInput: [String: Any] = [
            "content": message.content.isEmpty ? "(empty placeholder)" : message.content,
            "modelId": modelID,
            "origin": "AI_EDITOR",
        ]
        if !message.toolResults.isEmpty {
            userInput["userInputMessageContext"] = ["toolResults": message.toolResults]
        }
        return ["userInputMessage": userInput]
    }

    private func toolSpecification(_ tool: OpenAITool) -> [String: Any] {
        [
            "toolSpecification": [
                "name": String(tool.name.prefix(64)),
                "description": tool.description,
                "inputSchema": ["json": tool.parameters],
            ],
        ]
    }

    private func toolUses(from toolCalls: [[String: Any]]) -> [[String: Any]] {
        toolCalls.compactMap { call in
            guard let function = call["function"] as? [String: Any],
                  let name = function["name"] as? String else {
                return nil
            }
            let rawArguments = function["arguments"]
            let argumentsData = JSONUtilities.jsonObjectString(rawArguments)
            let input = (try? JSONUtilities.object(from: Data(argumentsData.utf8))) ?? [:]
            return [
                "name": name,
                "input": input,
                "toolUseId": call["id"] as? String ?? UUID().uuidString,
            ]
        }
    }
}

struct KiroMessage {
    var role: String
    var content: String
    var toolUses: [[String: Any]] = []
    var toolResults: [[String: Any]] = []
}
