import SwiftUI

/// Vikey's one window: the language switch on top, then every setting, compact.
struct MainView: View {
    @EnvironmentObject var state: AppState
    @AppStorage(PrefKey.hotkey) private var hotkeyRaw = Hotkey.defaultValue
    @AppStorage(PrefKey.modernOrthography) private var modern = 1
    @AppStorage(PrefKey.spelling) private var spelling = 1
    @AppStorage(PrefKey.restoreIfInvalid) private var restore = 1
    @AppStorage(PrefKey.autoSwitch) private var autoSwitch = 1
    @AppStorage(PrefKey.smartSwitch) private var smartSwitch = 1
    @AppStorage(PrefKey.smartSwitchPerSite) private var perSite = true
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                Section {
                    LabeledContent("Phím chuyển Anh/Việt") {
                        HotkeyRecorder(raw: Binding(get: { hotkeyRaw }, set: { hotkeyRaw = $0; Preferences.apply() }))
                    }
                    Toggle("Kêu bíp khi chuyển", isOn: Binding(
                        get: { Hotkey(raw: hotkeyRaw).beep },
                        set: { var h = Hotkey(raw: hotkeyRaw); h.beep = $0; hotkeyRaw = h.raw; Preferences.apply() }))
                }
                Section("Tự chuyển") {
                    Toggle("Tự chuyển Anh/Việt khi gõ", isOn: flag($autoSwitch))
                    Toggle("Nhớ ngôn ngữ cho từng ứng dụng", isOn: flag($smartSwitch))
                    Toggle("Nhớ riêng cho từng trang web", isOn: Binding(get: { perSite }, set: { perSite = $0; Preferences.apply() }))
                        .disabled(smartSwitch == 0)
                }
                Section("Gõ tiếng Việt") {
                    Picker("Đặt dấu", selection: Binding(get: { modern }, set: { modern = $0; Preferences.apply() })) {
                        Text("hoà, thuý").tag(1)
                        Text("hòa, thúy").tag(0)
                    }
                    Toggle("Kiểm tra chính tả", isOn: flag($spelling))
                    Toggle("Từ không phải tiếng Việt thì giữ nguyên phím gõ", isOn: flag($restore))
                        .disabled(spelling == 0)
                }
                Section {
                    Toggle("Mở Vikey khi đăng nhập", isOn: Binding(get: { launchAtLogin }, set: { LaunchAtLogin.set($0); launchAtLogin = LaunchAtLogin.isEnabled }))
                    LabeledContent("Nhật ký gõ") {
                        Button("Xem…") { Windows.history.show() }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            footer
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Vikey").font(.title2.weight(.bold))
                if state.isRunning {
                    Text("Bấm \(Hotkey(raw: hotkeyRaw).display) để chuyển")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Button("Cấp quyền Trợ năng…") { OnboardingWindow.show() }
                        .buttonStyle(.link)
                }
            }
            Spacer()
            Picker("", selection: Binding(get: { state.language }, set: { state.setLanguage($0) })) {
                Text("Tiếng Việt").tag(1)
                Text("English").tag(0)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var footer: some View {
        VStack(spacing: 3) {
            Text("Vikey \(version) · Tony Dinh")
            HStack(spacing: 4) {
                Text("Dựa trên OpenKey của Tuyen Mai · GPL-3.0 ·")
                Link("vikey.app", destination: URL(string: "https://vikey.app")!)
                Text("·")
                Link("GitHub", destination: URL(string: "https://github.com/tonyminibot/Vikey")!)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.bottom, 16)
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }
}

/// Binds an Int (0/1) preference used by the C core to a Toggle, applying it on change.
func flag(_ value: Binding<Int>) -> Binding<Bool> {
    Binding(get: { value.wrappedValue != 0 }, set: { value.wrappedValue = $0 ? 1 : 0; Preferences.apply() })
}
