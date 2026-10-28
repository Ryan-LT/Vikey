import SwiftUI

@main
struct VikeyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(state)
        } label: {
            Image(nsImage: MenuBarIcon.image(vietnamese: state.language == 1))
        }

        Window("Vikey", id: "settings") {
            SettingsView()
                .environmentObject(state)
        }
        .defaultSize(width: 880, height: 680)

    }
}
