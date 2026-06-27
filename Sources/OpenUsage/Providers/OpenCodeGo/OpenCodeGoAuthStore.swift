import Foundation

struct OpenCodeGoAuthState: Hashable, Sendable {
    var apiKey: String
}

enum OpenCodeGoError: Error, LocalizedError, Equatable {
    case notDetected
    case historyUnavailable

    var errorDescription: String? {
        switch self {
        case .notDetected:
            return "OpenCode Go not detected. Log in with OpenCode Go or use it locally first."
        case .historyUnavailable:
            return "OpenCode Go usage data unavailable. Try again later."
        }
    }
}

struct OpenCodeGoAuthStore: Sendable {
    static let authPath = "~/.local/share/opencode/auth.json"

    var files: TextFileAccessing

    init(files: TextFileAccessing = LocalTextFileAccessor()) {
        self.files = files
    }

    func loadAuth() -> OpenCodeGoAuthState? {
        guard files.exists(Self.authPath),
              let text = try? files.readText(Self.authPath),
              let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = object["opencode-go"] as? [String: Any],
              let key = (entry["key"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty
        else {
            return nil
        }
        return OpenCodeGoAuthState(apiKey: key)
    }
}
