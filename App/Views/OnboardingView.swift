import SwiftUI

/// Hosts the onboarding in its own window so it can be shown from anywhere (before the menu bar is used).
enum OnboardingWindow {
    private static var window: NSWindow?

    @MainActor static func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: OnboardingView().environmentObject(AppState.shared)))
            w.title = "Vikey"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            window = w
        }
        WindowFocus.bringForward()
        window?.layoutIfNeeded()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    @MainActor static func close() { window?.close() }
}

struct OnboardingView: View {
    @EnvironmentObject var state: AppState
    @AppStorage(PrefKey.hotkey) private var hotkeyRaw = Hotkey.defaultValue

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Vikey").font(.system(size: 26, weight: .bold))
                    Text("Gõ tiếng Việt, tự chuyển Anh/Việt cho bạn.")
                        .foregroundStyle(.secondary)
                }
            }

            if state.isRunning && !UserDefaults.standard.bool(forKey: "previewPermissionStep") {
                ready
            } else {
                permission
            }
        }
        .padding(28)
        .frame(width: 500)
    }

    private var permission: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cho phép Vikey đọc phím gõ")
                .font(.title3.weight(.semibold))
            Text("Vikey cần quyền Trợ năng (Accessibility) để biến phím bạn gõ thành chữ tiếng Việt. Mọi thứ xử lý ngay trên máy, không gửi đi đâu.")
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                Label("Bấm nút bên dưới để mở Cài đặt hệ thống", systemImage: "1.circle.fill")
                Label("Bật Vikey trong danh sách Trợ năng", systemImage: "2.circle.fill")
                Label("Quay lại đây, Vikey sẽ tự bắt đầu", systemImage: "3.circle.fill")
            }
            .foregroundStyle(.secondary)
            HStack {
                Button("Mở Cài đặt hệ thống") {
                    VikeyCore.requestAccessibility()
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Spacer()
                ProgressView().controlSize(.small)
                Text("Đang chờ quyền…").foregroundStyle(.secondary)
            }
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Vikey đã sẵn sàng", systemImage: "checkmark.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.green)
            Text("Bấm \(Hotkey(raw: hotkeyRaw).display) để chuyển Anh/Việt. Khi bạn gõ nhầm chế độ, Vikey tự sửa từ và chuyển giúp bạn. Bấm Delete ngay sau đó nếu muốn hoàn tác.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Xong") { OnboardingWindow.close() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
