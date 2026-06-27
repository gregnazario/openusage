import Foundation

protocol DirectoryListing: Sendable {
    func listDirectory(_ path: String) throws -> [String]
}

struct LocalDirectoryLister: DirectoryListing {
    func listDirectory(_ path: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: expandHome(path))
    }
}

struct JetBrainsQuotaFile: Hashable, Sendable {
    var path: String
    var text: String
}

enum JetBrainsAIError: Error, LocalizedError, Equatable {
    case notDetected
    case quotaUnavailable

    var errorDescription: String? {
        switch self {
        case .notDetected:
            return "JetBrains AI Assistant not detected. Open a JetBrains IDE with AI Assistant enabled."
        case .quotaUnavailable:
            return "JetBrains AI Assistant quota data unavailable. Open AI Assistant once and try again."
        }
    }
}

struct JetBrainsAIAuthStore: Sendable {
    static let quotaFilename = "AIAssistantQuotaManager2.xml"
    static let basePath = "~/Library/Application Support/JetBrains"
    static let productPrefixes = [
        "Aqua", "AndroidStudio", "CLion", "DataGrip", "DataSpell", "GoLand",
        "IdeaIC", "IntelliJIdea", "IntelliJIdeaCE", "PhpStorm", "PyCharm",
        "PyCharmCE", "Rider", "RubyMine", "RustRover", "WebStorm", "Writerside"
    ]

    var files: TextFileAccessing
    var directories: DirectoryListing

    init(
        files: TextFileAccessing = LocalTextFileAccessor(),
        directories: DirectoryListing = LocalDirectoryLister()
    ) {
        self.files = files
        self.directories = directories
    }

    func loadQuotaFiles() -> [JetBrainsQuotaFile] {
        let entries = (try? directories.listDirectory(Self.basePath)) ?? []
        return entries.compactMap { entry in
            guard Self.isLikelyIDEDirectory(entry) else { return nil }
            let path = "\(Self.basePath)/\(entry)/options/\(Self.quotaFilename)"
            guard files.exists(path),
                  let text = try? files.readText(path)
            else {
                return nil
            }
            return JetBrainsQuotaFile(path: path, text: text)
        }
    }

    static func isLikelyIDEDirectory(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard productPrefixes.contains(where: { trimmed.hasPrefix($0) }) else { return false }
        return trimmed.range(of: #"\d{4}\.\d"#, options: .regularExpression) != nil
    }
}
