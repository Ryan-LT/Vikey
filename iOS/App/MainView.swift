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
    @AppStorage("didOnboard") private var didOnboard = true
    @State private var added = KeyboardStatus.isAdded
    @State private var sample = ""
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
                    TextField("Chạm vào đây, chọn Vikey bằng \(Image(systemName: "globe")) rồi gõ", text: $sample, axis: .vertical)
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
                    Toggle(isOn: $autoCap) { Tip("Tự viết hoa đầu câu", "Chữ đầu tiên của câu được viết hoa, như bàn phím của iPhone.") }
                    Toggle(isOn: $doubleSpace) { Tip("Chạm hai lần phím cách để thêm dấu chấm", "Chạm nhanh hai lần phím cách để thêm dấu chấm và một khoảng trắng.") }
                }
                Section {
                    Button("Xem lại hướng dẫn") { didOnboard = false }
                    Link("vikey.app", destination: URL(string: "https://vikey.app")!)
                    LabeledContent("Phiên bản", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                } footer: {
                    Text("Vikey được thiết kế và phát triển bởi Tony Dinh, dựa trên dự án mã nguồn mở OpenKey của Tuyen Mai. Mã nguồn mở theo giấy phép GPL-3.0.")
                }
            }
            .navigationTitle("Vikey")
        }
        .onChange(of: phase) { _, p in if p == .active { added = KeyboardStatus.isAdded } }
    }
}

/// A setting's title with a (?) that explains it.
struct Tip: View {
    let title: String, tip: String
    @State private var shown = false
    init(_ title: String, _ tip: String) { self.title = title; self.tip = tip }
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
