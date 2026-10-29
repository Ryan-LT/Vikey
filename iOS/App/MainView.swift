import SwiftUI

/// Settings (shared with the keyboard), a place to try it, and the keyboard's status.
struct MainView: View {
    @AppStorage(VKSettings.Key.autoSwitch, store: VKSettings.defaults) private var autoSwitch = true
    @AppStorage(VKSettings.Key.pauseAfterManual, store: VKSettings.defaults) private var pause = true
    @AppStorage(VKSettings.Key.englishForWebFields, store: VKSettings.defaults) private var webEnglish = true
    @AppStorage(VKSettings.Key.modernOrthography, store: VKSettings.defaults) private var modern = true
    @AppStorage(VKSettings.Key.spelling, store: VKSettings.defaults) private var spelling = true
    @AppStorage(VKSettings.Key.restoreIfInvalid, store: VKSettings.defaults) private var restore = true
    @AppStorage(VKSettings.Key.autoCapitalize, store: VKSettings.defaults) private var autoCap = true
    @AppStorage(VKSettings.Key.doubleSpacePeriod, store: VKSettings.defaults) private var doubleSpace = true
    @AppStorage(VKSettings.Key.haptics, store: VKSettings.defaults) private var haptics = true
    @AppStorage(VKSettings.Key.diagnostics, store: VKSettings.defaults) private var diagnostics = false
    @AppStorage(VKSettings.Key.suggestions, store: VKSettings.defaults) private var suggestions = true
    @AppStorage(VKSettings.Key.autoCorrect, store: VKSettings.defaults) private var autoCorrect = true
    @AppStorage("didOnboard") private var didOnboard = true
    @State private var added = KeyboardStatus.isAdded
    @State private var sample = ""
    @State private var logText = ""
    @Environment(\.scenePhase) private var phase

    var body: some View {
        NavigationStack {
            Form {
                if !added {
                    Section {
                        Button { KeyboardStatus.openSettings() } label: {
                            Label("Thêm bàn phím Vikey trong Cài đặt", systemImage: "keyboard.badge.ellipsis")
                        }
                    } footer: {
                        Text("Cài đặt › Vikey › Bàn phím › bật Vikey.")
                    }
                }
                Section("Thử bàn phím") {
                    TextField("Chạm vào đây, chọn Vikey bằng 🌐 rồi gõ", text: $sample, axis: .vertical)
                        .lineLimit(2...5)
                        .onChange(of: sample) { _, t in
                            #if DEBUG
                            // simulator tests read what was typed from here
                            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("typed.txt")
                            try? t.write(to: url, atomically: true, encoding: .utf8)
                            #endif
                        }
                }
                Section("Tự chuyển") {
                    Toggle(isOn: $autoSwitch) { Tip("Tự chuyển Anh/Việt khi gõ", "Gõ một từ tiếng Anh khi đang ở tiếng Việt (hoặc ngược lại), Vikey tự sửa từ đó và chuyển chế độ. Bấm xoá ngay sau đó để hoàn tác.") }
                    Toggle(isOn: $pause) { Tip("Tạm dừng 5 giây sau khi chuyển tay", "Khi bạn tự bấm phím VI/EN, Vikey không tự chuyển trong 5 giây, để giữ đúng lựa chọn của bạn.") }
                        .disabled(!autoSwitch)
                    Toggle(isOn: $webEnglish) { Tip("Ô địa chỉ web và email gõ tiếng Anh", "Trong ô nhập địa chỉ web, email hoặc tìm kiếm web, Vikey bắt đầu bằng tiếng Anh và quay lại ngôn ngữ cũ khi bạn rời ô đó.") }
                }
                Section("Gõ tiếng Việt") {
                    Picker(selection: $modern) {
                        Text("hoà, thuý").tag(true)
                        Text("hòa, thúy").tag(false)
                    } label: { Tip("Đặt dấu", "Vị trí dấu thanh với oa, oe, uy: kiểu mới (hoà, thuý) hoặc kiểu cũ (hòa, thúy).") }
                    Toggle(isOn: $spelling) { Tip("Kiểm tra chính tả", "Chỉ bỏ dấu khi từ đang gõ đúng quy tắc chính tả tiếng Việt.") }
                    Toggle(isOn: $restore) { Tip("Từ không phải tiếng Việt thì giữ nguyên phím gõ", "Khi gõ xong một từ sai chính tả tiếng Việt, Vikey trả lại đúng các phím bạn đã gõ.") }
                        .disabled(!spelling)
                }
                Section("Bàn phím") {
                    Toggle(isOn: $suggestions) { Tip("Gợi ý từ", "Hiện các từ gợi ý phía trên bàn phím, cả tiếng Việt lẫn tiếng Anh. Chạm vào một từ để dùng nó.") }
                    Toggle(isOn: $autoCorrect) { Tip("Tự sửa lỗi gõ", "Khi bạn chạm lệch phím (\"teh\" thay vì \"the\"), Vikey sửa từ đó khi bạn bấm phím cách. Bấm xoá ngay sau đó để giữ lại từ bạn gõ.") }
                    Toggle(isOn: $autoCap) { Tip("Tự viết hoa đầu câu", "Chữ đầu tiên của câu được viết hoa, như bàn phím của iPhone.") }
                    Toggle(isOn: $haptics) { Tip("Rung khi gõ phím", "Rung nhẹ mỗi khi chạm phím, như bàn phím của iPhone. Cần bật Cho phép Truy cập đầy đủ: Cài đặt › Vikey › Bàn phím. Vikey chỉ dùng quyền này để rung, không bao giờ gửi gì ra khỏi máy.") }
                    Toggle(isOn: $doubleSpace) { Tip("Chạm hai lần phím cách để thêm dấu chấm", "Chạm nhanh hai lần phím cách để thêm dấu chấm và một khoảng trắng.") }
                }
                Section {
                    Toggle(isOn: $diagnostics) { Tip("Gỡ lỗi bàn phím", "Phía trên các phím hiện thời gian xử lý mỗi lần chạm, số lần rung và số lần chạm iOS gửi tới, và ghi vào nhật ký. Nhật ký không chứa chữ bạn gõ, chỉ có thời gian và loại phím (chữ, dấu cách, xoá…). Cần Truy cập đầy đủ để bàn phím ghi được nhật ký.") }
                    if diagnostics {
                        ShareLink(item: logText.isEmpty ? "(nhật ký trống)" : logText, subject: Text("Vikey keyboard log")) {
                            Label("Gửi nhật ký", systemImage: "square.and.arrow.up")
                        }
                        Button("Xoá nhật ký", role: .destructive) { KBLog.clear(); logText = "" }
                        Text(logText.isEmpty ? LocalizedStringKey("Chưa có gì. Mở bàn phím Vikey và gõ thử.") : LocalizedStringKey("\(logText.split(separator: "\n").count) dòng")).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: { Text("Gỡ lỗi") }
                Section {
                    Button { KeyboardStatus.openSettings() } label: {
                        LabeledContent("Ngôn ngữ ứng dụng", value: Locale.current.localizedString(forLanguageCode: Bundle.main.preferredLocalizations.first ?? "en") ?? "")
                    }
                    .foregroundStyle(.primary)
                    Button("Xem lại hướng dẫn") { didOnboard = false }
                    NavigationLink("Ghi nhận") { AcknowledgementsView() }
                    Link("vikey.app", destination: URL(string: "https://vikey.app")!)
                    LabeledContent("Phiên bản", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                } footer: {
                    Text("Vikey được thiết kế và phát triển bởi Tony Dinh, dựa trên dự án mã nguồn mở OpenKey của Tuyen Mai. Mã nguồn mở theo giấy phép GPL-3.0.")
                }
            }
            .navigationTitle("Vikey")
        }
        .onChange(of: phase) { _, p in if p == .active { added = KeyboardStatus.isAdded; logText = KBLog.read() } }
        .onAppear { logText = KBLog.read() }
    }
}

/// A setting's title with a (?) that explains it.
struct Tip: View {
    let title: LocalizedStringKey, tip: LocalizedStringKey
    @State private var shown = false
    init(_ title: LocalizedStringKey, _ tip: LocalizedStringKey) { self.title = title; self.tip = tip }
    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Button { shown = true } label: { Image(systemName: "questionmark.circle").foregroundStyle(.tertiary) }
                .buttonStyle(.plain)
                .popover(isPresented: $shown) {
                    Text(tip).font(.callout).padding().frame(width: 280).fixedSize(horizontal: false, vertical: true)
                        .presentationCompactAdaptation(.popover)
                }
        }
    }
}
