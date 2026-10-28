import UIKit

/// The Vikey keyboard: keys go through the same engine and driver as the Mac app
/// (Engine/Driver), and its edits are applied to the text field.
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
    private var webFieldsEnglish = true, autoCapitalize = true, doubleSpacePeriod = true, markedText = false
    /// Marked-text mode: the word being typed stays marked (like Chinese/Japanese keyboards) and each
    /// key replaces it in one call; the word is committed at a word break. This is that word.
    private var composing = ""

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
        markedText = d.bool(forKey: VKSettings.Key.markedText)
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
        case .go: return ("Đi", true)
        case .search, .google, .yahoo: return ("Tìm", true)
        case .send: return ("Gửi", true)
        case .done: return ("Xong", true)
        case .next: return ("Tiếp", false)
        case .join: return ("Tham gia", true)
        case .route: return ("Chỉ đường", true)
        case .continue: return ("Tiếp tục", true)
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
        if markedText, !composing.isEmpty, (ctx ?? "").hasSuffix(composing) || (lastContext ?? "").hasSuffix(ctx ?? "\u{0}") {
            lastContext = ctx      // the host caught up with our marked word
            return
        }
        if ctx != lastContext {
            composing = ""
            driver.resetContext()
            lastContext = ctx
            updateAutoShift(ctx ?? "")
        }
    }

    // MARK: keys

    func keyboard(_ view: KeyboardView, didTap kind: KeyKind) {
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

    func keyboardBackspaceRepeat(_ view: KeyboardView) { backspace() }

    private func spaceKey() {
        // double space: ". " like the system keyboard
        let before = lastContext ?? ""
        if doubleSpacePeriod, now - lastSpace < 0.6, before.hasSuffix(" "),
           let prev = before.dropLast().last, prev.isLetter || prev.isNumber {
            commitMarked()
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
        if markedText { applyMarked(e); return }
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
        if e.languageChanged { saveLanguage(); refresh() }
        afterEdit()
    }

    /// Marked-text version of apply: edits inside the word being typed are one setMarkedText call.
    private func applyMarked(_ e: VKEditResult) {
        if e.deleteCount <= composing.count {
            composing = String(composing.dropLast(e.deleteCount)) + e.text
        } else {
            // the edit reaches into text already committed (look-back fix, undo): plain delete + insert
            let extra = e.deleteCount - composing.count
            composing = ""
            proxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
            proxy.unmarkText()
            for _ in 0..<extra { proxy.deleteBackward() }
            composing = e.text
        }
        // everything up to the last word break is final; the rest is the word still being typed
        if let i = composing.lastIndex(where: { !($0.isLetter || $0.isNumber) }) {
            let done = String(composing[...i]), rest = String(composing[composing.index(after: i)...])
            proxy.setMarkedText(done, selectedRange: NSRange(location: (done as NSString).length, length: 0))
            proxy.unmarkText()
            composing = rest
        }
        if !composing.isEmpty || e.deleteCount > 0 {
            proxy.setMarkedText(composing, selectedRange: NSRange(location: (composing as NSString).length, length: 0))
            if composing.isEmpty { proxy.unmarkText() }
        }
        if e.languageChanged { saveLanguage(); refresh() }
        afterEdit()
    }

    private func commitMarked() {
        guard markedText, !composing.isEmpty else { return }
        proxy.unmarkText()
        composing = ""
    }

    override func viewWillDisappear(_ animated: Bool) {
        commitMarked()
        super.viewWillDisappear(animated)
    }

    private func afterEdit() {
        lastContext = proxy.documentContextBeforeInput   // one text read per key
        updateAutoShift(lastContext ?? "")
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
