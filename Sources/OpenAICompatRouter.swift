import Foundation
import NIOHTTP1

final class OpenAICompatRouter {
    private let apiKey: String
    private let authManager: KiroAuthManager
    private let payloadBuilder = KiroPayloadBuilder()
    private lazy var modelCatalog = KiroModelCatalog(authManager: authManager)
    private lazy var kiroClient = KiroClient(authManager: authManager)

    init(apiKey: String, authManager: KiroAuthManager) {
        self.apiKey = apiKey
        self.authManager = authManager
    }

    func handle(method: HTTPMethod, uri: String, headers: HTTPHeaders, body: Data) async -> ProxyHTTPResponse {
        do {
            let path = uri.split(separator: "?", maxSplits: 1).first.map(String.init) ?? uri

            if method == .OPTIONS {
                return cors(status: 204, body: Data())
            }
            if method == .GET && path == "/health" {
                return .json(["status": "healthy", "provider": "kiro"])
            }
            if method == .GET && path == "/v1/models" {
                try authorize(headers)
                return .json(try await modelsResponse())
            }
            if method == .POST && path == "/v1/chat/completions" {
                try authorize(headers)
                return try await chatCompletions(body: body)
            }

            return .json(status: 404, ["error": ["message": "Not found"]])
        } catch ProxyError.unauthorized {
            return .json(status: 401, ["error": ["message": ProxyError.unauthorized.localizedDescription]])
        } catch ProxyError.badRequest(let message) {
            return .json(status: 400, ["error": ["message": message]])
        } catch {
            return .json(status: 502, ["error": ["message": error.localizedDescription]])
        }
    }

    private func authorize(_ headers: HTTPHeaders) throws {
        guard let authorization = headers.first(name: "Authorization"),
              authorization == "Bearer \(apiKey)" else {
            throw ProxyError.unauthorized
        }
    }

    private func chatCompletions(body: Data) async throws -> ProxyHTTPResponse {
        let object = try JSONUtilities.object(from: body)
        let request = try OpenAIChatRequest(json: object)
        _ = try await authManager.validAccessToken()
        let profileArn = await authManager.currentProfileArn()
        let payload = try payloadBuilder.payload(for: request, profileArn: profileArn)
        let kiroResponse = try await kiroClient.generate(payload: payload)

        if request.stream {
            return .sse(OpenAIStreamFormatter.events(for: kiroResponse, model: request.model))
        }
        return .json(OpenAIResponseFormatter.response(for: kiroResponse, model: request.model))
    }

    private func cors(status: Int, body: Data) -> ProxyHTTPResponse {
        ProxyHTTPResponse(
            status: status,
            headers: [
                ("Access-Control-Allow-Origin", "*"),
                ("Access-Control-Allow-Headers", "Authorization, Content-Type"),
                ("Access-Control-Allow-Methods", "GET, POST, OPTIONS"),
            ],
            body: body
        )
    }

    private func modelsResponse() async throws -> [String: Any] {
        let models = try await modelCatalog.models()
        return [
            "object": "list",
            "data": models.map {
                [
                    "id": $0,
                    "object": "model",
                    "created": 0,
                    "owned_by": "kiro",
                ]
            },
        ]
    }
}
