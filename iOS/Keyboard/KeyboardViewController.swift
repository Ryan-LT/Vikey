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
    var keyboardViewForTests: KeyboardView { keyboard }
    func setLanguageForTests(_ l: Int) { driver.language = l; driver.resetContext() }
    private var heightConstraint: NSLayoutConstraint?
    private var emojiView: EmojiKeyboardView?
    /// The user's Text Replacements (Settings › General › Keyboard), like the system keyboard: "omw" → "On my way!"
    private var textReplacements: [String: String] = [:]
    func setTextReplacementsForTests(_ r: [String: String]) { textReplacements = r }
    private var emojiQuery = ""
    /// Our own copy of the text before the cursor, kept up to date from our edits. Asking the app for it
    /// is a synchronous cross-process call, so it's only read when iOS says the text changed.
    private var lastContext: String?
    /// The text after the cursor when we last looked. Our own typing never changes it, so when it changes
    /// the cursor moved (a tap inside a word leaves the text before the cursor looking like one of our edits).
    private var lastAfter = ""
    private var recentContexts: [String] = []   // states we produced that the app may still be catching up to
    private var lastShiftTap: TimeInterval = 0
    private var lastSpace: TimeInterval = 0
    private var fieldLanguage: Int?           // language to restore after a web/email field
    private let languageKey = "Language"
    /// Letters typed so far in the current word (for the fat-finger model and auto-correct), with
    /// where each was touched and how many were capitals.
    private var wordPrefix = ""
    private var wordXs: [Float] = [], wordYs: [Float] = []
    private var wordCaps = 0
    private var candidates: [VKCandidate] = []     // for the strip; [0] is what auto-correct would use
    private var willCorrect = false
    /// What the end of this word will put in instead of it (auto-correct or a contraction), and its language.
    private var pendingFix: (text: String, vietnamese: Bool)?
    /// The last auto-correct, so the next backspace can put the typed word back.
    private var lastCorrection: (typed: String, inserted: String)?
    private var keepWord: String?                  // a word put back by backspace: don't correct it again
    /// The text field. Tests swap in a counting proxy (performance lock: one text read per key).
    lazy var proxy: UITextDocumentProxy = textDocumentProxy
    // settings, read once when the keyboard appears (reading shared defaults per key is slow)
    private var webFieldsEnglish = true, autoCapitalize = true, doubleSpacePeriod = true, haptics = true
    private var suggestionsOn = true, autoCorrectOn = true

    override func loadView() {
        let v = KeyboardInputView(frame: .zero, inputViewStyle: .keyboard)
        v.allowsSelfSizing = true
        inputView = v
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        KeyboardView.searchTop = nil   // left over from an emoji search in an earlier keyboard of this process
        keyboard = KeyboardView(frame: view.bounds)
        keyboard.delegate = self
        keyboard.wordContext = { [unowned self] in (self.wordPrefix, self.driver.language == 1) }
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
        DispatchQueue.global(qos: .utility).async { _ = EmojiIndex.shared }   // the emoji keyboard opens instantly
        requestSupplementaryLexicon { [weak self] lex in
            var r: [String: String] = [:]
            for e in lex.entries where e.userInput.lowercased() != e.documentText.lowercased()   // (contact names list themselves)
                && e.userInput.allSatisfy({ $0.isLetter && $0.isASCII }) {
                r[e.userInput.lowercased()] = e.documentText
            }
            DispatchQueue.main.async { self?.textReplacements = r }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let ev = emojiView, !ev.isHidden { emojiKeyboardClose(ev) }   // a new field opens on the letters
        if KeyboardView.searchTop != nil, emojiView?.searching != true {     // static: it outlives a closed keyboard
            KeyboardView.searchTop = nil
            heightConstraint?.constant = keyboardHeight
            keyboard.setNeedsLayout()
        }
        loadSettings()
        startField()
        refresh()
        if keyboard.haptics { keyboard.feedback.start() }
        if Diag.on { startStallWatch() }
        if Diag.on {
            KBLog.add("open: fullAccess=\(hasFullAccess) haptics=\(keyboard.haptics) field=\(proxy.keyboardType?.rawValue ?? -1) return=\(proxy.returnKeyType?.rawValue ?? -1) width=\(Int(view.bounds.width))")
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        stallWatch?.invalidate(); stallWatch = nil
        keyboard.feedback.stop()
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
        suggestionsOn = d.bool(forKey: VKSettings.Key.suggestions)
        autoCorrectOn = d.bool(forKey: VKSettings.Key.autoCorrect)
        KeyboardView.barOn = suggestionsOn || autoCorrectOn
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
        lastAfter = proxy.documentContextAfterInput ?? ""
        clearWord()
        updateAutoShift(lastContext ?? "")
    }

    /// Auto-correct and suggestions only where the system keyboard offers them.
    private var correctsHere: Bool {
        if proxy.autocorrectionType == .no || proxy.spellCheckingType == .no { return false }
        let t = proxy.keyboardType ?? .default
        return !(t == .URL || t == .emailAddress || t == .webSearch || t == .numberPad || t == .decimalPad || t == .asciiCapableNumberPad)
    }

    private var now: Double { ProcessInfo.processInfo.systemUptime }

    private func refresh() {
        keyboard.dark = proxy.keyboardAppearance == .dark || traitCollection.userInterfaceStyle == .dark
        keyboard.languageTitle = driver.language == 1 ? "Tiếng Việt" : "English"
        keyboard.languageShort = driver.language == 1 ? "VI" : "EN"
        let (title, blue) = Self.returnTitle(proxy.returnKeyType ?? .default)
        keyboard.returnTitle = title
        keyboard.returnIsBlue = blue
        emojiView?.dark = keyboard.dark
        if emojiView?.searching == true { updateEmojiQuery() }   // VI/EN changes how the query reads
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
        let r0 = CACurrentMediaTime()
        let ctx = proxy.documentContextBeforeInput
        if Diag.on { KBLog.add("text read (iOS said the text changed): \(Self.time((CACurrentMediaTime() - r0) * 1000))") }
        let after = proxy.documentContextAfterInput ?? ""
        let moved = after != lastAfter
        if !moved, let c = ctx, c != lastContext, recentContexts.contains(c) { return }   // the app is catching up with our edits
        if moved || (ctx != lastContext && !Self.sameEnding(ctx ?? "", lastContext ?? "")) {
            if Diag.on { KBLog.add("reset: text changed outside the keyboard (cursor moved, or the app changed it)") }
            driver.resetContext()
            clearWord()
            lastCorrection = nil; keepWord = nil
            recentContexts = []
            lastContext = ctx
            lastAfter = after
            updateAutoShift(ctx ?? "")
        }
    }

    // MARK: keys

    func keyboard(_ view: KeyboardView, didTap kind: KeyKind) {
        if emojiView?.searching == true, emojiSearchKey(kind) { return }
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
            if snapsBack(c) { backspace() }   // "this ." → "this." like the system keyboard (Tony)
            if c == "-", (lastContext ?? "").hasSuffix("-"), !(lastContext ?? "").hasSuffix("--"),
               (proxy.smartDashesType ?? .default) != .no {   // smart dashes: "--" → "—"
                backspace(); clearWord(); type("—"); break
            }
            lastCorrection = nil
            if [".", ",", "?", "!"].contains(c), !wordPrefix.isEmpty, autoCorrectAtBreak(c) {   // "dont?" → "don't?"
                if c != "," { updateAutoShift(lastContext ?? "") }
                break
            }
            if let ch = c.first, ch.isLetter, ch.isASCII, wordPrefix.count < 30 {
                wordPrefix.append(ch)
                let t = keyboard.lastTapPoint ?? CGPoint(x: CGFloat.nan, y: .nan)
                keyboard.lastTapPoint = nil
                wordXs.append(Float(t.x)); wordYs.append(Float(t.y))
                if keyboard.layer_ == .letters && keyboard.shift != .off { wordCaps += 1 }
            } else { clearWord() }
            var s = c
            if keyboard.layer_ == .letters && keyboard.shift != .off { s = c.uppercased() }
            type(s)
            if keyboard.shift == .on { keyboard.shift = .off }
            if keyboard.layer_ != .letters && (c == "'" ) { keyboard.layer_ = .letters }
        case .space:
            if !autoCorrectAtBreak() { spaceKey() }
            clearWord()
        case .returnKey:
            clearWord()
            type("\n")
        case .backspace:
            if undoCorrection() { break }
            if !wordPrefix.isEmpty {
                wordPrefix.removeLast(); wordXs.removeLast(); wordYs.removeLast()
                wordCaps = min(wordCaps, wordPrefix.count)
            }
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
            lastCorrection = nil
            driver.manualSwitch(at: now)
            fieldLanguage = nil
            saveLanguage()
            refresh()
        case .globe:
            advanceToNextInputMode()
        case .emoji:
            showEmoji()
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
        clearWord()
        afterEdit(deleted: max(k, 1), inserted: "")
    }

    func keyboard(_ view: KeyboardView, insertAlternate text: String) {
        clearWord()
        type(text)      // a character the engine doesn't know passes through and starts a new word
        if keyboard.shift == .on { keyboard.shift = .off }
    }

    func keyboard(_ view: KeyboardView, moveCursorBy offset: Int) {
        proxy.adjustTextPosition(byCharacterOffset: offset)
    }

    func keyboardCursorModeEnded(_ view: KeyboardView) {
        driver.resetContext()
        clearWord()
        lastCorrection = nil; keepWord = nil
        lastContext = proxy.documentContextBeforeInput
        lastAfter = proxy.documentContextAfterInput ?? ""
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
            afterEdit(deleted: 1, inserted: ". ")
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
        afterEdit(deleted: deletes, inserted: insert)
    }

    /// The app's text before the cursor only shows a window of the document: compare what both have.
    /// Milliseconds as text; under 0.1 ms in nanoseconds (Tony).
    static func time(_ ms: Double) -> String {
        ms < 0.1 ? String(format: "%.0f ns", ms * 1_000_000) : String(format: "%.2f ms", ms)
    }

    private static func sameEnding(_ a: String, _ b: String) -> Bool {
        let n = min(a.count, b.count, 40)
        return n > 0 && a.suffix(n) == b.suffix(n) && abs(a.count - b.count) < 2000 && (a.count == b.count || n == 40)
    }

    private func afterEdit(deleted: Int, inserted: String) {
        var c = lastContext ?? ""
        c = String(c.dropLast(min(deleted, c.count))) + inserted
        if c.count > 4000 { c = String(c.suffix(2000)) }
        lastContext = c
        recentContexts.append(c)
        if recentContexts.count > 12 { recentContexts.removeFirst(recentContexts.count - 12) }
        Diag.readMs = 0
        updateAutoShift(c)
        scheduleSuggestions()
        if Diag.on {
            let end = CACurrentMediaTime()
            let hold = max(0, Diag.touchUp - Diag.touchStart) * 1000, work = max(0, end - Diag.touchUp) * 1000
            keyboard.diagnostics = "finger down \(Self.time(hold)) · lift→text \(Self.time(work)) · read \(Self.time(Diag.readMs))\n"
                + "vibrations \(Diag.haptics) · touches \(Diag.touches) · edits \(Diag.edits)"
            KBLog.add("key=\(Diag.lastKind) hold=\(Self.time(hold)) work=\(Self.time(work)) read=\(Self.time(Diag.readMs)) vib=\(Diag.haptics) late=\(Diag.late) delay=\(Self.time(Diag.delayMs)) touches=\(Diag.touches) edits=\(Diag.edits) suggest=\(Self.time(Diag.suggestMs)) lang=\(driver.language)")
            Diag.haptics = 0; Diag.touches = 0; Diag.edits = 0; Diag.late = 0; Diag.suggestMs = 0; Diag.delayMs = 0
        }
    }

    // MARK: suggestions and auto-correct

    private func clearWord() {
        wordPrefix = ""; wordXs = []; wordYs = []; wordCaps = 0
        candidates = []; willCorrect = false; pendingFix = nil
        keyboard?.suggestions = []
    }

    /// The word before the cursor as it shows in the field (after Telex: "tôi" for "tooi").
    private var shownWord: String {
        let c = lastContext ?? ""
        return String(c.reversed().prefix { $0.isLetter }.reversed())
    }

    private static func text(of c: VKCandidate) -> String {
        var c = c
        let n = Int(c.textLen)
        return withUnsafeBytes(of: &c.text) { raw in
            String(utf16CodeUnits: raw.bindMemory(to: unichar.self).baseAddress!, count: n)
        }
    }

    /// Capitalised like the typed word ("Teh" → "The").
    private func cased(_ s: String) -> String {
        shownWord.first?.isUppercase == true ? s.prefix(1).uppercased() + s.dropFirst() : s
    }

    /// The strip is worked out after the key's text has gone to the app, so it never delays typing;
    /// keys typed faster than that skip the in-between words.
    private var suggestionsDirty = false
    private func scheduleSuggestions() {
        guard !suggestionsDirty else { return }
        suggestionsDirty = true
        DispatchQueue.main.async { [weak self] in self?.updateSuggestionsIfNeeded() }
    }
    private func updateSuggestionsIfNeeded() {
        guard suggestionsDirty else { return }
        let t0 = CACurrentMediaTime()
        updateSuggestions()
        Diag.suggestMs = max(Diag.suggestMs, (CACurrentMediaTime() - t0) * 1000)
    }

    /// Debug log only: any main-thread freeze over 50 ms, and the key it followed. Touches that arrive
    /// during a freeze are what feel like lag (and, before, like double vibrations).
    private var stallWatch: CADisplayLink?
    private var lastFrame: CFTimeInterval = 0
    private func startStallWatch() {
        stallWatch?.invalidate()
        lastFrame = 0
        let link = CADisplayLink(target: self, selector: #selector(frameTick(_:)))
        link.add(to: .main, forMode: .common)
        stallWatch = link
    }
    @objc private func frameTick(_ link: CADisplayLink) {
        let gap = lastFrame == 0 ? 0 : link.timestamp - lastFrame
        lastFrame = link.timestamp
        if gap > 0.05 { KBLog.add("stall \(Self.time(gap * 1000)) after key=\(Diag.lastKind)") }
    }

    func updateSuggestions() {
        suggestionsDirty = false
        guard KeyboardView.barOn, correctsHere, !wordPrefix.isEmpty, !shownWord.isEmpty else {
            if !candidates.isEmpty || !(keyboard?.suggestions.isEmpty ?? true) { candidates = []; willCorrect = false; pendingFix = nil; keyboard.suggestions = [] }
            return
        }
        let typed = wordPrefix.lowercased()
        let vi: Int32 = driver.language == 1 ? 1 : 0
        let rects = keyboard.keyRects
        guard !rects.isEmpty else { return }
        var out = [VKCandidate](repeating: VKCandidate(), count: 6)
        let touched = !wordXs.contains { $0.isNaN }    // keys typed without a touch (tests): key centres only
        let n = typed.withCString { t in
            touched ? VKCandidates(t, wordXs, wordYs, vi, rects, Int32(rects.count), &out, 6)
                    : VKCandidates(t, nil, nil, vi, rects, Int32(rects.count), &out, 6)
        }
        candidates = Array(out.prefix(Int(n)))
        // never auto-correct acronyms / names typed with capitals inside, or a word put back by backspace
        willCorrect = autoCorrectOn && wordCaps < 2 && keepWord != typed && wordPrefix.count >= 3
            && typed.withCString { t in candidates.withUnsafeBufferPointer { VKShouldCorrect(t, $0.baseAddress!, n) } }
        pendingFix = willCorrect ? candidates.first.map { (cased(Self.text(of: $0)), $0.vietnamese == 1) } : nil
        // "dont" → "don't" from the keys typed (in Vietnamese mode "thats" shows as "thát" until the end of
        // the word); a common Vietnamese word in Vietnamese mode stays ("im")
        let shownNow = shownWord
        let typedCased = wordCaps == wordPrefix.count && wordPrefix.count > 1 ? typed.uppercased()
            : shownNow.first?.isUppercase == true ? typed.prefix(1).uppercased() + typed.dropFirst() : typed
        if autoCorrectOn, keepWord != typed, let c = Contractions.fix(typedCased),
           driver.language == 0 || typed.withCString({ VKWordScore(1, $0) }) < 10 {   // a common Vietnamese word stays ("im"); a rare one ("thát") doesn't block "that's"
            pendingFix = (c, false); willCorrect = true
        }
        if autoCorrectOn, keepWord != typed, let r = textReplacements[typed] {   // the user's own shortcuts win
            pendingFix = (r, driver.language == 1); willCorrect = true
        }
        var comp = [VKCandidate](repeating: VKCandidate(), count: 6)
        let m = suggestionsOn ? typed.withCString { VKCompletions($0, vi, &comp, 6) } : 0
        let shown = shownWord
        var cells: [Suggestion] = [Suggestion(text: shown, quoted: true)]
        var seen: Set<String> = [shown.lowercased()]
        func add(_ c: VKCandidate, highlight: Bool = false) {
            let t = cased(Self.text(of: c))
            guard cells.count < 3, !seen.contains(t.lowercased()) else { return }
            seen.insert(t.lowercased()); cells.append(Suggestion(text: t, highlighted: highlight))
        }
        if willCorrect, let fix = pendingFix, !seen.contains(fix.text.lowercased()) {
            seen.insert(fix.text.lowercased()); cells.append(Suggestion(text: fix.text, highlighted: true))
        }
        if suggestionsOn {
            // a typed word that isn't a word: fixes first; otherwise ways to finish it
            let isWord = candidates.contains { String(cString: withUnsafeBytes(of: $0.letters) { Array($0.bindMemory(to: CChar.self)) + [0] }) == typed }
            let fixes = candidates.filter { $0.score > -9 }
            for c in isWord ? Array(comp.prefix(Int(m))) + fixes : fixes + Array(comp.prefix(Int(m))) { add(c) }
        }
        if cells.count == 1 { cells[0].quoted = false }
        if !suggestionsOn && !willCorrect { cells = [] }
        keyboard.suggestions = cells
    }

    /// Space after a word: put in the correction (like the system keyboard). Returns true when it typed the space itself.
    private func autoCorrectAtBreak(_ end: String = " ") -> Bool {
        updateSuggestionsIfNeeded()       // typed faster than the strip: decide on the whole word now
        guard willCorrect, let fix = pendingFix else { return false }
        replaceWord(with: fix.text, vietnamese: fix.vietnamese, recordUndo: true, then: end)
        return true
    }

    /// Replace the word before the cursor with `word` + a space, in the word's language.
    private func replaceWord(with word: String, vietnamese: Bool, recordUndo: Bool, then end: String = " ") {
        let old = shownWord
        let insert = word + end
        for _ in 0..<old.count { proxy.deleteBackward() }
        proxy.insertText(insert)
        Diag.edits += old.count + 1
        driver.resetContext()
        if (driver.language == 1) != vietnamese && driver.autoSwitch {
            driver.language = vietnamese ? 1 : 0
            saveLanguage(); refresh()
        }
        lastCorrection = recordUndo ? (old, insert) : nil
        lastSpace = end == " " ? now : 0
        clearWord()
        afterEdit(deleted: old.count, inserted: insert)
    }

    /// Backspace right after an auto-correct puts the typed word back (and keeps it this time).
    private func undoCorrection() -> Bool {
        guard let c = lastCorrection, (lastContext ?? "").hasSuffix(c.inserted) else { lastCorrection = nil; return false }
        lastCorrection = nil
        for _ in 0..<c.inserted.count { proxy.deleteBackward() }
        proxy.insertText(c.typed)
        driver.resetContext()
        keepWord = c.typed.lowercased()
        clearWord()
        afterEdit(deleted: c.inserted.count, inserted: c.typed)
        return true
    }

    func keyboard(_ view: KeyboardView, pickSuggestion index: Int) {
        let cells = keyboard.suggestions
        guard index < cells.count else { return }
        let cell = cells[index]
        lastCorrection = nil
        if cell.quoted || cell.text == shownWord {
            // keep what was typed: a space, and don't correct it
            keepWord = wordPrefix.lowercased()
            willCorrect = false
            spaceKey()
            clearWord()
            return
        }
        let c = candidates.first { cased(Self.text(of: $0)) == cell.text }
        var vi = driver.language == 1
        if let c { vi = c.vietnamese == 1 } else {
            var comp = [VKCandidate](repeating: VKCandidate(), count: 6)
            let m = wordPrefix.lowercased().withCString { VKCompletions($0, driver.language == 1 ? 1 : 0, &comp, 6) }
            if let hit = comp.prefix(Int(m)).first(where: { cased(Self.text(of: $0)) == cell.text }) { vi = hit.vietnamese == 1 }
        }
        replaceWord(with: cell.text, vietnamese: vi, recordUndo: false)
    }

    private func saveLanguage() { UserDefaults.standard.set(driver.language, forKey: languageKey) }

    /// Capital letter at the start of a sentence, like the system keyboard.
    /// Punctuation typed right after a space goes back onto the word: "this ." → "this.", "hello "" → "hello"".
    /// Quotes and brackets only when they close one that is open in this paragraph.
    private func snapsBack(_ c: String) -> Bool {
        guard ".,?!:;)\"".contains(c), let before = lastContext, before.hasSuffix(" ") else { return false }
        let prev = before.dropLast().last
        guard let p = prev, p != " ", p != "\n" else { return false }
        let para = before.split(separator: "\n", omittingEmptySubsequences: false).last ?? ""
        if c == ")" { return para.filter { $0 == "(" }.count > para.filter { $0 == ")" }.count }
        if c == "\"" { return para.filter { $0 == "\"" }.count % 2 == 1 }
        return true
    }

    private func updateAutoShift(_ before: String) {
        guard keyboard.layer_ == .letters, keyboard.shift != .locked else { return }
        guard autoCapitalize, (proxy.autocapitalizationType ?? .sentences) != .none else {
            if keyboard.shift == .on { keyboard.shift = .off }
            return
        }
        let trimmed = before.replacingOccurrences(of: " ", with: "")
        var start = before.isEmpty || before.hasSuffix("\n")
        // a sentence ends at . ? ! … , also with closing quotes or brackets after it: go." Then, (wow.) Next
        let core = trimmed.reversed().drop { "\"”’')]".contains($0) }
        if !start, before.hasSuffix(" "), let last = core.first { start = ".?!…".contains(last) }
        if proxy.autocapitalizationType == .allCharacters { keyboard.shift = .on; return }
        if proxy.autocapitalizationType == .words && (before.isEmpty || before.hasSuffix(" ")) { start = true }
        keyboard.shift = start ? .on : .off
    }
}

// MARK: emoji keyboard

extension KeyboardViewController: EmojiKeyboardDelegate {
    private var keyboardHeight: CGFloat { KeyboardView.keyboardHeight(compactHeight: traitCollection.verticalSizeClass == .compact) }

    func showEmoji() {
        clearWord()
        driver.resetContext()
        let ev = emojiView ?? {
            let v = EmojiKeyboardView(frame: view.bounds)
            v.delegate = self
            v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(v)
            emojiView = v
            return v
        }()
        ev.dark = keyboard.dark
        ev.haptics = keyboard.haptics
        ev.feedback = keyboard.feedback
        ev.load()
        browseEmoji()
    }

    private func browseEmoji() {
        guard let ev = emojiView else { return }
        KeyboardView.searchTop = nil
        heightConstraint?.constant = keyboardHeight
        keyboard.isHidden = true
        ev.isHidden = false
        ev.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        ev.frame = view.bounds
        ev.setSearching(false)
        keyboard.setNeedsLayout()
    }

    func emojiKeyboardClose(_ v: EmojiKeyboardView) {
        KeyboardView.searchTop = nil
        heightConstraint?.constant = keyboardHeight
        v.isHidden = true
        keyboard.isHidden = false
        keyboard.layer_ = .letters
        keyboard.setNeedsLayout()
        updateAutoShift(lastContext ?? "")
    }

    func emojiKeyboardStartSearch(_ v: EmojiKeyboardView) {
        KeyboardView.searchTop = EmojiKeyboardView.searchHeight
        heightConstraint?.constant = keyboardHeight
        keyboard.isHidden = false
        keyboard.layer_ = .letters
        keyboard.shift = .off
        keyboard.setNeedsLayout()
        v.autoresizingMask = [.flexibleWidth]
        v.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: EmojiKeyboardView.searchHeight)
        v.setSearching(true)
        emojiQuery = ""
        updateEmojiQuery()
    }

    func emojiKeyboard(_ v: EmojiKeyboardView, insert text: String) {
        proxy.insertText(text)
        driver.resetContext()
        clearWord()
        afterEdit(deleted: 0, inserted: text)
    }

    func emojiKeyboardDelete(_ v: EmojiKeyboardView) {
        proxy.deleteBackward()
        driver.resetContext()
        clearWord()
        afterEdit(deleted: 1, inserted: "")
    }

    /// Keys while searching go to the query, not the app. Returns false for keys that work as usual.
    private func emojiSearchKey(_ kind: KeyKind) -> Bool {
        switch kind {
        case .char(let c): emojiQuery += c.lowercased()
        case .space: if !emojiQuery.isEmpty && !emojiQuery.hasSuffix(" ") { emojiQuery += " " }
        case .backspace: if !emojiQuery.isEmpty { emojiQuery.removeLast() }
        case .returnKey, .emoji: browseEmoji(); return true
        default: return false
        }
        if keyboard.shift == .on { keyboard.shift = .off }
        updateEmojiQuery()
        return true
    }

    /// The query reads as Telex in Vietnamese mode ("nguwaj" shows "ngựa"); search uses the raw keys too.
    private func updateEmojiQuery() {
        guard let ev = emojiView else { return }
        let vi = driver.language == 1
        let shown = vi ? Telex.convert(emojiQuery) : emojiQuery
        let found = emojiQuery.trimmingCharacters(in: .whitespaces).isEmpty ? [] :
            EmojiIndex.shared.search(emojiQuery, vietnamese: vi, limit: 80).filter { $0.version <= EmojiKeyboardView.maxVersion }
        ev.setQuery(shown, results: found)
    }
}

