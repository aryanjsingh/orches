import Foundation
import CryptoKit

actor KiroAuthManager {
    private enum ExternalKeychain {
        static let kiroCLIService = "kirocli:social:token"
    }

    private enum KeychainAccount {
        static let refreshToken = "kiro-refresh-token"
        static let proxyAPIKey = "proxy-api-key"
    }

    private let keychain: KeychainStore
    private let defaults: UserDefaults
    private var accessToken: String?
    private var refreshToken: String?
    private var profileArn: String?
    private var expiresAt: Date?

    init(keychain: KeychainStore, defaults: UserDefaults = .standard) {
        self.keychain = keychain
        self.defaults = defaults
        self.refreshToken = keychain.string(for: KeychainAccount.refreshToken)
        self.profileArn = defaults.string(forKey: "kiro.profileArn")
    }

    var hasRefreshToken: Bool {
        refreshToken?.isEmpty == false
    }

    func importFromKiroKeychain() throws -> KiroCredentialImportSummary {
        guard let rawCredential = KeychainStore.genericPassword(service: ExternalKeychain.kiroCLIService) else {
            throw ProxyError.badRequest("Kiro CLI auth not found in Keychain. Sign in to Kiro first.")
        }

        let credential = try KiroCLIKeychainCredential.decode(rawCredential)
        guard !credential.refreshToken.isEmpty else {
            throw ProxyError.badRequest("Kiro CLI Keychain item has no refresh token.")
        }

        try keychain.set(credential.refreshToken, for: KeychainAccount.refreshToken)
        refreshToken = credential.refreshToken

        let parsedExpiry = credential.expiresAt.flatMap(KiroCLIKeychainCredential.parseExpiry)
        if let access = credential.accessToken, !access.isEmpty,
           let parsedExpiry, parsedExpiry.timeIntervalSinceNow > 120 {
            accessToken = access
            expiresAt = parsedExpiry
        } else {
            accessToken = nil
            expiresAt = nil
        }

        if let arn = credential.profileArn, !arn.isEmpty {
            profileArn = arn
            defaults.set(arn, forKey: "kiro.profileArn")
        }

        return KiroCredentialImportSummary(
            provider: credential.provider,
            profileArn: credential.profileArn,
            hasUsableAccessToken: accessToken != nil
        )
    }

    func syncFromKiroKeychainIfAvailable() throws -> KiroCredentialImportSummary? {
        guard KeychainStore.genericPassword(service: ExternalKeychain.kiroCLIService) != nil else {
            return nil
        }
        return try importFromKiroKeychain()
    }

    func saveRefreshToken(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProxyError.badRequest("Kiro refresh token cannot be empty.")
        }
        try keychain.set(trimmed, for: KeychainAccount.refreshToken)
        refreshToken = trimmed
        accessToken = nil
        expiresAt = nil
    }

    func apiKey() throws -> String {
        if let existing = keychain.string(for: KeychainAccount.proxyAPIKey), !existing.isEmpty {
            return existing
        }
        let generated = "orches-\(SecureTokenGenerator.makeAPIKey())"
        try keychain.set(generated, for: KeychainAccount.proxyAPIKey)
        return generated
    }

    func currentProfileArn() -> String? {
        profileArn
    }

    func validAccessToken() async throws -> String {
        if let accessToken, let expiresAt, expiresAt.timeIntervalSinceNow > 120 {
            return accessToken
        }
        try await refresh()
        guard let accessToken else {
            throw ProxyError.upstream("Kiro auth did not return access token.")
        }
        return accessToken
    }

    func forceRefresh() async throws -> String {
        accessToken = nil
        expiresAt = nil
        return try await validAccessToken()
    }

    private func refresh() async throws {
        guard let refreshToken, !refreshToken.isEmpty else {
            throw ProxyError.missingToken
        }

        let url = URL(string: "https://prod.us-east-1.auth.desktop.kiro.dev/refreshToken")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("KiroIDE-0.7.45-\(MachineFingerprint.value)", forHTTPHeaderField: "User-Agent")
        request.httpBody = JSONUtilities.data(["refreshToken": refreshToken])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProxyError.upstream("Kiro auth returned no HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "empty body"
            throw ProxyError.upstream("Kiro auth failed (\(http.statusCode)): \(body)")
        }

        let object = try JSONUtilities.object(from: data)
        guard let newAccessToken = object["accessToken"] as? String, !newAccessToken.isEmpty else {
            throw ProxyError.upstream("Kiro auth response missing accessToken.")
        }

        accessToken = newAccessToken
        if let newRefreshToken = object["refreshToken"] as? String, !newRefreshToken.isEmpty {
            self.refreshToken = newRefreshToken
            try keychain.set(newRefreshToken, for: KeychainAccount.refreshToken)
        }
        if let newProfileArn = object["profileArn"] as? String, !newProfileArn.isEmpty {
            profileArn = newProfileArn
            defaults.set(newProfileArn, forKey: "kiro.profileArn")
        }

        let expiresIn = object["expiresIn"] as? TimeInterval ?? 3600
        expiresAt = Date().addingTimeInterval(max(60, expiresIn - 60))
    }
}

enum MachineFingerprint {
    static let value: String = {
        let base = "\(Host.current().localizedName ?? "mac")-\(NSUserName())-orches"
        guard let data = base.data(using: .utf8) else {
            return UUID().uuidString
        }
        return SHA256Compat.hexDigest(data)
    }()
}

enum SHA256Compat {
    static func hexDigest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct KiroCredentialImportSummary: Equatable {
    let provider: String?
    let profileArn: String?
    let hasUsableAccessToken: Bool

    var userMessage: String {
        let source = provider?.isEmpty == false ? provider! : "Kiro"
        let tokenState = hasUsableAccessToken ? "access token ready" : "refresh token ready"
        if profileArn?.isEmpty == false {
            return "Auto-detected \(source) auth from Keychain; \(tokenState)."
        }
        return "Auto-detected \(source) auth from Keychain; \(tokenState), no profile ARN."
    }
}

struct KiroCLIKeychainCredential: Decodable, Equatable {
    let accessToken: String?
    let expiresAt: String?
    let refreshToken: String
    let provider: String?
    let profileArn: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresAt = "expires_at"
        case refreshToken = "refresh_token"
        case provider
        case profileArn = "profile_arn"
    }

    static func decode(_ rawCredential: String) throws -> KiroCLIKeychainCredential {
        guard let data = rawCredential.data(using: .utf8) else {
            throw ProxyError.badRequest("Kiro CLI Keychain credential is not valid UTF-8.")
        }
        do {
            return try JSONDecoder().decode(KiroCLIKeychainCredential.self, from: data)
        } catch {
            throw ProxyError.badRequest("Kiro CLI Keychain credential has unsupported format.")
        }
    }

    static func parseExpiry(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
