import SwiftUI


@main
struct MacPilotDemoApp: App {
    @StateObject private var store = DemoStore()

    var body: some Scene {
        WindowGroup("MacPilot Demo") {
            ContentView()
                .environmentObject(store)
        }
        .windowResizability(.contentSize)
    }
}
