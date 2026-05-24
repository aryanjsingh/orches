import Foundation

struct KiroStreamParser {
    func parse(_ data: Data) -> KiroResponse {
        let text = String(data: data, encoding: .utf8) ?? ""
        var response = KiroResponse(content: "", toolCalls: [], usage: nil)
        var lastContent: String?
        var currentTool: (id: String, name: String, arguments: String)?

        for object in extractJSONObjects(from: text) {
            if let content = object["content"] as? String,
               object["followupPrompt"] == nil,
               content != lastContent {
                response.content += content
                lastContent = content
            }

            if let usage = object["usage"] as? Int {
                response.usage = usage
            }

            if let name = object["name"] as? String {
                if let currentTool {
                    response.toolCalls.append(finalize(currentTool))
                }
                currentTool = (
                    id: object["toolUseId"] as? String ?? UUID().uuidString,
                    name: name,
                    arguments: argumentString(from: object["input"])
                )
            } else if object["input"] != nil, currentTool != nil {
                currentTool?.arguments += argumentString(from: object["input"])
            }

            if (object["stop"] as? Bool) == true, let completedTool = currentTool {
                response.toolCalls.append(finalize(completedTool))
                currentTool = nil
            }
        }

        if let pendingTool = currentTool {
            response.toolCalls.append(finalize(pendingTool))
        }
        return response
    }

    private func finalize(_ tool: (id: String, name: String, arguments: String)) -> KiroToolCall {
        let normalized: String
        if let data = tool.arguments.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) {
            normalized = JSONUtilities.string(object)
        } else {
            normalized = tool.arguments.isEmpty ? "{}" : tool.arguments
        }
        return KiroToolCall(id: tool.id, name: tool.name, arguments: normalized)
    }

    private func argumentString(from value: Any?) -> String {
        guard let value else { return "" }
        if let string = value as? String { return string }
        if value is NSNull { return "" }
        if let dictionary = value as? [String: Any], dictionary.isEmpty { return "" }
        return JSONUtilities.string(value)
    }

    private func extractJSONObjects(from text: String) -> [[String: Any]] {
        var results: [[String: Any]] = []
        var searchIndex = text.startIndex

        while searchIndex < text.endIndex {
            guard let start = text[searchIndex...].firstIndex(of: "{"),
                  let end = matchingBrace(in: text, from: start) else {
                break
            }
            let fragment = String(text[start...end])
            if let data = fragment.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               isKiroEvent(object) {
                results.append(object)
            }
            searchIndex = text.index(after: end)
        }

        return results
    }

    private func isKiroEvent(_ object: [String: Any]) -> Bool {
        object["content"] != nil ||
            object["name"] != nil ||
            object["input"] != nil ||
            object["stop"] != nil ||
            object["usage"] != nil ||
            object["contextUsagePercentage"] != nil
    }

    private func matchingBrace(in text: String, from start: String.Index) -> String.Index? {
        var index = start
        var depth = 0
        var inString = false
        var escaping = false

        while index < text.endIndex {
            let char = text[index]
            if escaping {
                escaping = false
            } else if char == "\\" && inString {
                escaping = true
            } else if char == "\"" {
                inString.toggle()
            } else if !inString {
                if char == "{" {
                    depth += 1
                } else if char == "}" {
                    depth -= 1
                    if depth == 0 {
                        return index
                    }
                }
            }
            index = text.index(after: index)
        }
        return nil
    }
}
