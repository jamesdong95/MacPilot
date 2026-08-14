import SwiftUI
import AppKit


struct ContentView: View {
    @EnvironmentObject private var store: DemoStore
    @State private var showSettings = false

    var body: some View {
        NavigationSplitView {
            SidebarView(onSettings: { showSettings = true })
        } detail: {
            Group {
                switch store.selectedSection ?? .search {
                case .search:
                    SearchView()
                case .suggestions:
                    SuggestionsView()
                case .activity:
                    ActivityView()
                }
            }
            .frame(minWidth: 760, minHeight: 560)
        }
        // Window titlebars overlap the split view at compact sizes on macOS;
        // reserve that inset inside the fixed window content size.
        .padding(.top, 34)
        .frame(
            minWidth: 960,
            maxWidth: .infinity,
            minHeight: 640,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .onAppear {
            fitWindowToScreen()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { _ in
            clampWindowToScreen()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.autoRefreshIfStale()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            var urls: [URL] = []
            let group = DispatchGroup()
            for provider in providers {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { object, _ in
                    if let url = object {
                        urls.append(url)
                    }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                store.handleDroppedURLs(urls)
            }
            return true
        }
    }

    /// Open the window at a compact, screen-safe size and center it so the app
    /// never starts larger than the display (small screens / VDI viewports).
    private func fitWindowToScreen() {
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.isVisible || $0.isKeyWindow }) ?? NSApp.windows.first,
                  let screen = window.screen ?? NSScreen.main else {
                return
            }
            let visible = screen.visibleFrame
            // Guard against bogus/zero-height frames (VDI and virtual displays
            // can report a titlebar-sized visibleFrame): if the visible area is
            // implausibly small, leave the window at its default size instead
            // of collapsing it to a sliver.
            guard visible.width >= 480, visible.height >= 480 else { return }
            let currentContentRect = window.contentRect(forFrameRect: window.frame)
            let frameInsets = CGSize(
                width: window.frame.width - currentContentRect.width,
                height: window.frame.height - currentContentRect.height
            )
            let targetContentWidth = min(960.0, max(0, visible.width - frameInsets.width))
            let targetContentHeight = min(640.0, max(0, visible.height - frameInsets.height))
            let contentRect = NSRect(
                origin: .zero,
                size: CGSize(width: targetContentWidth, height: targetContentHeight)
            )
            var targetFrame = window.frameRect(forContentRect: contentRect)
            targetFrame.origin.x = visible.minX + max(0, (visible.width - targetFrame.width) / 2)
            targetFrame.origin.y = visible.minY + max(0, (visible.height - targetFrame.height) / 2)

            window.setFrame(targetFrame, display: true)
            clampWindowToScreen(window)
        }
    }

    /// Clamp window size and origin so the window frame never exceeds the screen's visible frame.
    private func clampWindowToScreen(_ targetWindow: NSWindow? = nil) {
        guard let window = targetWindow ?? NSApp.windows.first(where: { $0.isVisible || $0.isKeyWindow }) ?? NSApp.windows.first,
              let screen = window.screen ?? NSScreen.main else {
            return
        }
        let visible = screen.visibleFrame
        guard visible.width >= 480, visible.height >= 480 else { return }
        var frame = window.frame
        var changed = false

        if frame.width > visible.width {
            frame.size.width = visible.width
            changed = true
        }
        if frame.height > visible.height {
            frame.size.height = visible.height
            changed = true
        }
        if frame.maxY > visible.maxY {
            frame.origin.y = visible.maxY - frame.height
            changed = true
        }
        if frame.minY < visible.minY {
            frame.origin.y = visible.minY
            changed = true
        }
        if frame.maxX > visible.maxX {
            frame.origin.x = visible.maxX - frame.width
            changed = true
        }
        if frame.minX < visible.minX {
            frame.origin.x = visible.minX
            changed = true
        }

        if changed {
            window.setFrame(frame, display: true)
        }
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var store: DemoStore
    var onSettings: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("MacPilot", systemImage: "sparkle.magnifyingglass")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Text("Local-first file intelligence")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 4)
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                }
                .buttonStyle(.borderless)
                .help("Settings")
                .accessibilityLabel("Settings")
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            List(selection: $store.selectedSection) {
                Section("Workspace") {
                    ForEach(AppSection.allCases) { section in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(section.title)
                                    .lineLimit(1)
                                Text(section.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } icon: {
                            Image(systemName: section.icon)
                                .frame(width: 20)
                        }
                        .tag(section)
                        .padding(.vertical, 3)
                    }
                }
            }
            .listStyle(.sidebar)
            .layoutPriority(1)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(store.workspaceName)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                            Text(store.hasCore ? "Python core connected" : "Python core unavailable")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    Button("Choose folder…") { store.chooseWorkspace() }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .disabled(!store.hasCore || store.isBusy)
                    if store.workspacePath != nil {
                        Button {
                            store.reindex()
                        } label: {
                            Label("Re-index", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .disabled(store.isBusy)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label("Privacy protected", systemImage: "lock.shield.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.green)
                        .lineLimit(1)
                    Text("Search and previews stay local. File changes require explicit confirmation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
    }
}

private struct SearchView: View {
    @EnvironmentObject private var store: DemoStore
    @State private var fileToTrash: DemoFile?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(
                eyebrow: "FILE SEARCH",
                title: "Find anything, locally.",
                subtitle: "Search names, paths and extracted content without uploading your files."
            )
            .layoutPriority(1)

            HStack(spacing: 8) {
                Label(store.workspaceName, systemImage: "folder.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if store.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Choose folder…") { store.chooseWorkspace() }
                    .buttonStyle(.bordered)
                    .disabled(!store.hasCore || store.isBusy)
            }
            .layoutPriority(1)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Try: project invoice or launch checklist", text: $store.query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .disabled(store.isBusy)
                if !store.query.isEmpty {
                    Button { store.query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
            .layoutPriority(1)

            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(FileFilter.allCases) { filter in
                            FilterPill(
                                title: filter.title,
                                active: store.activeFilter == filter,
                                action: { store.activeFilter = filter }
                            )
                        }
                    }
                }
                Spacer(minLength: 2)
                Label("Local only", systemImage: "checkmark.shield")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
                    .lineLimit(1)
                    .fixedSize()
            }
            .layoutPriority(1)

            if store.workspacePath == nil {
                EmptyWorkspaceCard(
                    action: { store.chooseWorkspace() },
                    recentWorkspaces: store.recentWorkspaces,
                    onSelectRecent: { path in
                        store.indexWorkspace(URL(fileURLWithPath: path))
                    }
                )
                .layoutPriority(1)
            }

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Results")
                            .font(.headline)
                        Text("\(store.filteredFiles.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(store.filteredFiles) { file in
                                FileRow(
                                    file: file,
                                    selected: store.selectedFile?.id == file.id,
                                    highlight: store.query
                                ) {
                                    store.selectedFile = file
                                }
                                .contextMenu {
                                    Button("Move to Trash", role: .destructive) {
                                        fileToTrash = file
                                    }
                                }
                            }
                            if store.filteredFiles.isEmpty, store.workspacePath != nil {
                                Text(store.query.isEmpty ? "No indexed files yet." : "No matching files.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 80)
                            }
                        }
                    }
                }
                .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)

                Divider()

                Group {
                    if let file = store.selectedFile {
                        FileInspector(file: file)
                    } else {
                        EmptyInspector()
                    }
                }
                .frame(
                    minWidth: 160,
                    idealWidth: 210,
                    maxWidth: 250,
                    minHeight: 110,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
            }
            .frame(minHeight: 120, maxHeight: .infinity)
            .layoutPriority(0)

            if let progress = store.indexProgress {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Indexed \(progress) files…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Text(store.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        // Leave enough room for the 760pt detail minimum beside the sidebar
        // when the window is at its 960pt minimum.
        .padding(12)
        .confirmationDialog(
            "Move \(fileToTrash?.name ?? "this file") to the Trash?",
            isPresented: Binding(
                get: { fileToTrash != nil },
                set: { if !$0 { fileToTrash = nil } }
            )
        ) {
            Button("Move to Trash", role: .destructive) {
                if let file = fileToTrash {
                    store.trash(file)
                }
                fileToTrash = nil
            }
            Button("Cancel", role: .cancel) { fileToTrash = nil }
        } message: {
            Text("The file is moved to the macOS Trash and can be undone from Activity.")
        }
    }
}

private struct SuggestionsView: View {
    @EnvironmentObject private var store: DemoStore
    @State private var suggestionToApply: DemoSuggestion?
    @State private var showRename = false
    @State private var renameFind = ""
    @State private var renameReplace = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                PageHeader(
                    eyebrow: "SAFE ORGANIZATION",
                    title: "Suggestions, not surprises.",
                    subtitle: "Review every proposed action before anything changes on disk."
                )
                Spacer(minLength: 8)
                Button("Batch rename…") {
                    showRename = true
                }
                .buttonStyle(.bordered)
                .fixedSize()
                .disabled(store.workspacePath == nil || store.isBusy)
            }

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(store.suggestions) { suggestion in
                        SuggestionCard(
                            suggestion: suggestion,
                            preview: { store.preview(suggestion) },
                            apply: { suggestionToApply = suggestion }
                        )
                    }
                    if store.suggestions.isEmpty {
                        Text("Index a folder to generate local suggestions.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    }
                }
            }
        }
        .padding(18)
        .confirmationDialog(
            "Apply \(suggestionToApply?.files.count ?? 0) move(s)?",
            isPresented: Binding(
                get: { suggestionToApply != nil },
                set: { if !$0 { suggestionToApply = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Apply Moves") {
                if let suggestion = suggestionToApply {
                    store.apply(suggestion)
                }
                suggestionToApply = nil
            }
            Button("Cancel", role: .cancel) {
                suggestionToApply = nil
            }
        } message: {
            Text("Files move into a new folder on your disk. Each move is recorded and can be undone from Activity.")
        }
        .sheet(isPresented: $showRename) {
            RenameSheet(
                find: $renameFind,
                replace: $renameReplace,
                onApply: {
                    store.renameApply(find: renameFind, replace: renameReplace)
                    showRename = false
                }
            )
        }
    }
}

private struct RenameSheet: View {
    @EnvironmentObject private var store: DemoStore
    @Environment(\.dismiss) private var dismiss
    @Binding var find: String
    @Binding var replace: String
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Batch rename")
                .font(.title2.bold())
                .lineLimit(1)
            Text("Replaces text in filenames across the indexed folder. Every rename is recorded and undoable from Activity.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LabeledContent("Find") {
                TextField("e.g. Untitled", text: $find)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Replace with") {
                TextField("e.g. Photo", text: $replace)
                    .textFieldStyle(.roundedBorder)
            }

            Spacer(minLength: 0)

            HStack {
                Button("Rename") {
                    onApply()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(find.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
                Button("Cancel") { dismiss() }
            }
        }
        .padding(20)
        .frame(width: 420, height: 260)
    }
}

private struct ActivityView: View {
    @EnvironmentObject private var store: DemoStore
    @State private var actionToUndo: ActivityEntry?
    @State private var undoAllConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                PageHeader(
                    eyebrow: "AUDIT TRAIL",
                    title: "Local activity, clearly recorded.",
                    subtitle: "Every applied move is recorded. Undo restores the file to its original location."
                )
                Spacer(minLength: 8)
                if store.actions.contains(where: { !$0.isUndone }) {
                    Button("Undo all", role: .destructive) {
                        undoAllConfirm = true
                    }
                    .buttonStyle(.bordered)
                    .fixedSize()
                }
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(store.actions) { action in
                        HStack(spacing: 12) {
                            Image(systemName: action.isUndone ? "arrow.uturn.backward.circle" : "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(action.isUndone ? Color.secondary : Color.green)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(action.action)
                                    .font(.headline)
                                    .lineLimit(1)
                                Text(action.detail)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(action.date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                if action.isUndone {
                                    Text("Undone")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                } else {
                                    Button("Undo") { actionToUndo = action }
                                        .buttonStyle(.bordered)
                                        .fixedSize()
                                }
                            }
                        }
                        .padding(14)
                        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
                    }
                    if store.actions.isEmpty {
                        Text("No applied actions in the local action log.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    }
                }
            }
        }
        .padding(18)
        .confirmationDialog(
            "Undo this move?",
            isPresented: Binding(
                get: { actionToUndo != nil },
                set: { if !$0 { actionToUndo = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Undo Move", role: .destructive) {
                if let action = actionToUndo {
                    store.undo(action)
                }
                actionToUndo = nil
            }
            Button("Cancel", role: .cancel) {
                actionToUndo = nil
            }
        } message: {
            Text("The file will be moved back to its original location. The action is recorded as undone.")
        }
        .confirmationDialog(
            "Undo all actions?",
            isPresented: $undoAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Undo All", role: .destructive) {
                store.undoAllActions()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every applied move will be reverted, newest first. Each revert stays individually undoable.")
        }
    }
}

private struct PageHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow)
                .font(.caption.weight(.bold))
                .foregroundStyle(.tint)
                .tracking(1.2)
            Text(title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.9)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

private struct FilterPill: View {
    let title: String
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(active ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(active ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
                .fixedSize()
        }
        .buttonStyle(.plain)
    }
}

private struct FileRow: View {
    let file: DemoFile
    let selected: Bool
    var highlight: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: file.icon)
                    .font(.title3)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .frame(width: 30, height: 30)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Text(highlightedSnippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(file.size)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(10)
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .background(selected ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var highlightedSnippet: AttributedString {
        var attributed = AttributedString(file.snippet)
        let terms = highlight
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
        for term in terms {
            var searchStart = attributed.startIndex
            while let range = attributed[searchStart...].range(
                of: term,
                options: .caseInsensitive
            ) {
                attributed[range].font = .caption.bold()
                attributed[range].foregroundColor = .accentColor
                searchStart = range.upperBound
            }
        }
        return attributed
    }
}

private struct FileInspector: View {
    @EnvironmentObject private var store: DemoStore
    let file: DemoFile

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: file.icon)
                    .font(.system(size: 32))
                    .foregroundStyle(.tint)
                Text(file.name)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                InspectorRow(label: "Type", value: file.kind)
                InspectorRow(label: "Size", value: file.size)
                InspectorRow(label: "Modified", value: file.modified)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Location")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(file.path)
                        .font(.caption)
                        .lineLimit(4)
                        .textSelection(.enabled)
                }
                Divider()
                Text(file.snippet)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if file.isText {
                    Divider()
                    if store.summarizingFile {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Summarizing…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if let summary = store.fileSummary, summary.fileID == file.id {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Summary", systemImage: "sparkles")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(summary.text)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Button {
                        store.summarize(file)
                    } label: {
                        Label("Summarize locally", systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.summarizingFile)
                }
            }
            .padding(.trailing, 4)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct InspectorRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var store: DemoStore
    @Environment(\.dismiss) private var dismiss
    @State private var cliPathText = ""
    @State private var dbPathText = ""
    @State private var newRulePattern = ""
    @State private var newRuleDestination = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings")
                .font(.title2.bold())
                .lineLimit(1)

            Divider()

            LabeledContent("Core") {
                Text(store.coreDescription)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            LabeledContent("Core path (CLI)") {
                TextField("auto-detect", text: $cliPathText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
            }

            LabeledContent("Database path") {
                TextField("default (~/.macpilot/index.sqlite3)", text: $dbPathText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Local AI")
                    .font(.headline)
                    .lineLimit(1)
                Picker("Provider", selection: $store.llmProvider) {
                    ForEach(LLMProvider.allCases) { provider in
                        Text(provider.title).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if store.llmProvider == .cloud {
                    LabeledContent("Base URL") {
                        TextField("https://api.openai.com", text: $store.cloudBaseURL)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Model") {
                        TextField("gpt-4o-mini", text: $store.cloudModel)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("API key") {
                        SecureField("sk-…", text: $store.cloudAPIKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Text("The API key is stored in the macOS Keychain, never in the app or the repository.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("Save AI settings") {
                    store.saveLLMConfig()
                }
                .buttonStyle(.bordered)
            }

            LabeledContent("Indexed folder") {
                Text(store.workspacePath ?? "None")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Organization rules")
                    .font(.headline)
                    .lineLimit(1)
                if store.rules.isEmpty {
                    Text("No rules yet. Add a pattern like *.pdf → a folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.rules) { rule in
                        HStack(spacing: 6) {
                            Text(rule.pattern)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text("→")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(rule.destination)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 4)
                            Button(role: .destructive) {
                                store.removeRule(id: rule.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove rule")
                        }
                    }
                }
                HStack(spacing: 6) {
                    TextField("*.pdf", text: $newRulePattern)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 130)
                    TextField("Destination folder", text: $newRuleDestination)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        store.addRule(pattern: newRulePattern, destination: newRuleDestination)
                        newRulePattern = ""
                        newRuleDestination = ""
                    }
                    .buttonStyle(.bordered)
                    .disabled(newRulePattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || newRuleDestination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if !store.recentWorkspaces.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent folders")
                        .font(.headline)
                        .lineLimit(1)
                    ForEach(store.recentWorkspaces, id: \.self) { path in
                        Text(path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Button("Clear recent folders") {
                        store.clearRecentWorkspaces()
                    }
                    .buttonStyle(.bordered)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Button("Apply") {
                    store.reconfigure(cliPath: cliPathText, databasePath: dbPathText)
                    dismiss()
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 780)
        .onAppear {
            cliPathText = store.configuredCliPath ?? ""
            dbPathText = store.configuredDatabasePath ?? store.databasePath ?? ""
            store.loadRules()
        }
    }
}

private struct EmptyInspector: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "cursorarrow.rays")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Select a file")
                .font(.headline)
                .lineLimit(1)
            Text("Inspect metadata and a content snippet here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(12)
        .frame(height: 110, alignment: .center)
        .frame(maxWidth: .infinity)
    }
}

private struct EmptyWorkspaceCard: View {
    let action: () -> Void
    var recentWorkspaces: [String] = []
    var onSelectRecent: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "folder.badge.plus")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text("Connect a local folder")
                    .font(.headline)
                    .lineLimit(1)
                Text("MacPilot will index it locally. Search and previews stay read-only until you confirm a move.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
            }
            Button("Choose folder…", action: action)
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !recentWorkspaces.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recent folders")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    ForEach(recentWorkspaces, id: \.self) { path in
                        Button {
                            onSelectRecent(path)
                        } label: {
                            Label(
                                URL(fileURLWithPath: path).lastPathComponent,
                                systemImage: "clock"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SuggestionCard: View {
    let suggestion: DemoSuggestion
    let preview: () -> Void
    let apply: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: suggestion.isPreviewed ? "checkmark.seal.fill" : "sparkles")
                .font(.title2)
                .foregroundStyle(suggestion.isPreviewed ? Color.green : Color.accentColor)
                .frame(width: 36, height: 36)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 6) {
                Text(suggestion.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(suggestion.reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Label(suggestion.files.joined(separator: " · "), systemImage: "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Label(suggestion.destination, systemImage: "folder")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tint)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if suggestion.isPreviewed {
                HStack(spacing: 6) {
                    Text("Previewed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .lineLimit(1)
                    Button("Apply") { apply() }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .fixedSize()
                }
            } else {
                Button("Preview") { preview() }
                    .buttonStyle(.borderedProminent)
                    .fixedSize()
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }
}
