import SwiftUI


struct ContentView: View {
    @EnvironmentObject private var store: DemoStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
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
            .frame(minWidth: 820, minHeight: 640)
        }
        .frame(minWidth: 1080, minHeight: 720)
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var store: DemoStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Label("MacPilot", systemImage: "sparkle.magnifyingglass")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Local-first file intelligence")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 20)
            .padding(.bottom, 14)

            List(selection: $store.selectedSection) {
                Section("Workspace") {
                    ForEach(AppSection.allCases) { section in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(section.title)
                                Text(section.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: section.icon)
                                .frame(width: 20)
                        }
                        .tag(section)
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.workspaceName)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                            Text(store.hasCore ? "Python core connected" : "Python core unavailable")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    Button("Choose folder…") { store.chooseWorkspace() }
                        .buttonStyle(.bordered)
                        .disabled(!store.hasCore || store.isBusy)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("Privacy protected", systemImage: "lock.shield.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.green)
                    Text("Search and previews stay local. File changes are not enabled in this read-only slice.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
    }
}

private struct SearchView: View {
    @EnvironmentObject private var store: DemoStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(
                eyebrow: "FILE SEARCH",
                title: "Find anything, locally.",
                subtitle: "Search names, paths and extracted content without uploading your files."
            )

            HStack(spacing: 10) {
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
            .padding(14)
            .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 8) {
                FilterPill(title: "All files", active: true)
                FilterPill(title: "Content")
                FilterPill(title: "Recently changed")
                Spacer()
                Label("Local only", systemImage: "checkmark.shield")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            }

            if store.workspacePath == nil {
                EmptyWorkspaceCard { store.chooseWorkspace() }
            }

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Results")
                            .font(.headline)
                        Text("\(store.filteredFiles.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(store.filteredFiles) { file in
                                FileRow(file: file, selected: store.selectedFile?.id == file.id) {
                                    store.selectedFile = file
                                }
                            }
                            if store.filteredFiles.isEmpty, store.workspacePath != nil {
                                Text(store.query.isEmpty ? "No indexed files yet." : "No matching files.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 100)
                            }
                        }
                    }
                }
                .frame(minWidth: 460, maxWidth: .infinity, alignment: .leading)

                Divider()

                Group {
                    if let file = store.selectedFile {
                        FileInspector(file: file)
                    } else {
                        EmptyInspector()
                    }
                }
                .frame(width: 290)
            }
            .frame(maxHeight: .infinity)

            Text(store.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(30)
    }
}

private struct SuggestionsView: View {
    @EnvironmentObject private var store: DemoStore

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeader(
                eyebrow: "SAFE ORGANIZATION",
                title: "Suggestions, not surprises.",
                subtitle: "Review every proposed action before anything changes on disk."
            )

            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(store.suggestions) { suggestion in
                        SuggestionCard(suggestion: suggestion) {
                            store.preview(suggestion)
                        }
                    }
                    if store.suggestions.isEmpty {
                        Text("Index a folder to generate local suggestions.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 100)
                    }
                }
            }
        }
        .padding(30)
    }
}

private struct ActivityView: View {
    @EnvironmentObject private var store: DemoStore

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeader(
                eyebrow: "AUDIT TRAIL",
                title: "Local activity, clearly recorded.",
                subtitle: "Existing action records are shown for audit. This client does not apply or undo filesystem changes."
            )

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(store.actions) { action in
                        HStack(spacing: 14) {
                            Image(systemName: action.isUndone ? "arrow.uturn.backward.circle" : "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(action.isUndone ? Color.secondary : Color.green)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(action.action)
                                    .font(.headline)
                                Text(action.detail)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 6) {
                                Text(action.date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !action.isUndone {
                                    Text("Read-only")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Undone")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(16)
                        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
                    }
                    if store.actions.isEmpty {
                        Text("No applied actions in the local action log.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 100)
                    }
                }
            }
        }
        .padding(30)
    }
}

private struct PageHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(eyebrow)
                .font(.caption.weight(.bold))
                .foregroundStyle(.tint)
                .tracking(1.2)
            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct FilterPill: View {
    let title: String
    var active = false

    var body: some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(active ? .white : .primary)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(active ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
    }
}

private struct FileRow: View {
    let file: DemoFile
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: file.icon)
                    .font(.title3)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .frame(width: 30, height: 30)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Text(file.snippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(file.size)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .background(selected ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

private struct FileInspector: View {
    let file: DemoFile

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: file.icon)
                .font(.system(size: 34))
                .foregroundStyle(.tint)
            Text(file.name)
                .font(.title3.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            InspectorRow(label: "Type", value: file.kind)
            InspectorRow(label: "Size", value: file.size)
            InspectorRow(label: "Modified", value: file.modified)
            VStack(alignment: .leading, spacing: 6) {
                Text("Location")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(file.path)
                    .font(.caption)
                    .textSelection(.enabled)
            }
            Divider()
            Text(file.snippet)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
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
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
        }
    }
}

private struct EmptyInspector: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "cursorarrow.rays")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text("Select a file")
                .font(.headline)
            Text("Inspect metadata and a content snippet here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxHeight: .infinity)
    }
}

private struct EmptyWorkspaceCard: View {
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "folder.badge.plus")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 5) {
                Text("Connect a local folder")
                    .font(.headline)
                Text("MacPilot will index it locally and keep search and previews read-only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Choose folder…", action: action)
                .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SuggestionCard: View {
    let suggestion: DemoSuggestion
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: suggestion.isPreviewed ? "checkmark.seal.fill" : "sparkles")
                .font(.title2)
                .foregroundStyle(suggestion.isPreviewed ? Color.green : Color.accentColor)
                .frame(width: 38, height: 38)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 8) {
                Text(suggestion.title)
                    .font(.headline)
                Text(suggestion.reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Label(suggestion.files.joined(separator: " · "), systemImage: "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(suggestion.destination, systemImage: "folder")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tint)
            }
            Spacer()
            if suggestion.isPreviewed {
                Text("Previewed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                Button("Preview") { action() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
    }
}
