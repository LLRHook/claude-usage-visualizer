import SwiftUI

@main
struct ClaudeUsageBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsWindowContent(
                usageService: appDelegate.usageService,
                appUpdater: appDelegate.appUpdater
            )
        }
    }
}
