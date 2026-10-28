import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, typing, switching, log, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "Chung"
        case .typing: return "Gõ tiếng Việt"
        case .switching: return "Tự chuyển"
        case .log: return "Nhật ký gõ"
        case .about: return "Giới thiệu"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .typing: return "character.cursor.ibeam"
        case .switching: return "arrow.left.arrow.right"
        case .log: return "chart.bar.xaxis"
        case .about: return "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: return .gray
        case .typing: return .indigo
        case .switching: return .blue
        case .log: return .teal
        case .about: return .secondary
        }
    }
}

/// One window, System Settings style: a sidebar of panes on the left, the pane on the right.
struct SettingsView: View {
    @SceneStorage("settings.pane") private var paneRaw = SettingsPane.general.rawValue

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: Binding(get: { SettingsPane(rawValue: paneRaw) }, set: { paneRaw = ($0 ?? .general).rawValue })) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    Image(systemName: pane.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(pane.tint.gradient))
                }
                .tag(pane)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            let pane = SettingsPane(rawValue: paneRaw) ?? .general
            Group {
                switch pane {
                case .general: GeneralSettings()
                case .typing: TypingSettings()
                case .switching: SwitchingSettings()
                case .log: TypingLogView()
                case .about: AboutView()
                }
            }
            .navigationTitle(pane.title)
        }
        .frame(minWidth: 780, minHeight: 640)
        .onReceive(NotificationCenter.default.publisher(for: .vikeyShowPane)) { note in
            if let raw = note.object as? String { paneRaw = raw }
        }
        .onAppear {
            if let raw = UserDefaults.standard.string(forKey: "openSettingsPane") { paneRaw = raw }
        }
    }
}

/// Binds an Int (0/1) preference used by the C core to a Toggle, applying it on change.
private func flag(_ value: Binding<Int>) -> Binding<Bool> {
    Binding(get: { value.wrappedValue != 0 }, set: { value.wrappedValue = $0 ? 1 : 0; Preferences.apply() })
}

private struct GeneralSettings: View {
    @EnvironmentObject var state: AppState
    @AppStorage(PrefKey.hotkey) private var hotkeyRaw = Hotkey.defaultValue
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section {
                LabeledContent("Phím chuyển Anh/Việt") {
                    HotkeyRecorder(raw: Binding(get: { hotkeyRaw }, set: { hotkeyRaw = $0; Preferences.apply() }))
                }
                Toggle("Kêu bíp khi chuyển", isOn: Binding(
                    get: { Hotkey(raw: hotkeyRaw).beep },
                    set: { var h = Hotkey(raw: hotkeyRaw); h.beep = $0; hotkeyRaw = h.raw; Preferences.apply() }))
            } footer: {
                Text("Bấm vào phím tắt để đổi. Dùng một phím kèm phím bổ trợ (⌥Z) hoặc chỉ phím bổ trợ (⌃⇧).")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Mở Vikey khi đăng nhập", isOn: Binding(get: { launchAtLogin }, set: { LaunchAtLogin.set($0); launchAtLogin = LaunchAtLogin.isEnabled }))
            }
            Section {
                LabeledContent("Quyền Trợ năng") {
                    if state.isRunning {
                        Label("Đã cấp", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Cấp quyền…") { OnboardingWindow.show() }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct TypingSettings: View {
    @AppStorage(PrefKey.modernOrthography) private var modern = 1
    @AppStorage(PrefKey.spelling) private var spelling = 1
    @AppStorage(PrefKey.restoreIfInvalid) private var restore = 1

    var body: some View {
        Form {
            Section {
                Picker("Đặt dấu", selection: Binding(get: { modern }, set: { modern = $0; Preferences.apply() })) {
                    Text("Kiểu mới: hoà, thuý").tag(1)
                    Text("Kiểu cũ: hòa, thúy").tag(0)
                }
            }
            Section {
                Toggle("Kiểm tra chính tả", isOn: flag($spelling))
                Toggle("Gõ sai chính tả thì giữ nguyên phím đã gõ", isOn: flag($restore))
                    .disabled(spelling == 0)
            } footer: {
                Text("Ví dụ: gõ \"windows\" sẽ ra đúng \"windows\" thay vì chữ tiếng Việt sai.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct SwitchingSettings: View {
    @AppStorage(PrefKey.autoSwitch) private var autoSwitch = 1
    @AppStorage(PrefKey.smartSwitch) private var smartSwitch = 1
    @AppStorage(PrefKey.smartSwitchPerSite) private var perSite = true

    var body: some View {
        Form {
            Section {
                Toggle("Tự chuyển Anh/Việt khi gõ", isOn: flag($autoSwitch))
            } footer: {
                Text("Gõ nhầm chế độ thì Vikey tự sửa từ và chuyển ngôn ngữ. Bấm Delete ngay sau đó để hoàn tác.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Nhớ ngôn ngữ cho từng ứng dụng", isOn: flag($smartSwitch))
                Toggle("Nhớ riêng cho từng trang web", isOn: Binding(get: { perSite }, set: { perSite = $0; Preferences.apply() }))
                    .disabled(smartSwitch == 0)
            } footer: {
                Text("Với trình duyệt, Vikey nhớ ngôn ngữ theo từng trang web. Lần đầu dùng mỗi trình duyệt, macOS sẽ hỏi quyền cho Vikey đọc địa chỉ trang.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct AboutView: View {
    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return "\(v) (\(b))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            Text("Vikey").font(.title.weight(.bold))
            Text("Phiên bản \(version)").foregroundStyle(.secondary)
            Text("Dựa trên OpenKey của Tuyen Mai. Mã nguồn mở theo giấy phép GPL-3.0.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Link("Mã nguồn trên GitHub", destination: URL(string: "https://github.com/tonyminibot/Vikey")!)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}
