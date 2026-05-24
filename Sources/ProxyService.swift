import Foundation
import AppKit

enum ProxyRunStatus: Equatable {
    case stopped
    case starting
    case running(port: Int)
    case failed(String)

    var title: String {
        switch self {
        case .stopped: return "Stopped"
        case .starting: return "Starting"
        case .running: return "Running"
        case .failed: return "Failed"
        }
    }
}

final class ProxyService {
    private let keychain = KeychainStore()
    private let server = EmbeddedProxyServer()
    private lazy var authManager = KiroAuthManager(keychain: keychain)
    private var apiKeyCache: String?
    private(set) var authMessage = "Kiro auth will auto-detect from Keychain when proxy starts." {
        didSet { notify() }
    }

    private(set) var status: ProxyRunStatus = .stopped {
        didSet { notify() }
    }
    var onChange: (() -> Void)?

    var hasToken: Bool {
        get async { await authManager.hasRefreshToken }
    }

    var currentAPIKey: String {
        if let apiKeyCache { return apiKeyCache }
        let key: String
        if let existing = keychain.string(for: "proxy-api-key"), !existing.isEmpty {
            key = existing
        } else {
            key = "orches-\(SecureTokenGenerator.makeAPIKey())"
            try? keychain.set(key, for: "proxy-api-key")
        }
        apiKeyCache = key
        return key
    }

    var baseURL: String? {
        if case .running(let port) = status {
            return "http://127.0.0.1:\(port)/v1"
        }
        return nil
    }

    func saveToken(_ token: String) async throws {
        try await authManager.saveRefreshToken(token)
        authMessage = "Manual Kiro token saved in Keychain."
        notify()
    }

    func autoDetectKiroAuth() async throws {
        let summary = try await authManager.importFromKiroKeychain()
        authMessage = summary.userMessage
        notify()
    }

    func start() {
        guard case .running = status else {
            status = .starting
            Task.detached(priority: .userInitiated) { [weak self] in
                await self?.startServer()
            }
            return
        }
    }

    func stop() {
        server.stop()
        status = .stopped
    }

    func copyBaseURL() {
        guard let baseURL else { return }
        copy(baseURL)
    }

    func copyAPIKey() {
        copy(currentAPIKey)
    }

    private func startServer() async {
        do {
            if let summary = try await authManager.syncFromKiroKeychainIfAvailable() {
                authMessage = summary.userMessage
            }
            guard await authManager.hasRefreshToken else {
                throw ProxyError.missingToken
            }
            let apiKey = try await authManager.apiKey()
            apiKeyCache = apiKey
            let router = OpenAICompatRouter(apiKey: apiKey, authManager: authManager)
            let port = try server.start(router: router)
            await MainActor.run {
                status = .running(port: port)
            }
        } catch {
            await MainActor.run {
                status = .failed(error.localizedDescription)
            }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func notify() {
        DispatchQueue.main.async { [weak self] in
            self?.onChange?()
        }
    }
}
