import SwiftUI

struct MenuBarContent: View {
    @EnvironmentObject var state: AppState
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
        Toggle("Tự chuyển Anh/Việt", isOn: Binding(get: { autoSwitch == 1 }, set: { autoSwitch = $0 ? 1 : 0; Preferences.apply() }))
        Divider()
        Button("Mở Vikey…") { Windows.main.show() }
            .keyboardShortcut(",")
        Divider()
        Button("Hướng dẫn…") { OnboardingWindow.show() }
        Button("Kiểm tra cập nhật…") { Updater.shared.checkForUpdates() }
        Button("Giới thiệu Vikey") { AboutPanel.show() }
        Button("Thoát Vikey") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// Debug items, in the Vikey app menu only (not the menu bar icon).
struct DebugMenu: View {
    @AppStorage(PrefKey.typingLogEnabled) private var logEnabled = 0

    var body: some View {
        Menu("Gỡ lỗi") {
            Toggle("Ghi nhật ký gõ", isOn: Binding(get: { logEnabled == 1 }, set: { logEnabled = $0 ? 1 : 0; Preferences.apply() }))
            Button("Xem nhật ký gõ…") { Windows.history.show() }
                .disabled(logEnabled == 0)
        }
    }
}
