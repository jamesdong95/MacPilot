import Foundation
import Security


enum AppSection: String, CaseIterable, Hashable, Identifiable {
    case search
    case suggestions
    case activity
    case duplicates
    case storage

    var id: Self { self }

    var title: String {
        switch self {
        case .search: return L10n.t("search")
        case .suggestions: return L10n.t("suggestions")
        case .activity: return L10n.t("activity")
        case .duplicates: return L10n.t("duplicates")
        case .storage: return L10n.t("storage")
        }
    }

    var subtitle: String {
        switch self {
        case .search: return L10n.t("search.subtitle")
        case .suggestions: return L10n.t("suggestions.subtitle")
        case .activity: return L10n.t("activity.subtitle")
        case .duplicates: return L10n.t("duplicates.subtitle")
        case .storage: return L10n.t("storage.subtitle")
        }
    }

    var icon: String {
        switch self {
        case .search: return "magnifyingglass"
        case .suggestions: return "sparkles"
        case .activity: return "clock.arrow.circlepath"
        case .duplicates: return "doc.on.doc"
        case .storage: return "internaldrive"
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

struct DuplicateGroup: Identifiable, Hashable {
    let id: String
    let size: Int
    let paths: [String]

    var sizeString: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    /// All but the first path (the kept copy) are the surplus copies.
    var surplusPaths: [String] {
        Array(paths.dropFirst())
    }
}

struct StorageEntry: Identifiable, Hashable {
    let id: String
    let path: String
    let size: Int

    var sizeString: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    var name: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

struct StorageReport {
    let totalFiles: Int
    let totalSize: Int
    let largest: [StorageEntry]
    let oldest: [StorageEntry]
    let screenshots: [StorageEntry]

    var totalSizeString: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)
    }
}

struct BatchSummary: Identifiable {
    let id: String
    let name: String
    let summary: String
}

struct SavedSearch: Identifiable, Hashable {
    let id: Int
    let name: String
    let query: String
}

/// Minimal runtime localization (English + Vietnamese) without an .xcstrings
/// catalog, so the app can switch languages without a rebuild.
enum L10n {
    static let languageKey = "macpilot.language"

    static var language: String {
        UserDefaults.standard.string(forKey: languageKey) ?? "en"
    }

    static func setLanguage(_ code: String) {
        UserDefaults.standard.set(code, forKey: languageKey)
    }

    static func t(_ key: String) -> String {
        table[key]?[language] ?? table[key]?["en"] ?? key
    }

    private static let table: [String: [String: String]] = [
        "search": ["en": "Search", "vi": "Tìm kiếm"],
        "search.subtitle": ["en": "Find files instantly", "vi": "Tìm file tức thì"],
        "suggestions": ["en": "Suggestions", "vi": "Gợi ý"],
        "suggestions.subtitle": ["en": "Review move previews", "vi": "Xem trước di chuyển"],
        "activity": ["en": "Activity", "vi": "Hoạt động"],
        "activity.subtitle": ["en": "Local action history", "vi": "Lịch sử hành động"],
        "duplicates": ["en": "Duplicates", "vi": "Trùng lặp"],
        "duplicates.subtitle": ["en": "Reclaim space safely", "vi": "Giải phóng dung lượng an toàn"],
        "storage": ["en": "Storage", "vi": "Dung lượng"],
        "storage.subtitle": ["en": "See what's using space", "vi": "Xem thứ gì đang chiếm chỗ"],
        "choose.folder": ["en": "Choose folder…", "vi": "Chọn thư mục…"],
        "reindex": ["en": "Re-index", "vi": "Đánh chỉ mục lại"],
        "settings": ["en": "Settings", "vi": "Cài đặt"],
        "summarize": ["en": "Summarize", "vi": "Tóm tắt"],
        "save": ["en": "Save", "vi": "Lưu"],
        "cancel": ["en": "Cancel", "vi": "Hủy"],
        "done": ["en": "Done", "vi": "Xong"],
    ]
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
    let tag: String?

    init(
        id: String? = nil,
        name: String,
        path: String,
        kind: String,
        size: String,
        modified: String,
        snippet: String,
        isText: Bool = false,
        modifiedAt: Date? = nil,
        tag: String? = nil
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
        self.tag = tag
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
