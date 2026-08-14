import SwiftUI
import AppKit


final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A MenuBarExtra can leave the app in accessory mode; force regular
        // activation so the WindowGroup window actually appears.
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            Self.openMainWindow()
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        // Clicking the Dock icon when no window is visible reopens it.
        Self.openMainWindow()
        return true
    }

    static func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.isVisible || $0.canBecomeMain })
            ?? NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }
}


@main
struct MacPilotDemoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
                AppDelegate.openMainWindow()
            }
        }
    }

    var body: some Scene {
        WindowGroup("MacPilot") {
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
                AppDelegate.openMainWindow()
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
}
