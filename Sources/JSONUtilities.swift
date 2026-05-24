import Foundation

enum JSONUtilities {
    static func object(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProxyError.badRequest("JSON body must be an object.")
        }
        return object
    }

    static func data(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [])) ?? Data("{}".utf8)
    }

    static func string(_ object: Any) -> String {
        String(data: data(object), encoding: .utf8) ?? "{}"
    }

    static func jsonObjectString(_ object: Any?) -> String {
        guard let object else { return "{}" }
        if let string = object as? String {
            return string.isEmpty ? "{}" : string
        }
        return string(object)
    }

    static func text(from content: Any?) -> String {
        guard let content else { return "" }
        if let string = content as? String {
            return string
        }
        if content is NSNull {
            return ""
        }
        if let blocks = content as? [[String: Any]] {
            return blocks.compactMap { block in
                if let text = block["text"] as? String {
                    return text
                }
                if let nested = block["content"] {
                    return text(from: nested)
                }
                return nil
            }.joined()
        }
        return "\(content)"
    }
}

enum ProxyError: LocalizedError {
    case badRequest(String)
    case unauthorized
    case missingToken
    case upstream(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .badRequest(let message), .upstream(let message), .server(let message):
            return message
        case .unauthorized:
            return "Invalid or missing API key."
        case .missingToken:
            return "Save a Kiro refresh token before starting proxy."
        }
    }
}
