import UIKit

/// The Vikey keyboard: keys go through the same engine and driver as the Mac app
/// (Engine/Driver), and its edits are applied to the text field.
/// The keyboard's root view: adopting UIInputViewAudioFeedback is what makes playInputClick() click.
final class KeyboardInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}

final class KeyboardViewController: UIInputViewController, KeyboardViewDelegate {
    private let driver = VKDriver()
    private var keyboard: KeyboardView!
    private var heightConstraint: NSLayoutConstraint?
    private var lastContext: String?          // text before the cursor after our last edit
    private var lastShiftTap: TimeInterval = 0
    private var lastSpace: TimeInterval = 0
    private var fieldLanguage: Int?           // language to restore after a web/email field
    private let languageKey = "Language"
    /// The text field. Tests swap in a counting proxy (performance lock: one text read per key).
    lazy var proxy: UITextDocumentProxy = textDocumentProxy
    // settings, read once when the keyboard appears (reading shared defaults per key is slow)
    private var webFieldsEnglish = true, autoCapitalize = true, doubleSpacePeriod = true, haptics = true

    override func loadView() {
        let v = KeyboardInputView(frame: .zero, inputViewStyle: .keyboard)
        v.allowsSelfSizing = true
        inputView = v
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        keyboard = KeyboardView(frame: view.bounds)
        keyboard.delegate = self
        keyboard.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboard)
        NSLayoutConstraint.activate([
            keyboard.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboard.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboard.topAnchor.constraint(equalTo: view.topAnchor),
            keyboard.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        let h = view.heightAnchor.constraint(equalToConstant: KeyboardView.keyboardHeight(compactHeight: traitCollection.verticalSizeClass == .compact))
        h.priority = .defaultHigh
        h.isActive = true
        heightConstraint = h
        let saved = UserDefaults.standard.object(forKey: languageKey) as? Int ?? 1
        driver.language = saved
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadSettings()
        startField()
        refresh()
        if Diag.on {
            KBLog.add("open: fullAccess=\(hasFullAccess) haptics=\(keyboard.haptics) field=\(proxy.keyboardType?.rawValue ?? -1) return=\(proxy.returnKeyType?.rawValue ?? -1) width=\(Int(view.bounds.width))")
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        KBLog.flush()
        super.viewWillDisappear(animated)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        if Diag.on { KBLog.add("memory warning") ; KBLog.flush() }
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        heightConstraint?.constant = KeyboardView.keyboardHeight(compactHeight: traitCollection.verticalSizeClass == .compact)
        keyboard?.setNeedsLayout()
        if previous?.userInterfaceStyle != traitCollection.userInterfaceStyle { refresh() }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        keyboard.showsGlobe = needsInputModeSwitchKey
        if let g = keyboard.globeButton {
            g.removeTarget(nil, action: nil, for: .allEvents)
            g.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        }
    }

    private func loadSettings() {
        VKSettings.register()
        let d = VKSettings.defaults
        driver.autoSwitch = d.bool(forKey: VKSettings.Key.autoSwitch)
        driver.pauseAfterManual = d.bool(forKey: VKSettings.Key.pauseAfterManual) ? 5 : 0
        driver.modernOrthography = d.bool(forKey: VKSettings.Key.modernOrthography)
        driver.spelling = d.bool(forKey: VKSettings.Key.spelling)
        driver.restoreIfInvalid = d.bool(forKey: VKSettings.Key.restoreIfInvalid)
        webFieldsEnglish = d.bool(forKey: VKSettings.Key.englishForWebFields)
        autoCapitalize = d.bool(forKey: VKSettings.Key.autoCapitalize)
        doubleSpacePeriod = d.bool(forKey: VKSettings.Key.doubleSpacePeriod)
        haptics = d.bool(forKey: VKSettings.Key.haptics)
        Diag.on = d.bool(forKey: VKSettings.Key.diagnostics)
        keyboard?.diagnostics = Diag.on ? String(localized: "Gõ để xem thông số") : nil
        heightConstraint?.constant = KeyboardView.keyboardHeight(compactHeight: traitCollection.verticalSizeClass == .compact)
        keyboard?.setNeedsLayout()
        keyboard?.haptics = haptics && hasFullAccess   // haptics need Full Access; without it keys click
    }

    /// A new text field: start fresh; web addresses and email start in English (and go back after).
    private func startField() {
        driver.resetContext()
        let type = proxy.keyboardType ?? .default
        let webField = type == .URL || type == .emailAddress || type == .webSearch
        if webField && webFieldsEnglish {
            if fieldLanguage == nil { fieldLanguage = driver.language }
            driver.language = 0
        } else if let l = fieldLanguage {
            driver.language = l
            fieldLanguage = nil
        }
        lastContext = proxy.documentContextBeforeInput
        updateAutoShift(lastContext ?? "")
    }

    private var now: Double { ProcessInfo.processInfo.systemUptime }

    private func refresh() {
        keyboard.dark = proxy.keyboardAppearance == .dark || traitCollection.userInterfaceStyle == .dark
        keyboard.languageTitle = driver.language == 1 ? "Tiếng Việt" : "English"
        keyboard.languageShort = driver.language == 1 ? "VI" : "EN"
        let (title, blue) = Self.returnTitle(proxy.returnKeyType ?? .default)
        keyboard.returnTitle = title
        keyboard.returnIsBlue = blue
    }

    private static func returnTitle(_ t: UIReturnKeyType) -> (String, Bool) {
        switch t {
        case .go: return (String(localized: "Đi"), true)
        case .search, .google, .yahoo: return (String(localized: "Tìm"), true)
        case .send: return (String(localized: "Gửi"), true)
        case .done: return (String(localized: "Xong"), true)
        case .next: return (String(localized: "Tiếp"), false)
        case .join: return (String(localized: "Tham gia"), true)
        case .route: return (String(localized: "Chỉ đường"), true)
        case .continue: return (String(localized: "Tiếp tục"), true)
        case .emergencyCall: return ("SOS", true)
        default: return ("return", false)
        }
    }

    // MARK: text changes from outside (cursor moved, field cleared, another keyboard)

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        externalChange()
        refresh()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        externalChange()
    }

    private func externalChange() {
        let ctx = proxy.documentContextBeforeInput
        if ctx != lastContext {
            if Diag.on { KBLog.add("reset: text changed outside the keyboard (cursor moved, or the app changed it)") }
            driver.resetContext()
            lastContext = ctx
            updateAutoShift(ctx ?? "")
        }
    }

    // MARK: keys

    func keyboard(_ view: KeyboardView, didTap kind: KeyKind) {
        if Diag.on {
            switch kind {
            case .char(let c): Diag.lastKind = c.first?.isLetter == true ? "letter" : "symbol"
            case .space: Diag.lastKind = "space"
            case .backspace: Diag.lastKind = "delete"
            case .returnKey: Diag.lastKind = "return"
            default: Diag.lastKind = "other"
            }
        }
        switch kind {
        case .char(let c):
            var s = c
            if keyboard.layer_ == .letters && keyboard.shift != .off { s = c.uppercased() }
            type(s)
            if keyboard.shift == .on { keyboard.shift = .off }
            if keyboard.layer_ != .letters && (c == "'" ) { keyboard.layer_ = .letters }
        case .space:
            spaceKey()
        case .returnKey:
            type("\n")
        case .backspace:
            backspace()
        case .shift:
            let t = now
            if keyboard.shift == .locked { keyboard.shift = .off }
            else if t - lastShiftTap < 0.35 { keyboard.shift = .locked }
            else { keyboard.shift = keyboard.shift == .on ? .off : .on }
            lastShiftTap = t
        case .layer(let l):
            keyboard.layer_ = l
        case .language:
            driver.manualSwitch(at: now)
            fieldLanguage = nil
            saveLanguage()
            refresh()
        case .globe:
            advanceToNextInputMode()
        }
    }

    func keyboardBackspaceRepeat(_ view: KeyboardView, count n: Int) {
        // like the system keyboard: characters first, whole words after ~2 seconds of holding
        guard n > 20 else { backspace(); return }
        let before = lastContext ?? ""
        guard !before.isEmpty else { return }
        var chars = Array(before), k = 0
        while let last = chars.last, last == " " { chars.removeLast(); k += 1 }
        while let last = chars.last, last != " " && last != "\n" { chars.removeLast(); k += 1 }
        for _ in 0..<max(k, 1) { proxy.deleteBackward() }
        driver.resetContext()
        afterEdit()
    }

    func keyboard(_ view: KeyboardView, insertAlternate text: String) {
        type(text)      // a character the engine doesn't know passes through and starts a new word
        if keyboard.shift == .on { keyboard.shift = .off }
    }

    func keyboard(_ view: KeyboardView, moveCursorBy offset: Int) {
        proxy.adjustTextPosition(byCharacterOffset: offset)
    }

    func keyboardCursorModeEnded(_ view: KeyboardView) {
        driver.resetContext()
        lastContext = proxy.documentContextBeforeInput
        updateAutoShift(lastContext ?? "")
    }

    private func spaceKey() {
        // double space: ". " like the system keyboard
        let before = lastContext ?? ""
        if doubleSpacePeriod, now - lastSpace < 0.6, before.hasSuffix(" "),
           let prev = before.dropLast().last, prev.isLetter || prev.isNumber {
            proxy.deleteBackward()
            proxy.insertText(". ")
            driver.resetContext()
            lastSpace = 0
            afterEdit()
            return
        }
        type(" ")
        lastSpace = now
        if keyboard.layer_ != .letters { keyboard.layer_ = .letters }
    }

    private func type(_ s: String) {
        let e = driver.typeCharacter(s, now: now)
        apply(e)
    }

    private func backspace() {
        apply(driver.backspace(at: now))
    }

    private func apply(_ e: VKEditResult) {
        // Send only what changes: "toi" + s comes back as delete "oi", insert "ói"; the "o" is kept.
        // Every call is a message to the app being typed in, which lays its text out again.
        var deletes = e.deleteCount
        var insert = e.text
        if deletes > 0, let before = lastContext, before.count >= deletes {
            let old = Array(before.suffix(deletes)), new = Array(insert)
            var same = 0
            while same < old.count && same < new.count && old[same] == new[same] { same += 1 }
            deletes -= same
            insert = String(new.dropFirst(same))
        }
        for _ in 0..<deletes { proxy.deleteBackward() }
        if !insert.isEmpty { proxy.insertText(insert) }
        Diag.edits += deletes + (insert.isEmpty ? 0 : 1)
        if e.languageChanged { saveLanguage(); refresh() }
        afterEdit()
    }

    private func afterEdit() {
        let r0 = CACurrentMediaTime()
        lastContext = proxy.documentContextBeforeInput   // one text read per key
        Diag.readMs = (CACurrentMediaTime() - r0) * 1000
        updateAutoShift(lastContext ?? "")
        if Diag.on {
            let total = (CACurrentMediaTime() - Diag.touchStart) * 1000
            keyboard.diagnostics = String(format: "touch→text %.1f ms · read %.2f ms\nvibrations %d · touches %d · edits %d", total, Diag.readMs, Diag.haptics, Diag.touches, Diag.edits)
            KBLog.add(String(format: "key=%@ total=%.1fms read=%.2fms vib=%d touches=%d edits=%d lang=%d", Diag.lastKind, total, Diag.readMs, Diag.haptics, Diag.touches, Diag.edits, driver.language))
            Diag.haptics = 0; Diag.touches = 0; Diag.edits = 0
        }
    }

    private func saveLanguage() { UserDefaults.standard.set(driver.language, forKey: languageKey) }

    /// Capital letter at the start of a sentence, like the system keyboard.
    private func updateAutoShift(_ before: String) {
        guard keyboard.layer_ == .letters, keyboard.shift != .locked else { return }
        guard autoCapitalize, (proxy.autocapitalizationType ?? .sentences) != .none else {
            if keyboard.shift == .on { keyboard.shift = .off }
            return
        }
        let trimmed = before.replacingOccurrences(of: " ", with: "")
        var start = before.isEmpty || before.hasSuffix("\n")
        if !start, before.hasSuffix(" "), let last = trimmed.last { start = ".?!".contains(last) }
        if proxy.autocapitalizationType == .allCharacters { keyboard.shift = .on; return }
        if proxy.autocapitalizationType == .words && (before.isEmpty || before.hasSuffix(" ")) { start = true }
        keyboard.shift = start ? .on : .off
    }
}
