import SwiftUI
import AppKit


@main
struct MacPilotDemoApp: App {
    @StateObject private var store = DemoStore()
    private static var hotkeyMonitor: Any?

    init() {
        // Global hotkey (⌘⇧Space) opens/raises the main window from anywhere.
        // Requires Accessibility permission; without it this silently no-ops.
        Self.hotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains(.command),
                  event.modifierFlags.contains(.shift),
                  event.keyCode == 49 else { return }
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.isVisible || $0.canBecomeMain })?
                    .makeKeyAndOrderFront(nil)
            }
        }
    }

    var body: some Scene {
        WindowGroup("MacPilot Demo") {
            ContentView()
                .environmentObject(store)
        }
        .defaultPosition(.center)
        .defaultSize(width: 960, height: 640)
        .windowResizability(.contentSize)

        MenuBarExtra {
            Text("MacPilot")
                .font(.headline)
            if let status = store.coreStatus {
                Text("\(status.files) files indexed")
            } else if store.workspacePath != nil {
                Text("Indexing…")
            } else {
                Text("No folder indexed")
            }
            if let workspace = store.workspacePath {
                Text(workspace)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Divider()
            Button("Open MacPilot") {
                openMainWindow()
            }
            Button("Quit MacPilot") {
                NSApp.terminate(nil)
            }
            Divider()
            Text("⌘⇧Space to search")
                .font(.caption)
                .foregroundStyle(.secondary)
        } label: {
            Image(systemName: "sparkle.magnifyingglass")
        }
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.isVisible || $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
