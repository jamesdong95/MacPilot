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
        case .suggestions: return "Review safe actions"
        case .activity: return "Undoable history"
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

struct DemoFile: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let kind: String
    let size: String
    let modified: String
    let snippet: String

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
    let id = UUID()
    let title: String
    let files: [String]
    let destination: String
    let reason: String
    var isApplied = false
}

struct ActivityEntry: Identifiable, Hashable {
    let id = UUID()
    let action: String
    let detail: String
    let date: String
    var isUndone = false
}

enum DemoData {
    static let files = [
        DemoFile(
            name: "invoice-january.pdf",
            path: "~/Downloads/invoice-january.pdf",
            kind: "PDF",
            size: "1.8 MB",
            modified: "Today, 09:42",
            snippet: "January project invoice and payment terms."
        ),
        DemoFile(
            name: "invoice-february.pdf",
            path: "~/Downloads/invoice-february.pdf",
            kind: "PDF",
            size: "2.1 MB",
            modified: "Yesterday, 16:18",
            snippet: "February project invoice and payment terms."
        ),
        DemoFile(
            name: "project-launch-checklist.md",
            path: "~/Downloads/project-launch-checklist.md",
            kind: "Markdown",
            size: "14 KB",
            modified: "Yesterday, 11:07",
            snippet: "Remember the MacPilot launch checklist."
        ),
        DemoFile(
            name: "screen-recording.png",
            path: "~/Downloads/screen-recording.png",
            kind: "Image",
            size: "4.6 MB",
            modified: "Aug 10, 2026",
            snippet: "OCR: settings screen and local model configuration."
        ),
        DemoFile(
            name: "meeting-notes.txt",
            path: "~/Downloads/meeting-notes.txt",
            kind: "Text",
            size: "8 KB",
            modified: "Aug 09, 2026",
            snippet: "Notes from the product planning meeting."
        )
    ]

    static let suggestions = [
        DemoSuggestion(
            title: "Group project invoices",
            files: ["invoice-january.pdf", "invoice-february.pdf"],
            destination: "~/Documents/Invoices",
            reason: "Both files share the invoice keyword and PDF type."
        ),
        DemoSuggestion(
            title: "Move project notes together",
            files: ["project-launch-checklist.md", "meeting-notes.txt"],
            destination: "~/Documents/Project Notes",
            reason: "The content appears related to the same project workspace."
        )
    ]

    static let actions = [
        ActivityEntry(
            action: "Indexed folder",
            detail: "~/Downloads · 248 files · local only",
            date: "Today, 10:04"
        ),
        ActivityEntry(
            action: "Search completed",
            detail: "invoice · 2 matching files",
            date: "Today, 09:58"
        )
    ]
}
