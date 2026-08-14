import AppKit
import Foundation
import SwiftUI


@MainActor
final class DemoStore: ObservableObject {
    @Published var query = "" {
        didSet {
            guard oldValue != query else { return }
            scheduleSearch()
        }
    }
    @Published var selectedSection: AppSection? = .search
    @Published var selectedFile: DemoFile?
    @Published var activeFilter: FileFilter = .all
    @Published private(set) var rules: [OrgRule] = []
    @Published private(set) var fileSummary: FileSummary?
    @Published private(set) var summarizingFile = false
    @Published private(set) var indexProgress: Int?
    @Published private(set) var duplicateGroups: [DuplicateGroup] = []
    @Published var llmProvider: LLMProvider = .ollama
    @Published var cloudBaseURL = ""
    @Published var cloudModel = "gpt-4o-mini"
    @Published var cloudAPIKey = ""
    @Published private(set) var files: [DemoFile] = []
    @Published private(set) var suggestions: [DemoSuggestion] = []
    @Published private(set) var actions: [ActivityEntry] = []
    @Published private(set) var workspacePath: String?
    @Published private(set) var coreStatus: CoreStatus?
    @Published private(set) var isBusy = false
    @Published private(set) var statusMessage: String
    @Published private(set) var recentWorkspaces: [String]

    private(set) var coreDescription: String
    private(set) var client: MacPilotClient?
    private var searchResults: [DemoFile] = []
    private var operationTask: Task<Void, Never>?
    private var securityScopedWorkspaceURL: URL?
    private var lastIndexURL: URL?
    private var lastIndexDate: Date?

    private static let recentWorkspacesKey = "macpilot.recentWorkspaces"
    private static let recentWorkspacesLimit = 8

    init(client: MacPilotClient? = MacPilotClient.discover()) {
        self.client = client
        self.coreDescription = client?.displayName ?? "Local Python core unavailable"
        self.statusMessage = client == nil
            ? "Local core not found · set MACPILOT_PROJECT_ROOT or install macpilot"
            : "Choose a folder to index · no files will be changed"
        self.recentWorkspaces = (UserDefaults.standard
            .stringArray(forKey: Self.recentWorkspacesKey)) ?? []
        self.llmProvider = LLMProvider(
            rawValue: UserDefaults.standard.string(forKey: "macpilot.llmProvider") ?? ""
        ) ?? .ollama
        self.cloudBaseURL = UserDefaults.standard.string(forKey: "macpilot.cloudBaseURL") ?? ""
        self.cloudModel = UserDefaults.standard.string(forKey: "macpilot.cloudModel") ?? "gpt-4o-mini"
        self.cloudAPIKey = KeychainHelper.get("cloudAPIKey") ?? ""
    }

    deinit {
        operationTask?.cancel()
        securityScopedWorkspaceURL?.stopAccessingSecurityScopedResource()
    }

    var filteredFiles: [DemoFile] {
        let base = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? files
            : searchResults
        switch activeFilter {
        case .all:
            return base
        case .content:
            return base.filter { $0.isText }
        case .recent:
            let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
            return base.filter { file in
                guard let modifiedAt = file.modifiedAt else { return false }
                return modifiedAt >= cutoff
            }
        }
    }

    var hasCore: Bool {
        client != nil
    }

    /// Path of the local SQLite index the core reads and writes.
    var databasePath: String? {
        client?.databaseURL.path
    }

    func clearRecentWorkspaces() {
        recentWorkspaces = []
        UserDefaults.standard.removeObject(forKey: Self.recentWorkspacesKey)
    }

    /// Core-path and database-path overrides persisted in UserDefaults.
    var configuredCliPath: String? {
        UserDefaults.standard.string(forKey: "macpilot.cliPath")
    }

    var configuredDatabasePath: String? {
        UserDefaults.standard.string(forKey: "macpilot.dbPath")
    }

    /// Persist new core/database paths, re-discover the client, and re-index
    /// the current folder if one was already chosen.
    func reconfigure(cliPath: String, databasePath: String) {
        let cli = cliPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let db = databasePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if cli.isEmpty {
            UserDefaults.standard.removeObject(forKey: "macpilot.cliPath")
        } else {
            UserDefaults.standard.set(cli, forKey: "macpilot.cliPath")
        }
        if db.isEmpty {
            UserDefaults.standard.removeObject(forKey: "macpilot.dbPath")
        } else {
            UserDefaults.standard.set(db, forKey: "macpilot.dbPath")
        }

        client = MacPilotClient.discover()
        coreDescription = client?.displayName ?? "Local Python core unavailable"

        if client == nil {
            statusMessage = "Local core not found · check the core path in Settings"
        } else if let current = workspacePath {
            indexWorkspace(URL(fileURLWithPath: current))
        } else {
            statusMessage = "Core reconfigured · choose a folder to index"
        }
    }

    var workspaceName: String {
        guard let workspacePath else { return "No folder selected" }
        return URL(fileURLWithPath: workspacePath).lastPathComponent
    }

    func chooseWorkspace() {
        guard client != nil else {
            statusMessage = "Local core unavailable · configure the Python core before indexing"
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Choose a folder for MacPilot"
        panel.message = "MacPilot will index this folder locally. It will not move or delete files."
        panel.prompt = "Index Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.indexWorkspace(url)
        }
    }

    func indexWorkspace(_ url: URL) {
        guard let client else {
            statusMessage = "Local core unavailable · configure the Python core before indexing"
            return
        }

        let workspaceURL = url.standardizedFileURL
        guard workspaceURL.isFileURL else {
            statusMessage = "Invalid folder path · choose a local file URL"
            return
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: workspaceURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            statusMessage = "Invalid folder path · the selected directory is unavailable"
            return
        }

        prepareWorkspaceAccess(for: workspaceURL)
        workspacePath = workspaceURL.path
        lastIndexURL = workspaceURL
        files = []
        suggestions = []
        actions = []
        coreStatus = nil
        selectedFile = nil
        searchResults = []
        operationTask?.cancel()
        isBusy = true
        indexProgress = nil
        statusMessage = "Indexing \(workspaceURL.path) locally — large folders may take a while…"

        operationTask = Task { [weak self] in
            do {
                let summary = try await client.index(root: workspaceURL) { count in
                    Task { @MainActor [weak self] in
                        self?.indexProgress = count
                    }
                }
                let indexedFiles = try await client.list(root: workspaceURL)
                let coreSuggestions = try await client.suggestions(root: workspaceURL)
                let coreActions = try await client.actions()
                let coreStatus = try await client.status()
                guard !Task.isCancelled else { return }

                self?.files = indexedFiles.map(Self.makeFile)
                self?.suggestions = coreSuggestions.map(Self.makeSuggestion)
                self?.actions = coreActions.map(Self.makeActivity)
                self?.coreStatus = coreStatus
                self?.rememberWorkspace(workspaceURL.path)
                self?.lastIndexDate = Date()
                self?.indexProgress = nil
                self?.isBusy = false
                self?.statusMessage = Self.indexStatus(
                    summary: summary,
                    totalFiles: indexedFiles.count,
                    workspace: workspaceURL.path
                )
            } catch {
                guard !Task.isCancelled else { return }
                self?.indexProgress = nil
                self?.isBusy = false
                self?.statusMessage = Self.errorMessage(error)
            }
        }
    }

    /// Re-index the most recently chosen folder (used by the retry affordance).
    func retryLastIndex() {
        guard let lastIndexURL else {
            statusMessage = "Nothing to retry · choose a folder first"
            return
        }
        indexWorkspace(lastIndexURL)
    }

    /// Re-index the currently selected workspace.
    func reindex() {
        guard let workspacePath else {
            statusMessage = "Choose a folder before re-indexing"
            return
        }
        indexWorkspace(URL(fileURLWithPath: workspacePath))
    }

    /// Re-index automatically on app activation only if the last index is
    /// stale (older than 60s) so external file changes are picked up without
    /// hammering the core on every focus change.
    func autoRefreshIfStale() {
        guard workspacePath != nil, !isBusy else { return }
        guard let last = lastIndexDate, Date().timeIntervalSince(last) > 60 else { return }
        reindex()
    }

    /// Handle files/folders dropped onto the window: a folder indexes directly;
    /// a file indexes its containing folder.
    func handleDroppedURLs(_ urls: [URL]) {
        guard let first = urls.first else { return }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: first.path,
            isDirectory: &isDirectory
        )
        guard exists else {
            statusMessage = "Dropped path no longer exists"
            return
        }
        let target = isDirectory.boolValue
            ? first
            : first.deletingLastPathComponent()
        indexWorkspace(target)
    }

    /// Persist LLM provider settings. The API key goes to the Keychain, never
    /// to UserDefaults or the repository.
    func saveLLMConfig() {
        UserDefaults.standard.set(llmProvider.rawValue, forKey: "macpilot.llmProvider")
        UserDefaults.standard.set(cloudBaseURL, forKey: "macpilot.cloudBaseURL")
        UserDefaults.standard.set(cloudModel, forKey: "macpilot.cloudModel")
        if cloudAPIKey.isEmpty {
            KeychainHelper.delete("cloudAPIKey")
        } else {
            KeychainHelper.set(cloudAPIKey, for: "cloudAPIKey")
        }
        statusMessage = "LLM settings saved · local only"
    }

    /// Environment overrides handed to the core for summarize calls so the
    /// selected provider (local Ollama or a cloud API) is honoured.
    func cloudEnvironment() -> [String: String] {
        var env: [String: String] = [:]
        env["MACPILOT_LLM_PROVIDER"] = llmProvider.rawValue
        if llmProvider == .cloud {
            env["MACPILOT_CLOUD_BASE_URL"] = cloudBaseURL
            env["MACPILOT_CLOUD_MODEL"] = cloudModel
            if !cloudAPIKey.isEmpty {
                env["MACPILOT_CLOUD_API_KEY"] = cloudAPIKey
            }
        }
        return env
    }

    func loadDuplicates() {
        guard let client else { return }
        operationTask?.cancel()
        operationTask = Task { [weak self] in
            do {
                let groups = try await client.duplicates()
                guard !Task.isCancelled else { return }
                self?.duplicateGroups = groups.map {
                    DuplicateGroup(id: $0.fingerprint, size: $0.size, paths: $0.paths)
                }
            } catch {
                // Duplicates are optional; a failed load leaves the list empty.
            }
        }
    }

    /// Move every surplus copy in a duplicate group to the Trash, keeping the
    /// first path. Each trash is individually undoable.
    func trashSurplus(in group: DuplicateGroup) {
        guard let client else {
            statusMessage = "Local core unavailable · could not clean duplicates"
            return
        }
        guard !isBusy else { return }
        let surplus = group.surplusPaths
        guard !surplus.isEmpty else { return }

        operationTask?.cancel()
        isBusy = true
        statusMessage = "Moving \(surplus.count) duplicate(s) to Trash…"

        operationTask = Task { [weak self] in
            do {
                var trashed = 0
                for path in surplus {
                    let outcome = try await client.trashApply(source: path)
                    if outcome.applied { trashed += 1 }
                }
                guard !Task.isCancelled else { return }
                try await self?.refreshAfterMutation()
                guard !Task.isCancelled else { return }
                self?.loadDuplicates()
                self?.isBusy = false
                self?.statusMessage =
                    "Moved \(trashed) duplicate(s) to Trash · undo available in Activity"
            } catch {
                guard !Task.isCancelled else { return }
                self?.isBusy = false
                self?.statusMessage = Self.errorMessage(error)
            }
        }
    }

    private func rememberWorkspace(_ path: String) {
        var workspaces = recentWorkspaces.filter { $0 != path }
        workspaces.insert(path, at: 0)
        if workspaces.count > Self.recentWorkspacesLimit {
            workspaces = Array(workspaces.prefix(Self.recentWorkspacesLimit))
        }
        recentWorkspaces = workspaces
        UserDefaults.standard.set(workspaces, forKey: Self.recentWorkspacesKey)
    }

    func preview(_ suggestion: DemoSuggestion) {
        guard let index = suggestions.firstIndex(where: { $0.id == suggestion.id }) else { return }
        guard !suggestions[index].isPreviewed else { return }
        guard let client else {
            statusMessage = "Local core unavailable · preview could not be created"
            return
        }

        operationTask?.cancel()
        isBusy = true
        statusMessage = "Preparing a no-change preview…"
        let sources = suggestion.sourcePaths
        let destination = suggestion.destination

        operationTask = Task { [weak self] in
            do {
                for source in sources {
                    guard !Task.isCancelled else { return }
                    let filename = URL(fileURLWithPath: source).lastPathComponent
                    let destinationPath = URL(fileURLWithPath: destination, isDirectory: true)
                        .appendingPathComponent(filename)
                        .path
                    _ = try await client.previewMove(
                        source: source,
                        destination: destinationPath
                    )
                }
                guard !Task.isCancelled else { return }
                if let index = self?.suggestions.firstIndex(where: { $0.id == suggestion.id }) {
                    self?.suggestions[index].isPreviewed = true
                }
                self?.isBusy = false
                self?.statusMessage = "Preview ready · no files were changed"
            } catch {
                guard !Task.isCancelled else { return }
                self?.isBusy = false
                self?.statusMessage = Self.errorMessage(error)
            }
        }
    }

    func apply(_ suggestion: DemoSuggestion) {
        guard let client else {
            statusMessage = "Local core unavailable · apply could not run"
            return
        }
        guard !isBusy else { return }
        guard workspacePath != nil else {
            statusMessage = "Choose a folder before applying moves"
            return
        }
        guard !suggestion.sourcePaths.isEmpty else {
            statusMessage = "Nothing to apply for this suggestion"
            return
        }

        operationTask?.cancel()
        isBusy = true
        statusMessage = "Applying \(suggestion.sourcePaths.count) move(s)…"
        let sources = suggestion.sourcePaths
        let destination = suggestion.destination

        operationTask = Task { [weak self] in
            do {
                var appliedCount = 0
                for source in sources {
                    guard !Task.isCancelled else { return }
                    let filename = URL(fileURLWithPath: source).lastPathComponent
                    let destinationPath = URL(fileURLWithPath: destination, isDirectory: true)
                        .appendingPathComponent(filename)
                        .path
                    let outcome = try await client.applyMove(
                        source: source,
                        destination: destinationPath
                    )
                    guard outcome.applied else {
                        throw MacPilotClientError.commandFailed(
                            command: "move apply",
                            message: "The core did not confirm the move",
                            status: -1
                        )
                    }
                    appliedCount += 1
                }
                guard !Task.isCancelled else { return }
                try await self?.refreshAfterMutation()
                guard !Task.isCancelled else { return }
                self?.isBusy = false
                self?.statusMessage =
                    "Applied \(appliedCount) move(s) · undo is available in Activity · local only"
            } catch {
                guard !Task.isCancelled else { return }
                self?.isBusy = false
                self?.statusMessage = Self.errorMessage(error)
            }
        }
    }

    func undo(_ action: ActivityEntry) {
        guard !action.isUndone else { return }
        guard let actionID = action.coreActionID else {
            statusMessage = "This activity record has no core action to undo"
            return
        }
        guard let client else {
            statusMessage = "Local core unavailable · undo could not run"
            return
        }
        guard !isBusy else { return }

        operationTask?.cancel()
        isBusy = true
        statusMessage = "Undoing move #\(actionID)…"
        operationTask = Task { [weak self] in
            do {
                let outcome = try await client.undo(actionID: actionID)
                guard outcome.applied else {
                    throw MacPilotClientError.commandFailed(
                        command: "undo apply",
                        message: "The core did not confirm the undo",
                        status: -1
                    )
                }
                guard !Task.isCancelled else { return }
                try await self?.refreshAfterMutation()
                guard !Task.isCancelled else { return }
                self?.isBusy = false
                self?.statusMessage =
                    "Move undone · file restored to its original location · local only"
            } catch {
                guard !Task.isCancelled else { return }
                self?.isBusy = false
                self?.statusMessage = Self.errorMessage(error)
            }
        }
    }

    func trash(_ file: DemoFile) {
        guard let client else {
            statusMessage = "Local core unavailable · trash could not run"
            return
        }
        guard !isBusy else { return }

        operationTask?.cancel()
        isBusy = true
        statusMessage = "Moving \(file.name) to Trash…"
        let source = file.path

        operationTask = Task { [weak self] in
            do {
                let outcome = try await client.trashApply(source: source)
                guard outcome.applied else {
                    throw MacPilotClientError.commandFailed(
                        command: "trash apply",
                        message: "The core did not confirm the trash",
                        status: -1
                    )
                }
                guard !Task.isCancelled else { return }
                try await self?.refreshAfterMutation()
                guard !Task.isCancelled else { return }
                self?.isBusy = false
                self?.statusMessage =
                    "\(file.name) moved to Trash · undo is available in Activity · local only"
            } catch {
                guard !Task.isCancelled else { return }
                self?.isBusy = false
                self?.statusMessage = Self.errorMessage(error)
            }
        }
    }

    func summarize(_ file: DemoFile) {
        guard let client else {
            statusMessage = "Local core unavailable · summarize could not run"
            return
        }
        summarizingFile = true
        fileSummary = nil
        statusMessage = "Summarizing \(file.name)…"
        operationTask?.cancel()
        let environment = cloudEnvironment()

        operationTask = Task { [weak self] in
            do {
                let result = try await client.summarize(
                    path: file.path,
                    extraEnvironment: environment
                )
                guard !Task.isCancelled else { return }
                self?.fileSummary = FileSummary(fileID: file.id, text: result.summary)
                self?.summarizingFile = false
                self?.statusMessage = "Summary ready"
            } catch {
                guard !Task.isCancelled else { return }
                self?.summarizingFile = false
                self?.statusMessage = Self.errorMessage(error)
            }
        }
    }

    func undoAllActions() {
        guard let client else {
            statusMessage = "Local core unavailable · undo-all could not run"
            return
        }
        guard !isBusy else { return }
        operationTask?.cancel()
        isBusy = true
        statusMessage = "Undoing all actions…"

        operationTask = Task { [weak self] in
            do {
                let result = try await client.undoAll(apply: true)
                guard !Task.isCancelled else { return }
                try await self?.refreshAfterMutation()
                guard !Task.isCancelled else { return }
                self?.isBusy = false
                self?.statusMessage = "Reverted \(result.count) action(s) · local only"
            } catch {
                guard !Task.isCancelled else { return }
                self?.isBusy = false
                self?.statusMessage = Self.errorMessage(error)
            }
        }
    }

    func loadRules() {
        guard let client else { return }
        operationTask?.cancel()
        operationTask = Task { [weak self] in
            do {
                let fetched = try await client.rules()
                guard !Task.isCancelled else { return }
                self?.rules = fetched.map {
                    OrgRule(id: $0.id, pattern: $0.pattern, destination: $0.destination)
                }
            } catch {
                // Rules are optional; a failed load leaves the list empty.
            }
        }
    }

    func addRule(pattern: String, destination: String) {
        guard let client else {
            statusMessage = "Local core unavailable · rule could not be added"
            return
        }
        let cleanPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDestination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPattern.isEmpty, !cleanDestination.isEmpty else {
            statusMessage = "Rule needs a pattern and a destination"
            return
        }
        operationTask?.cancel()
        operationTask = Task { [weak self] in
            do {
                _ = try await client.addRule(pattern: cleanPattern, destination: cleanDestination)
                guard !Task.isCancelled else { return }
                self?.statusMessage = "Rule added · preview-first"
                self?.loadRules()
            } catch {
                guard !Task.isCancelled else { return }
                self?.statusMessage = Self.errorMessage(error)
            }
        }
    }

    func removeRule(id: Int) {
        guard let client else { return }
        operationTask?.cancel()
        operationTask = Task { [weak self] in
            do {
                _ = try await client.removeRule(id: id)
                guard !Task.isCancelled else { return }
                self?.statusMessage = "Rule removed"
                self?.loadRules()
            } catch {
                guard !Task.isCancelled else { return }
                self?.statusMessage = Self.errorMessage(error)
            }
        }
    }

    func renameApply(find: String, replace: String) {
        guard let client else {
            statusMessage = "Local core unavailable · rename could not run"
            return
        }
        guard let workspacePath else {
            statusMessage = "Choose a folder before renaming"
            return
        }
        let cleanFind = find.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanFind.isEmpty else {
            statusMessage = "Rename needs a non-empty 'find' text"
            return
        }
        guard !isBusy else { return }
        operationTask?.cancel()
        isBusy = true
        statusMessage = "Renaming files…"

        operationTask = Task { [weak self] in
            do {
                let result = try await client.rename(
                    root: workspacePath,
                    find: cleanFind,
                    replace: replace,
                    apply: true
                )
                guard !Task.isCancelled else { return }
                try await self?.refreshAfterMutation()
                guard !Task.isCancelled else { return }
                self?.isBusy = false
                self?.statusMessage =
                    "Renamed \(result.count) file(s) · undo available in Activity · local only"
            } catch {
                guard !Task.isCancelled else { return }
                self?.isBusy = false
                self?.statusMessage = Self.errorMessage(error)
            }
        }
    }

    private func scheduleSearch() {
        operationTask?.cancel()
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            searchResults = []
            isBusy = false
            if workspacePath != nil {
                statusMessage = "Showing indexed files · local only"
            }
            return
        }
        guard let client else {
            searchResults = []
            isBusy = false
            statusMessage = "Local core unavailable · search cannot run"
            return
        }
        guard workspacePath != nil else {
            searchResults = []
            isBusy = false
            statusMessage = "Choose a folder before searching"
            return
        }

        isBusy = true
        operationTask = Task { [weak self] in
            do {
                let results = try await client.search(query: term)
                guard !Task.isCancelled else { return }
                self?.searchResults = results.map(Self.makeFile)
                if let selected = self?.selectedFile,
                   !results.contains(where: { $0.path == selected.path }) {
                    self?.selectedFile = nil
                }
                self?.isBusy = false
                self?.statusMessage = "Found \(results.count) matching files · local only"
            } catch {
                guard !Task.isCancelled else { return }
                self?.searchResults = []
                self?.isBusy = false
                self?.statusMessage = Self.errorMessage(error)
            }
        }
    }

    private func prepareWorkspaceAccess(for url: URL) {
        if securityScopedWorkspaceURL?.path == url.path {
            return
        }

        securityScopedWorkspaceURL?.stopAccessingSecurityScopedResource()
        securityScopedWorkspaceURL = nil
        if url.startAccessingSecurityScopedResource() {
            securityScopedWorkspaceURL = url
        }
    }

    private func refreshAfterMutation() async throws {
        guard let client, let workspacePath else { return }
        let root = URL(fileURLWithPath: workspacePath)
        let indexedFiles = try await client.list(root: root)
        let coreSuggestions = try await client.suggestions(root: root)
        let coreActions = try await client.actions()
        let coreStatus = try await client.status()
        files = indexedFiles.map(Self.makeFile)
        suggestions = coreSuggestions.map(Self.makeSuggestion)
        actions = coreActions.map(Self.makeActivity)
        self.coreStatus = coreStatus
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if term.isEmpty {
            searchResults = []
        } else {
            searchResults = try await client.search(query: term).map(Self.makeFile)
        }
        selectedFile = nil
    }

    private static func makeFile(_ result: CoreSearchResult) -> DemoFile {
        DemoFile(
            id: result.path,
            name: result.filename,
            path: result.path,
            kind: kind(for: result.extension),
            size: ByteCountFormatter.string(
                fromByteCount: Int64(result.size),
                countStyle: .file
            ),
            modified: displayDate(result.modifiedAt),
            snippet: result.snippet,
            isText: result.isText ?? false,
            modifiedAt: parseDate(result.modifiedAt)
        )
    }

    private static func makeSuggestion(_ suggestion: CoreSuggestion) -> DemoSuggestion {
        DemoSuggestion(
            id: suggestion.destination,
            title: suggestion.category,
            files: suggestion.files.map { URL(fileURLWithPath: $0).lastPathComponent },
            sourcePaths: suggestion.files,
            destination: suggestion.destination,
            reason: suggestion.reason
        )
    }

    private static func makeActivity(_ action: CoreAction) -> ActivityEntry {
        let source = URL(fileURLWithPath: action.sourcePath).lastPathComponent
        let destination = URL(fileURLWithPath: action.destinationPath).path
        return ActivityEntry(
            id: "action-\(action.id)",
            coreActionID: action.id,
            action: "Move recorded",
            detail: "\(source) → \(destination)",
            date: displayDate(action.appliedAt),
            isUndone: action.undoneAt != nil
        )
    }

    private static func kind(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case ".pdf": return "PDF"
        case ".png", ".jpg", ".jpeg", ".gif", ".webp", ".heic": return "Image"
        case ".md", ".markdown": return "Markdown"
        case ".txt": return "Text"
        case ".csv", ".xls", ".xlsx": return "Spreadsheet"
        case ".doc", ".docx": return "Document"
        default: return fileExtension.isEmpty ? "File" : fileExtension.uppercased()
        }
    }

    private static func displayDate(_ value: String) -> String {
        value.replacingOccurrences(of: "T", with: " ")
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) {
            return date
        }
        return formatter.date(from: value.replacingOccurrences(of: " ", with: "T"))
    }

    private static func indexStatus(
        summary: CoreIndexSummary,
        totalFiles: Int,
        workspace: String
    ) -> String {
        var message = "Indexed \(totalFiles) files · \(workspace) · local only"
        if summary.skippedSymlinks > 0 {
            message += " · skipped \(summary.skippedSymlinks) symlink(s)"
        }
        return message
    }

    private static func errorMessage(_ error: Error) -> String {
        Diagnostics.log("error: \(error.localizedDescription)")
        if let coreError = error as? MacPilotClientError {
            switch coreError {
            case .timedOut(let command, let timeout):
                return "\(command) timed out after \(Int(timeout))s · try a smaller folder, then retry"
            case .executableNotFound:
                return "Local core not found · set MACPILOT_PROJECT_ROOT or install macpilot"
            case .commandFailed(let command, let message, let status):
                let detail = message.isEmpty ? "exit status \(status)" : message
                return "\(command) failed (\(detail)) · local only, nothing was changed"
            case .invalidOutput(let command, _):
                return "\(command) returned unexpected output · the local core may need an update"
            }
        }
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return "Local core error · \(error.localizedDescription)"
    }
}
