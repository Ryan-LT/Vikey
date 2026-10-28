import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Migration.fromOpenKeyIfNeeded()
        AppState.shared.startIfPossible()
        if UserDefaults.standard.bool(forKey: "showOnboarding") { OnboardingWindow.show() }   // -showOnboarding YES (screenshots)
        if UserDefaults.standard.bool(forKey: "showAbout") { AboutPanel.show() }             // -showAbout YES (screenshots)
        if UserDefaults.standard.bool(forKey: "showMain") { Windows.main.show() }           // -showMain YES (screenshots)
        // Opened by the user (not at login, minutes after boot): show the main window.
        if AppState.shared.isRunning && ProcessInfo.processInfo.systemUptime > 180 && !UserDefaults.standard.bool(forKey: "noWindowAtLaunch") {
            Windows.main.show()
        }

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { _ in
            VikeyCore.frontmostAppChanged()
        }
        ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
            VikeyCore.activeSpaceChanged()
        }
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            VikeyCore.stop()
        }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            AppState.shared.startIfPossible()
        }
    }

    /// Opening Vikey again while it runs (Finder, Spotlight, Dock) shows the main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if AppState.shared.needsOnboarding { OnboardingWindow.show() } else { Windows.main.show() }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        VikeyCore.flushTypingLog()
    }
}
