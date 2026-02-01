import AppKit
import UserNotifications
import os.log

/// Handles application lifecycle events and system integration.
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.app.info("Application launched")

        // Set up notification delegate and categories
        UNUserNotificationCenter.current().delegate = NotificationService.shared
        NotificationService.shared.setupNotificationCategories()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Logger.app.info("Application terminating")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep the app running even when all windows are closed
        // This allows background sync and MCP server to continue
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Reopen main window when dock icon is clicked
        if !flag {
            for window in sender.windows {
                window.makeKeyAndOrderFront(self)
            }
        }
        return true
    }
}
