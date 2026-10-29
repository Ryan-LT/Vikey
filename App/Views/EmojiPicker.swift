import AppKit
import SwiftUI

/// The emoji picker: a hotkey (off by default, set in the main window) opens a panel in the middle of the
/// screen. Typing searches in English and Vietnamese (EmojiSearch.swift), arrows move, Return types the emoji
/// into the app you were in, Esc closes. The panel never activates Vikey, so that app keeps its cursor.
enum PrefEmoji {
    static let enabled = "EmojiPicker"      // 0/1, read by the core
    static let hotkey = "EmojiHotkey"       // Hotkey raw, 0 = not set
    static let tone = "EmojiSkinTone"       // 0 = default yellow, 1-5 light … dark
    static let recents = "EmojiRecents"
}

final class EmojiPicker {
    static let shared = EmojiPicker()
    private var panel: EmojiPanel?
    let model = EmojiPickerModel()

    /// At launch: the hotkey handler, and the panel built ahead of time so it opens instantly.
    func install() {
        VikeyCore.setEmojiHotkeyHandler { [weak self] in self?.toggle() }
        DispatchQueue.global(qos: .userInitiated).async { _ = EmojiIndex.shared }
        DispatchQueue.main.async { if UserDefaults.standard.integer(forKey: PrefEmoji.enabled) != 0 { self.prepare() } }
    }

    private func prepare() {
        guard panel == nil else { return }
        let p = EmojiPanel(model: model)
        p.onClose = { [weak self] in self?.close() }
        panel = p
    }

    func toggle() { panel?.isVisible == true ? close() : open() }

    func open() {
        prepare()
        guard let p = panel else { return }
        model.reset(vietnamese: VikeyCore.language() == 1)
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: f.midX - p.frame.width / 2, y: f.midY - p.frame.height / 2 + f.height * 0.08))
        }
        VikeyCore.setEmojiPickerOpen(true)
        p.makeKeyAndOrderFront(nil)
    }

    func close() {
        VikeyCore.setEmojiPickerOpen(false)
        panel?.orderOut(nil)
    }

    /// Types the emoji into the app that was in front, after the panel is gone.
    func choose(_ e: Emoji) {
        let text = e.withSkin(model.tone)
        model.remember(e)
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { VikeyCore.insertText(text) }
    }
}

/// Borderless, non-activating, but able to take keys.
final class EmojiPanel: NSPanel {
    var onClose: (() -> Void)?
    private let model: EmojiPickerModel

    init(model: EmojiPickerModel) {
        self.model = model
        super.init(contentRect: NSRect(x: 0, y: 0, width: EmojiGridView.width, height: 404),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        backgroundColor = .clear
        hasShadow = true
        let fx = NSVisualEffectView()
        fx.material = .popover; fx.state = .active; fx.blendingMode = .behindWindow
        fx.wantsLayer = true; fx.layer?.cornerRadius = 14; fx.layer?.masksToBounds = true
        let host = NSHostingView(rootView: EmojiGridView(model: model))
        host.translatesAutoresizingMaskIntoConstraints = false
        fx.addSubview(host)
        NSLayoutConstraint.activate([host.leadingAnchor.constraint(equalTo: fx.leadingAnchor), host.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
                                     host.topAnchor.constraint(equalTo: fx.topAnchor), host.bottomAnchor.constraint(equalTo: fx.bottomAnchor)])
        contentView = fx
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func resignKey() { super.resignKey(); if isVisible { onClose?() } }   // clicked elsewhere

    override func keyDown(with e: NSEvent) {
        let cmd = e.modifierFlags.contains(.command), opt = e.modifierFlags.contains(.option)
        switch e.keyCode {
        case 53: onClose?()                                                    // Esc
        case 36, 76: if let x = model.current { EmojiPicker.shared.choose(x) }  // Return
        case 123: model.move(-1)
        case 124: model.move(1)
        case 125: model.move(EmojiGridView.columns)
        case 126: model.move(-EmojiGridView.columns)
        case 51: cmd ? model.setRaw("") : opt ? model.deleteWord() : model.deleteBack()   // ⌫
        default:
            if cmd {
                if e.charactersIgnoringModifiers == "v", let s = NSPasteboard.general.string(forType: .string) { model.setRaw(model.raw + s) }
                else if e.charactersIgnoringModifiers == "w" { onClose?() }
                return
            }
            if let c = e.characters, !c.isEmpty, c.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
                model.setRaw(model.raw + c)
            }
        }
    }
}

final class EmojiPickerModel: ObservableObject {
    @Published private(set) var raw = ""
    @Published private(set) var vietnamese = true
    @Published private(set) var results: [Emoji] = []          // what the grid shows when searching
    @Published var selected = 0
    @Published var tone = UserDefaults.standard.integer(forKey: PrefEmoji.tone) {
        didSet { UserDefaults.standard.set(tone, forKey: PrefEmoji.tone) }
    }
    @Published private(set) var recents: [Emoji] = []
    private var observer: Any?
    var mouseAtOpen = NSPoint.zero   // hover selects only after the mouse really moves

    /// The emoji this Mac can draw (newer Unicode versions show as boxes on older macOS).
    static let maxVersion: Double = {
        if #available(macOS 26.4, *) { return 17 }
        if #available(macOS 15.4, *) { return 16 }
        if #available(macOS 14.4, *) { return 15.1 }
        if #available(macOS 13.3, *) { return 15 }
        return 14
    }()
    lazy var all: [Emoji] = EmojiIndex.shared.all.filter { $0.version <= Self.maxVersion }
    lazy var groups: [(Int, [Emoji])] = Dictionary(grouping: all, by: \.group).sorted { $0.key < $1.key }.map { ($0.key, $0.value) }

    init() {
        observer = NotificationCenter.default.addObserver(forName: .VikeyLanguageDidChange, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.vietnamese = VikeyCore.language() == 1; self.search()
        }
    }

    var display: String { vietnamese ? Telex.convert(raw) : raw }
    var searching: Bool { !raw.trimmingCharacters(in: .whitespaces).isEmpty }
    /// Everything the arrows walk through, in grid order.
    var visible: [Emoji] { searching ? results : recents + all }
    var current: Emoji? { let v = visible; return v.indices.contains(selected) ? v[selected] : nil }

    func reset(vietnamese: Bool) {
        self.vietnamese = vietnamese
        raw = ""; results = []; selected = 0; mouseAtOpen = NSEvent.mouseLocation
        let byChar = Dictionary(all.map { ($0.char, $0) }, uniquingKeysWith: { a, _ in a })
        recents = (UserDefaults.standard.stringArray(forKey: PrefEmoji.recents) ?? []).compactMap { byChar[$0] }
    }

    func setRaw(_ s: String) { raw = s; search() }
    func deleteBack() { if !raw.isEmpty { raw.removeLast(); search() } }
    func deleteWord() {
        var r = raw
        while r.last == " " { r.removeLast() }
        while let l = r.last, l != " " { r.removeLast() }
        setRaw(r)
    }

    private func search() {
        results = searching ? EmojiIndex.shared.search(raw, vietnamese: vietnamese, limit: 400, among: all) : []
        selected = 0
    }

    func move(_ d: Int) {
        let n = visible.count
        guard n > 0 else { return }
        selected = min(max(0, selected + d), n - 1)
    }

    func remember(_ e: Emoji) {
        var r = UserDefaults.standard.stringArray(forKey: PrefEmoji.recents) ?? []
        r.removeAll { $0 == e.char }
        r.insert(e.char, at: 0)
        UserDefaults.standard.set(Array(r.prefix(EmojiGridView.columns * 2)), forKey: PrefEmoji.recents)
    }
}

struct EmojiGridView: View {
    static let columns = 9
    static let cell: CGFloat = 44
    static let width = CGFloat(columns) * cell + 24
    @ObservedObject var model: EmojiPickerModel
    @State private var caret = true

    private static let groupNames = ["Mặt cười & cảm xúc", "Người & cơ thể", "", "Động vật & thiên nhiên", "Đồ ăn & thức uống",
                                     "Du lịch & địa điểm", "Hoạt động", "Đồ vật", "Biểu tượng", "Cờ"]
    private static let groupNamesEN = ["Smileys & Emotion", "People & Body", "", "Animals & Nature", "Food & Drink",
                                       "Travel & Places", "Activities", "Objects", "Symbols", "Flags"]

    var body: some View {
        VStack(spacing: 0) {
            searchField.padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 8)
            Divider().opacity(0.5)
            grid
            Divider().opacity(0.5)
            footer.padding(.horizontal, 14).frame(height: 44)
        }
        .frame(width: Self.width, height: 404)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            HStack(spacing: 1) {
                Text(model.display).lineLimit(1)
                Rectangle().fill(Color.brand).frame(width: 2, height: 18).opacity(caret ? 1 : 0)
                if model.raw.isEmpty {
                    Text(model.vietnamese ? "Tìm emoji: ngựa, horse…" : "Search emoji: horse, ngựa…").foregroundStyle(.tertiary).padding(.leading, 2)
                }
            }
            .font(.system(size: 17))
            Spacer(minLength: 0)
            Text(model.vietnamese ? "VI" : "EN").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2).background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
        }
        .onReceive(Timer.publish(every: 0.53, on: .main, in: .common).autoconnect()) { _ in caret.toggle() }
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    if model.searching {
                        if model.results.isEmpty {
                            Text(model.vietnamese ? "Không tìm thấy emoji nào" : "No emoji found")
                                .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 110)
                        } else { cells(model.results, offset: 0) }
                    } else {
                        if !model.recents.isEmpty {
                            Section(header: header(model.vietnamese ? "Dùng gần đây" : "Frequently Used")) { cells(model.recents, offset: 0) }
                        }
                        ForEach(model.groups, id: \.0) { g, list in
                            Section(header: header(model.vietnamese ? Self.groupNames[g] : Self.groupNamesEN[g])) {
                                cells(list, offset: model.recents.count + model.groups.prefix { $0.0 < g }.reduce(0) { $0 + $1.1.count })
                            }
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 8)
            }
            .onChange(of: model.selected) { i in proxy.scrollTo(i) }
            .onChange(of: model.raw) { _ in proxy.scrollTo(0, anchor: .top) }
        }
    }

    private func header(_ t: String) -> some View {
        Text(t).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6).padding(.top, 2)
            .background(.regularMaterial.opacity(0.0001))
    }

    private func cells(_ list: [Emoji], offset: Int) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: Self.columns), spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.offset) { i, e in
                let idx = offset + i
                Text(e.withSkin(model.tone))
                    .font(.system(size: 28))
                    .frame(maxWidth: .infinity).frame(height: Self.cell)
                    .background(RoundedRectangle(cornerRadius: 8).fill(idx == model.selected ? Color.brand.opacity(0.22) : .clear))
                    .contentShape(Rectangle())
                    .onHover { if $0 && NSEvent.mouseLocation != model.mouseAtOpen { model.selected = idx } }
                    .onTapGesture { EmojiPicker.shared.choose(e) }
                    .id(idx)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let e = model.current {
                Text(e.withSkin(model.tone)).font(.system(size: 22))
                Text(model.vietnamese ? e.nameVI : e.nameEN).font(.callout).lineLimit(1).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                ForEach(0..<6) { t in
                    Button(["✋", "✋🏻", "✋🏼", "✋🏽", "✋🏾", "✋🏿"][t]) { model.tone = t }
                }
            } label: { Text(["✋", "✋🏻", "✋🏼", "✋🏽", "✋🏾", "✋🏿"][model.tone]).font(.system(size: 18)) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help(model.vietnamese ? "Màu da" : "Skin tone")
        }
    }
}
