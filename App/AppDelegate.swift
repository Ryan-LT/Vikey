import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Migration.fromOpenKeyIfNeeded()
        AppState.shared.startIfPossible()
        if UserDefaults.standard.bool(forKey: "showOnboarding") { OnboardingWindow.show() }   // -showOnboarding YES (screenshots)

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

    func applicationWillTerminate(_ notification: Notification) {
        VikeyCore.flushTypingLog()
    }
}
