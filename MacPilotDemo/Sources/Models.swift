import Foundation


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
