import Foundation
import SwiftUI


final class DemoStore: ObservableObject {
    @Published var query = ""
    @Published var selectedSection: AppSection? = .search
    @Published var selectedFile: DemoFile?
    @Published private(set) var files = DemoData.files
    @Published private(set) var suggestions = DemoData.suggestions
    @Published private(set) var actions = DemoData.actions
    @Published private(set) var statusMessage = "Demo mode · no files will be changed"

    var filteredFiles: [DemoFile] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return files }
        return files.filter { file in
            [file.name, file.path, file.kind, file.snippet]
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(term)
        }
    }

    func apply(_ suggestion: DemoSuggestion) {
        guard let index = suggestions.firstIndex(where: { $0.id == suggestion.id }) else { return }
        guard !suggestions[index].isApplied else { return }
        suggestions[index].isApplied = true
        actions.insert(
            ActivityEntry(
                action: "Prepared move",
                detail: "\(suggestion.files.count) files → \(suggestion.destination)",
                date: "Just now"
            ),
            at: 0
        )
        statusMessage = "Preview applied in demo mode · real file actions require confirmation"
    }

    func undo(_ action: ActivityEntry) {
        guard let index = actions.firstIndex(where: { $0.id == action.id }) else { return }
        guard !actions[index].isUndone else { return }
        actions[index].isUndone = true
        statusMessage = "Action marked as undone in demo mode"
    }
}
