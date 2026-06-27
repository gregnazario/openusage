import CryptoKit
import Foundation

struct FactoryAuth: Codable, Hashable, Sendable {
    var accessToken: String?
    var refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

struct FactoryAuthState: Hashable, Sendable {
    enum Source: Hashable, Sendable {
        case fileV2(path: String, key: String)
        case file(path: String)
        case keychain(service: String)
    }

    var auth: FactoryAuth
    var source: Source
}

enum FactoryAuthError: Error, LocalizedError, Equatable {
    case notLoggedIn
    case invalidAuthFile
    case sessionExpired

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "Not logged in. Run `droid` to authenticate."
        case .invalidAuthFile:
            return "Invalid auth file. Run `droid` to authenticate."
        case .sessionExpired:
            return "Session expired. Run `droid` to log in again."
        }
    }
}

struct FactoryAuthStore: Sendable {
    static let authV2Path = "~/.factory/auth.v2.file"
    static let authV2KeyPath = "~/.factory/auth.v2.key"
    static let authPaths = ["~/.factory/auth.encrypted", "~/.factory/auth.json"]
    static let keychainServices = ["Factory Token", "Factory token", "Factory Auth", "Droid Auth"]
    static let refreshBuffer: TimeInterval = 24 * 60 * 60

    var files: TextFileAccessing
    var keychain: KeychainAccessing
    var now: @Sendable () -> Date

    init(
        files: TextFileAccessing = LocalTextFileAccessor(),
        keychain: KeychainAccessing = SecurityKeychainAccessor(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.files = files
        self.keychain = keychain
        self.now = now
    }

    func loadAuth() -> FactoryAuthState? {
        loadV2File() ?? loadLegacyFile() ?? loadKeychain()
    }

    func needsRefresh(_ accessToken: String) -> Bool {
        guard let expiry = tokenExpiry(accessToken) else { return true }
        return expiry.timeIntervalSince(now()) <= Self.refreshBuffer
    }

    func canUseExistingToken(_ accessToken: String) -> Bool {
        guard let expiry = tokenExpiry(accessToken) else { return true }
        return now() < expiry
    }

    func save(_ state: FactoryAuthState) {
        guard let text = (try? JSONEncoder().encode(state.auth))?.prettyJSONString else { return }
        do {
            switch state.source {
            case .fileV2(let path, let key):
                if let encrypted = Self.encryptAES256GCM(text, key: key) {
                    try files.writeText(path, encrypted)
                }
            case .file(let path):
                try files.writeText(path, text)
            case .keychain(let service):
                try keychain.writeGenericPassword(service: service, value: text)
            }
        } catch {
            AppLog.warn(LogTag.auth("factory"), "Factory auth persistence failed: \(error.localizedDescription)")
        }
    }

    private func loadV2File() -> FactoryAuthState? {
        guard files.exists(Self.authV2Path),
              files.exists(Self.authV2KeyPath),
              let envelope = try? files.readText(Self.authV2Path),
              let key = try? files.readText(Self.authV2KeyPath),
              let decrypted = Self.decryptAES256GCM(envelope, key: key),
              let auth = Self.parseAuth(decrypted, allowPartial: true)
        else {
            return nil
        }
        return FactoryAuthState(auth: auth, source: .fileV2(path: Self.authV2Path, key: key))
    }

    private func loadLegacyFile() -> FactoryAuthState? {
        for path in Self.authPaths {
            guard files.exists(path),
                  let text = try? files.readText(path),
                  let auth = Self.parseAuth(text, allowPartial: true)
            else {
                continue
            }
            return FactoryAuthState(auth: auth, source: .file(path: path))
        }
        return nil
    }

    private func loadKeychain() -> FactoryAuthState? {
        for service in Self.keychainServices {
            guard let text = try? keychain.readGenericPassword(service: service),
                  let auth = Self.parseAuth(text, allowPartial: false)
            else {
                continue
            }
            return FactoryAuthState(auth: auth, source: .keychain(service: service))
        }
        return nil
    }

    private func tokenExpiry(_ token: String) -> Date? {
        guard let exp = ProviderParse.jwtPayload(token)?["exp"].flatMap(ProviderParse.number) else {
            return nil
        }
        return Date(timeIntervalSince1970: exp)
    }

    static func parseAuth(_ text: String, allowPartial: Bool) -> FactoryAuth? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if looksLikeJWT(trimmed) {
            return FactoryAuth(accessToken: trimmed, refreshToken: nil)
        }
        if let jsonString = ProviderParse.decodeJSONWithHexFallback(trimmed, as: String.self),
           looksLikeJWT(jsonString) {
            return FactoryAuth(accessToken: jsonString, refreshToken: nil)
        }
        if let payload = ProviderParse.decodeJSONWithHexFallback(trimmed, as: FactoryRawAuth.self) {
            let access = payload.accessToken ?? payload.accessTokenCamel ?? payload.tokens?.accessToken ?? payload.tokens?.accessTokenCamel
            let refresh = payload.refreshToken ?? payload.refreshTokenCamel ?? payload.tokens?.refreshToken ?? payload.tokens?.refreshTokenCamel
            if access?.isEmpty == false || (allowPartial && refresh?.isEmpty == false) {
                return FactoryAuth(accessToken: access?.nilIfEmpty, refreshToken: refresh?.nilIfEmpty)
            }
        }
        return nil
    }

    static func decryptAES256GCM(_ envelope: String, key: String) -> String? {
        let parts = envelope.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":").map(String.init)
        guard parts.count == 3,
              let nonceData = Data(base64Encoded: parts[0]),
              let tag = Data(base64Encoded: parts[1]),
              let ciphertext = Data(base64Encoded: parts[2]),
              let keyData = Data(base64Encoded: key.trimmingCharacters(in: .whitespacesAndNewlines)),
              keyData.count == 32,
              let nonce = try? AES.GCM.Nonce(data: nonceData),
              let opened = try? AES.GCM.open(
                AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag),
                using: SymmetricKey(data: keyData)
              )
        else {
            return nil
        }
        return String(data: opened, encoding: .utf8)
    }

    static func encryptAES256GCM(_ text: String, key: String) -> String? {
        guard let keyData = Data(base64Encoded: key.trimmingCharacters(in: .whitespacesAndNewlines)),
              keyData.count == 32,
              let sealed = try? AES.GCM.seal(Data(text.utf8), using: SymmetricKey(data: keyData))
        else {
            return nil
        }
        return [
            sealed.nonce.withUnsafeBytes { Data($0).base64EncodedString() },
            sealed.tag.base64EncodedString(),
            sealed.ciphertext.base64EncodedString()
        ].joined(separator: ":")
    }

    private static func looksLikeJWT(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+$"#, options: .regularExpression) != nil
    }
}

private struct FactoryRawAuth: Decodable {
    var accessToken: String?
    var accessTokenCamel: String?
    var refreshToken: String?
    var refreshTokenCamel: String?
    var tokens: FactoryRawTokens?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case accessTokenCamel = "accessToken"
        case refreshToken = "refresh_token"
        case refreshTokenCamel = "refreshToken"
        case tokens
    }
}

private struct FactoryRawTokens: Decodable {
    var accessToken: String?
    var accessTokenCamel: String?
    var refreshToken: String?
    var refreshTokenCamel: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case accessTokenCamel = "accessToken"
        case refreshToken = "refresh_token"
        case refreshTokenCamel = "refreshToken"
    }
}

private extension Data {
    var prettyJSONString: String? {
        guard let object = try? JSONSerialization.jsonObject(with: self),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        else {
            return String(data: self, encoding: .utf8)
        }
        return String(data: data, encoding: .utf8)
    }
}
