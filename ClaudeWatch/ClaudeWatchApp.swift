import SwiftUI

@main
struct ClaudeWatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar app - no WindowGroup needed
        Settings {
            EmptyView()
        }
    }
}
