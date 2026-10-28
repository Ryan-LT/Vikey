import SwiftUI

/// Vikey's windows are plain NSWindows hosting SwiftUI, so they can be opened from anywhere
/// (menu bar, reopening the app from Finder, onboarding) and always come to the front.
@MainActor
final class HostedWindow<Content: View> {
    private var window: NSWindow?
    private let title: String
    private let size: NSSize?
    private let resizable: Bool
    var hideTitle = false
    private let content: () -> Content

    /// size: nil = fit the SwiftUI content exactly.
    init(title: String, size: NSSize?, resizable: Bool, content: @escaping () -> Content) {
        self.title = title
        self.size = size
        self.resizable = resizable
        self.content = content
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: content().environmentObject(AppState.shared))
            host.sizingOptions = []   // size is set once below; live content-size tracking loops in AppKit's constraint pass
            let w = NSWindow(contentViewController: host)
            w.title = title
            w.styleMask = resizable ? [.titled, .closable, .miniaturizable, .resizable] : [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            if hideTitle {
                w.titleVisibility = .hidden
                w.titlebarAppearsTransparent = true
            }
            w.setContentSize(size ?? host.view.fittingSize)
            w.center()
            window = w
        }
        WindowFocus.bringForward()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }
}

@MainActor
enum Windows {
    static let main: HostedWindow<MainView> = {
        let w = HostedWindow(title: "Vikey", size: nil, resizable: false) { MainView() }
        w.hideTitle = true
        return w
    }()
    static let history = HostedWindow(title: "Nhật ký gõ", size: NSSize(width: 780, height: 640), resizable: true) { TypingLogView() }
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
}

/// The standard macOS About window, with the author and the OpenKey credit.
enum AboutPanel {
    @MainActor static func show() {
        WindowFocus.bringForward()
        let credits = NSMutableAttributedString()
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        let base: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: center]
        func add(_ text: String, link: String? = nil) {
            var attrs = base
            if let link { attrs[.link] = URL(string: link) }
            credits.append(NSAttributedString(string: text, attributes: attrs))
        }
        add("Tony Dinh\n")
        add("Dựa trên ")
        add("OpenKey", link: "https://github.com/tuyenvm/OpenKey")
        add(" của Tuyen Mai\nMã nguồn mở theo giấy phép GPL-3.0\n\n")
        add("vikey.app", link: "https://vikey.app")
        add("  ·  ")
        add("GitHub", link: "https://github.com/tonyminibot/Vikey")
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits, .applicationName: "Vikey"])
    }
}
