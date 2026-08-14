import Foundation
import Security


enum AppSection: String, CaseIterable, Hashable, Identifiable {
    case search
    case suggestions
    case activity

    var id: Self { self }

    var title: String {
        switch self {
        case .search: return "Search"
        case .suggestions: return "Suggestions"
        case .activity: return "Activity"
        }
    }

    var subtitle: String {
        switch self {
        case .search: return "Find files instantly"
        case .suggestions: return "Review move previews"
        case .activity: return "Local action history"
        }
    }

    var icon: String {
        switch self {
        case .search: return "magnifyingglass"
        case .suggestions: return "sparkles"
        case .activity: return "clock.arrow.circlepath"
        }
    }
}

enum FileFilter: String, CaseIterable, Identifiable {
    case all
    case content
    case recent

    var id: Self { self }

    var title: String {
        switch self {
        case .all: return "All files"
        case .content: return "Content"
        case .recent: return "Recently changed"
        }
    }
}

struct OrgRule: Identifiable, Hashable {
    let id: Int
    let pattern: String
    let destination: String
}

struct FileSummary: Hashable {
    let fileID: String
    let text: String
}

enum LLMProvider: String, CaseIterable, Identifiable {
    case ollama
    case cloud

    var id: Self { self }

    var title: String {
        switch self {
        case .ollama: return "Local (Ollama)"
        case .cloud: return "Cloud API"
        }
    }
}

/// Append-only local diagnostics log. Opt-in: nothing is ever uploaded.
enum Diagnostics {
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        return f
    }()

    static let logURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/MacPilot", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("macpilot.log")
    }()

    static func log(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            try? handle.write(contentsOf: line.data(using: .utf8) ?? Data())
            try? handle.close()
        } else {
            try? line.data(using: .utf8)?.write(to: logURL)
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: logURL)
    }
}

/// Minimal Keychain wrapper for storing the optional cloud LLM API key.
/// The key is never written to UserDefaults or the repository.
enum KeychainHelper {
    private static let service = "com.calma.macpilot.demo.llm"

    static func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

struct DemoFile: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let kind: String
    let size: String
    let modified: String
    let snippet: String
    let isText: Bool
    let modifiedAt: Date?

    init(
        id: String? = nil,
        name: String,
        path: String,
        kind: String,
        size: String,
        modified: String,
        snippet: String,
        isText: Bool = false,
        modifiedAt: Date? = nil
    ) {
        self.id = id ?? path
        self.name = name
        self.path = path
        self.kind = kind
        self.size = size
        self.modified = modified
        self.snippet = snippet
        self.isText = isText
        self.modifiedAt = modifiedAt
    }

    var icon: String {
        switch kind {
        case "PDF": return "doc.richtext"
        case "Image": return "photo"
        case "Markdown": return "doc.text"
        default: return "doc"
        }
    }
}

struct DemoSuggestion: Identifiable, Hashable {
    let id: String
    let title: String
    let files: [String]
    let sourcePaths: [String]
    let destination: String
    let reason: String
    var isPreviewed = false

    init(
        id: String? = nil,
        title: String,
        files: [String],
        sourcePaths: [String] = [],
        destination: String,
        reason: String,
        isPreviewed: Bool = false
    ) {
        self.id = id ?? "\(destination)::\(title)"
        self.title = title
        self.files = files
        self.sourcePaths = sourcePaths.isEmpty ? files : sourcePaths
        self.destination = destination
        self.reason = reason
        self.isPreviewed = isPreviewed
    }
}

struct ActivityEntry: Identifiable, Hashable {
    let id: String
    let coreActionID: Int?
    let action: String
    let detail: String
    let date: String
    var isUndone = false

    init(
        id: String? = nil,
        coreActionID: Int? = nil,
        action: String,
        detail: String,
        date: String,
        isUndone: Bool = false
    ) {
        self.id = id ?? UUID().uuidString
        self.coreActionID = coreActionID
        self.action = action
        self.detail = detail
        self.date = date
        self.isUndone = isUndone
    }
}
