import SwiftUI

struct MenuBarContent: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    @AppStorage(PrefKey.autoSwitch) private var autoSwitch = 1
    @AppStorage(PrefKey.hotkey) private var hotkeyRaw = Hotkey.defaultValue

    var body: some View {
        if state.needsOnboarding {
            Button("Cấp quyền cho Vikey…") { OnboardingWindow.show() }
            Divider()
        }
        Toggle(isOn: Binding(get: { state.language == 1 }, set: { state.setLanguage($0 ? 1 : 0) })) {
            Text("Tiếng Việt   \(Hotkey(raw: hotkeyRaw).display)")
        }
        Toggle("Tự chuyển Anh/Việt khi gõ", isOn: Binding(get: { autoSwitch == 1 }, set: { autoSwitch = $0 ? 1 : 0; Preferences.apply() }))
        Divider()
        Button("Nhật ký gõ…") { open(.log) }
        Button("Cài đặt…") { open(.general) }
            .keyboardShortcut(",")
        Divider()
        Button("Thoát Vikey") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// Opens the settings window on a pane and brings it in front of other apps.
    private func open(_ pane: SettingsPane) {
        UserDefaults.standard.set(pane.rawValue, forKey: "openSettingsPane")
        WindowFocus.bringForward()
        openWindow(id: "settings")
        NotificationCenter.default.post(name: .vikeyShowPane, object: pane.rawValue)
        DispatchQueue.main.async { WindowFocus.focusVisibleWindow() }
    }
}

extension Notification.Name {
    static let vikeyShowPane = Notification.Name("VikeyShowPane")
}

/// A menu bar app has no Dock icon, so its windows can open behind others. While a window is
/// open, Vikey becomes a regular app (Dock icon, ⌘Tab) and goes back to menu-bar-only when the last one closes.
enum WindowFocus {
    private static var observer: Any?

    static func bringForward() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
                DispatchQueue.main.async {
                    let open = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain && $0 !== note.object as? NSWindow }
                    if !open { NSApp.setActivationPolicy(.accessory) }
                }
            }
        }
    }

    static func focusVisibleWindow() {
        NSApp.windows.first { $0.isVisible && $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
