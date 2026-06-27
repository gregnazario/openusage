import Foundation

struct ZAIAuth: Hashable, Sendable {
    enum Source: Hashable, Sendable {
        case configFile
        case keychain
        case environment
    }

    var apiKey: String
    var source: Source
}

enum ZAIAuthError: Error, LocalizedError, Equatable {
    case missingKey
    case invalidKey
    case saveFailed
    case deleteFailed

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "No Z.ai API key. Add it in Settings, store it in Keychain, or set ZAI_API_KEY."
        case .invalidKey:
            return "Z.ai API key invalid. Check your key at z.ai/manage-apikey/apikey-list."
        case .saveFailed:
            return "Couldn't save the Z.ai API key."
        case .deleteFailed:
            return "Couldn't remove the saved Z.ai API key."
        }
    }
}

/// Reads a [Z.ai](https://z.ai) (Zhipu AI) API key the user has already placed on the machine. Like
/// OpenRouter, Z.ai has no companion CLI/app that stashes a credential in a known spot, so the key
/// comes from a small config file, the macOS Keychain, or an environment variable. A GUI app launched
/// from Finder/Dock doesn't inherit the interactive shell environment, so `ProcessEnvironmentReader`
/// captures the login shell's environment at launch (see `LoginShellEnvironment`) — meaning an env var
/// exported in a shell profile is honored even in a packaged build; the config file remains the
/// explicit override path.
///
/// `ZAI_API_KEY` is the primary env name; `GLM_API_KEY` is accepted as a fallback (the older Zhipu name
/// some users still export), mirroring the legacy plugin's lookup order.
struct ZAIAuthStore: Sendable {
    /// Config files checked in order; first readable key wins. JSON (`apiKey` / `api_key` / `key`) or a
    /// plain-text file containing only the key.
    static let configPaths = [
        "~/.config/openusage/zai.json",
        "~/.config/zai/key.json"
    ]
    /// Keychain service names checked in order. `OpenUsage-zai` is the canonical service; the rest are
    /// compatibility names from older local setups.
    static let keychainServices = ["OpenUsage-zai", "ZAI_API_KEY", "GLM_API_KEY", "zai", "z.ai"]
    /// Environment variables checked in order. `ZAI_API_KEY` is current; `GLM_API_KEY` is the legacy
    /// Zhipu name some users still have exported.
    static let environmentNames = ["ZAI_API_KEY", "GLM_API_KEY"]

    var files: TextFileAccessing
    var environment: EnvironmentReading
    var keychain: KeychainAccessing

    init(
        files: TextFileAccessing = LocalTextFileAccessor(),
        environment: EnvironmentReading = ProcessEnvironmentReader(),
        keychain: KeychainAccessing = SecurityKeychainAccessor()
    ) {
        self.files = files
        self.environment = environment
        self.keychain = keychain
    }

    /// Config file first, Keychain second, environment third. The config path is the explicit override
    /// Settings writes, so it wins over stale machine-level credentials.
    func loadAPIKey() -> ZAIAuth? {
        if let key = keyFromConfigFile() {
            return ZAIAuth(apiKey: key, source: .configFile)
        }
        if let key = keyFromKeychain() {
            return ZAIAuth(apiKey: key, source: .keychain)
        }
        if let key = keyFromEnvironment() {
            return ZAIAuth(apiKey: key, source: .environment)
        }
        return nil
    }

    /// The effective key currently in use (config > Keychain > env), surfaced for the Settings ▸ API
    /// Keys reveal toggle. `nil` when no key is present.
    func currentAPIKey() -> String? {
        loadAPIKey()?.apiKey
    }

    /// Which combination of sources currently holds a key — drives the four-state API Keys card.
    /// A saved key plus a Keychain/env key is `overrideActive` because config wins.
    func keyStatus() -> APIKeyStatus {
        let hasConfig = keyFromConfigFile() != nil
        let hasExternal = keyFromKeychain() != nil || keyFromEnvironment() != nil
        switch (hasConfig, hasExternal) {
        case (true, true): return .overrideActive
        case (true, false): return .saved
        case (false, true): return .fromEnvironment
        default: return .notSet
        }
    }

    /// Persist `key` to the primary config file the auth store already reads, as JSON
    /// `{"apiKey":"…"}`. A saved key automatically wins over a stale Keychain/env key (config is checked
    /// first), so this is also the "override" path. Empty input is rejected as `missingKey`.
    func saveAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ZAIAuthError.missingKey }
        let data = try JSONSerialization.data(withJSONObject: ["apiKey": trimmed], options: [.sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else { throw ZAIAuthError.saveFailed }
        do {
            try files.writeText(Self.configPaths[0], text)
        } catch {
            AppLog.error(.auth, "save API key to \(Self.configPaths[0]) failed: \(error.localizedDescription)")
            throw ZAIAuthError.saveFailed
        }
    }

    /// Remove the saved key from every config file the auth store reads, so clearing truly clears
    /// the key — not just the primary file. Without this, a key held in the alternate config path
    /// (`~/.config/zai/key.json`) would resurface after the primary file is deleted, so the Settings
    /// "clear" would appear not to work. A missing file is a no-op. If a Keychain/env key remains,
    /// `keyStatus()` then reports `fromEnvironment` (the dashboard falls back to it on the next
    /// refresh).
    func deleteAPIKey() throws {
        for path in Self.configPaths {
            guard files.exists(path) else { continue }
            do {
                try files.remove(path)
            } catch {
                AppLog.error(.auth, "delete API key at \(path) failed: \(error.localizedDescription)")
                throw ZAIAuthError.deleteFailed
            }
        }
    }

    private func keyFromEnvironment() -> String? {
        for name in Self.environmentNames {
            if let value = environment.value(for: name)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func keyFromKeychain() -> String? {
        for service in Self.keychainServices {
            guard let raw = try? keychain.readGenericPassword(service: service),
                  let apiKey = Self.apiKey(from: raw)
            else {
                continue
            }
            return apiKey
        }
        return nil
    }

    private func keyFromConfigFile() -> String? {
        for path in Self.configPaths {
            guard files.exists(path), let text = try? files.readText(path) else { continue }
            if let key = Self.keyFromConfigText(text) {
                return key
            }
        }
        return nil
    }

    /// Accept a JSON object with `apiKey` / `api_key` / `key` / `token`, or a plain-text file holding
    /// only the key.
    static func keyFromConfigText(_ text: String) -> String? {
        apiKey(from: text)
    }

    static func apiKey(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let data = trimmed.data(using: .utf8),
           let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            for field in ["apiKey", "api_key", "key", "token"] {
                if let value = (object[field] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !value.isEmpty {
                    return value
                }
            }
            return nil
        }

        // Not JSON: treat as a plain-text key file, ignoring blank lines.
        return trimmed.contains("{") ? nil : trimmed
    }
}
