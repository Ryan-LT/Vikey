import UIKit

/// Debug readout (Vikey app › Hiện thông số bàn phím): what one key press costs on a real device.
enum Diag {
    static var on = false
    static var touchStart: CFTimeInterval = 0
    static var touches = 0, haptics = 0, edits = 0
    static var readMs = 0.0
    static var lastKind = "letter"
}

/// What a key does.
enum KeyKind: Equatable {
    case char(String)      // inserts this (letters stored lowercase)
    case shift, backspace, space, returnKey, globe, language
    case layer(KeyboardView.Layer)
}

struct KeyDef {
    var kind: KeyKind
    var frame: CGRect = .zero
}

protocol KeyboardViewDelegate: AnyObject {
    func keyboard(_ view: KeyboardView, didTap kind: KeyKind)
    /// A long-press alternate (… – ’ ă ê …), already in the right case.
    func keyboard(_ view: KeyboardView, insertAlternate text: String)
    /// Delete held down: n = how many repeats so far (the controller speeds up to whole words).
    func keyboardBackspaceRepeat(_ view: KeyboardView, count n: Int)
    /// Space held down and dragged: move the cursor by this many characters.
    func keyboard(_ view: KeyboardView, moveCursorBy offset: Int)
    func keyboardCursorModeEnded(_ view: KeyboardView)
}

/// The iOS 26 system keyboard, measured from the simulator (iPhone 17 Pro, 402 pt wide) and copied:
/// key 43 pt tall, rows 54 pt apart, 6 pt gaps, a 52 pt strip on top (where the system shows
/// suggestions; here it gives the top-row key popups room, since iOS clips a keyboard to its view).
/// Touches are handled by this view, not per key, so fast typing between keys never gets lost.
final class KeyboardView: UIView {
    enum Layer { case letters, numbers, symbols }
    enum Shift { case off, on, locked }

    weak var delegate: KeyboardViewDelegate?
    var layer_: Layer = .letters { didSet { if layer_ != oldValue { rebuild() } } }
    var shift: Shift = .off { didSet { if shift != oldValue { refreshLabels() } } }
    var dark = false { didSet { if dark != oldValue { refreshColors() } } }
    var showsGlobe = false { didSet { if showsGlobe != oldValue { rebuild() } } }
    // setters restyle keys only when something changed: they run on every key press
    var languageTitle = "Tiếng Việt" { didSet { if languageTitle != oldValue { refreshLabels() } } }
    var languageShort = "VI" { didSet { if languageShort != oldValue { refreshLabels() } } }
    var returnTitle = "return" { didSet { if returnTitle != oldValue { refreshLabels() } } }
    var returnIsBlue = false { didSet { if returnIsBlue != oldValue { refreshColors() } } }
    var haptics = false
    var globeButton: UIButton?
    private let diagLabel = UILabel()
    var diagnostics: String? {
        didSet { diagLabel.text = diagnostics; diagLabel.isHidden = diagnostics == nil }
    }

    private var keys: [(def: KeyDef, view: KeyCap)] = []
    private var touch: UITouch?                 // the touch that owns the current key
    private var touchKey: KeyCap?
    private var touchStart: CGPoint = .zero
    private var slideFromLayer = false         // 123 pressed and slid onto a symbol: back to letters after
    private let popup = KeyPopup()
    private let alternates = AlternatesView()
    private var holdTimer: Timer?
    private var repeatCount = 0
    private var cursorMode = false
    private var cursorAnchor: CGFloat = 0
    private let feedback = UIImpactFeedbackGenerator(style: .light)

    // geometry (portrait iPhone; scaled for other widths; landscape rows are shorter)
    /// No suggestion strip on top for now (Tony): the keys start right away. With diagnostics on, the
    /// strip comes back to show the readout.
    static func metrics(compactHeight: Bool) -> (top: CGFloat, keyH: CGFloat, pitch: CGFloat, bottom: CGFloat) {
        if compactHeight { return (top: 8, keyH: 34, pitch: 40, bottom: 4) }
        return (top: Diag.on ? 57 : 11, keyH: 43, pitch: 54, bottom: 3)
    }
    static func keyboardHeight(compactHeight: Bool) -> CGFloat {
        let m = metrics(compactHeight: compactHeight)
        return m.top + 3 * m.pitch + m.keyH + m.bottom
    }
    private var compactHeight: Bool { traitCollection.verticalSizeClass == .compact }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        // not .clear: iOS doesn't deliver touches on fully transparent parts of a keyboard,
        // so taps in the gaps between keys were lost
        backgroundColor = UIColor.black.withAlphaComponent(0.001)
        rebuild()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: layout

    private func rowKinds() -> [[KeyKind]] {
        func chars(_ s: String) -> [KeyKind] { s.map { .char(String($0)) } }
        var bottom: [KeyKind] = [layer_ == .letters ? .layer(.numbers) : .layer(.letters)]
        if showsGlobe { bottom.append(.globe) }
        bottom += [.language, .space, .returnKey]
        switch layer_ {
        case .letters: return [chars("qwertyuiop"), chars("asdfghjkl"), [.shift] + chars("zxcvbnm") + [.backspace], bottom]
        case .numbers: return [chars("1234567890"), chars("-/:;()$&@\""), [.layer(.symbols)] + chars(".,?!'") + [.backspace], bottom]
        case .symbols: return [chars("[]{}#%^*+="), chars("_\\|~<>€£¥•"), [.layer(.numbers)] + chars(".,?!'") + [.backspace], bottom]
        }
    }

    private func rebuild() {
        keys.forEach { $0.view.removeFromSuperview() }
        keys = []
        globeButton?.removeFromSuperview(); globeButton = nil
        for row in rowKinds() {
            for kind in row {
                let cap = KeyCap()
                cap.isUserInteractionEnabled = false
                addSubview(cap)
                keys.append((KeyDef(kind: kind), cap))
                if kind == .globe { let b = UIButton(type: .custom); addSubview(b); globeButton = b }
            }
        }
        diagLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        diagLabel.textColor = .secondaryLabel
        diagLabel.textAlignment = .center
        diagLabel.numberOfLines = 2
        addSubview(diagLabel)
        diagLabel.isHidden = diagnostics == nil
        addSubview(popup); popup.isHidden = true
        addSubview(alternates); alternates.isHidden = true
        setFonts()
        refreshLabels()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let m = Self.metrics(compactHeight: compactHeight)
        let W = bounds.width
        let s = W / 402                       // the measured layout is for 402 pt
        let side = 6.67 * s, gap = 6 * s
        let key = (W - 2 * side - 9 * gap) / 10
        let rows = rowKinds()
        var frames: [CGRect] = []
        for (r, row) in rows.enumerated() {
            let y = m.top + CGFloat(r) * m.pitch
            func rect(_ x: CGFloat, _ w: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: m.keyH) }
            switch r {
            case 0:
                for i in 0..<row.count { frames.append(rect(side + CGFloat(i) * (key + gap), key)) }
            case 1:
                if row.count == 9 {
                    let x0 = side + (key + gap) / 2
                    for i in 0..<9 { frames.append(rect(x0 + CGFloat(i) * (key + gap), key)) }
                } else {
                    for i in 0..<row.count { frames.append(rect(side + CGFloat(i) * (key + gap), key)) }
                }
            case 2:
                let fn = 45.3 * s
                frames.append(rect(side, fn))
                let inner = row.count - 2
                if inner == 7 {
                    let x0 = side + (key + gap) * 1.5
                    for i in 0..<7 { frames.append(rect(x0 + CGFloat(i) * (key + gap), key)) }
                } else {   // 5 wide punctuation keys between the function keys
                    let left = side + fn + gap * 2.5, right = W - side - fn - gap * 2.5
                    let w = (right - left - CGFloat(inner - 1) * gap) / CGFloat(inner)
                    for i in 0..<inner { frames.append(rect(left + CGFloat(i) * (w + gap), w)) }
                }
                frames.append(rect(W - side - fn, fn))
            default:
                let small = 43.3 * s, ret = 92.6 * s
                var x = side
                for kind in row {
                    switch kind {
                    case .space:
                        let w = W - side - ret - gap - x
                        frames.append(rect(x, w)); x += w + gap
                    case .returnKey:
                        frames.append(rect(W - side - ret, ret))
                    default:
                        frames.append(rect(x, small)); x += small + gap
                    }
                }
            }
        }
        diagLabel.frame = CGRect(x: 8, y: 2, width: W - 16, height: max(m.top - 6, 20))
        for i in keys.indices where i < frames.count {
            keys[i].def.frame = frames[i]
            keys[i].view.frame = frames[i]
            if keys[i].def.kind == .globe { globeButton?.frame = frames[i].insetBy(dx: -gap / 2, dy: -6) }
        }
    }

    // MARK: appearance

    private func title(for kind: KeyKind) -> (String?, UIImage?) {
        let sym = UIImage.SymbolConfiguration(pointSize: 19, weight: .regular)
        switch kind {
        case .char(let c): return (shift != .off && layer_ == .letters ? c.uppercased() : c, nil)
        case .shift: return (nil, UIImage(systemName: shift == .locked ? "capslock.fill" : (shift == .on ? "shift.fill" : "shift"), withConfiguration: sym))
        case .backspace: return (nil, UIImage(systemName: "delete.left", withConfiguration: sym))
        case .space: return (cursorMode ? "" : languageTitle, nil)
        case .returnKey: return returnTitle == "return" ? (nil, UIImage(systemName: "return", withConfiguration: sym)) : (returnTitle, nil)
        case .globe: return (nil, UIImage(systemName: "globe", withConfiguration: sym))
        case .language: return (languageShort, nil)
        case .layer(let l): return (l == .letters ? "ABC" : (l == .numbers ? "123" : "#+="), nil)
        }
    }

    private func setFonts() {
        for (def, v) in keys {
            switch def.kind {
            case .char: v.label.font = .systemFont(ofSize: layer_ == .letters ? 23 : 22, weight: .regular)
            case .space: v.label.font = .systemFont(ofSize: 15, weight: .regular); v.label.adjustsFontSizeToFitWidth = true; v.label.minimumScaleFactor = 0.6
            case .language: v.label.font = .systemFont(ofSize: 16, weight: .semibold)
            case .returnKey: v.label.font = .systemFont(ofSize: 16, weight: .medium)
            default: v.label.font = .systemFont(ofSize: 16, weight: .regular)
            }
        }
    }

    private func refreshLabels() {
        for (def, v) in keys {
            var (t, img) = title(for: def.kind)
            if cursorMode, case .char = def.kind { t = "" }     // the system keyboard blanks the keys in cursor mode
            if v.label.text != t { v.label.text = t }
            if v.icon.image != img { v.icon.image = img }
        }
        refreshColors()
    }

    private func refreshColors() {
        let fg: UIColor = dark ? .white : .black
        let key: UIColor = dark ? UIColor(white: 0.42, alpha: 1) : .white
        let pressed: UIColor = dark ? UIColor(white: 0.58, alpha: 1) : UIColor(red: 0.74, green: 0.76, blue: 0.80, alpha: 1)
        for (def, v) in keys {
            var bg = key, tint = fg
            if def.kind == .returnKey && returnIsBlue { bg = .systemBlue; tint = .white }
            if def.kind == .language { tint = dark ? UIColor(red: 0.62, green: 0.60, blue: 1, alpha: 1) : UIColor(red: 0.31, green: 0.27, blue: 0.90, alpha: 1) }
            if cursorMode { bg = dark ? UIColor(white: 0.32, alpha: 1) : UIColor(white: 0.93, alpha: 1) }
            v.normalColor = bg
            v.pressedColor = pressed
            if v !== touchKey && v.backgroundColor != bg { v.backgroundColor = bg }
            if v.label.textColor != tint { v.label.textColor = tint; v.icon.tintColor = tint }
        }
        popup.dark = dark
        alternates.dark = dark
    }

    // MARK: touches

    private func cap(at p: CGPoint) -> KeyCap? {
        var best: KeyCap?; var bestD = CGFloat.greatestFiniteMagnitude
        for (_, v) in keys {
            let f = v.frame.insetBy(dx: -3, dy: -5.5)
            if f.contains(p) { return v }
            let dx = max(f.minX - p.x, 0, p.x - f.maxX), dy = max(f.minY - p.y, 0, p.y - f.maxY)
            let d = dx * dx + dy * dy
            if d < bestD { bestD = d; best = v }
        }
        return bestD < 44 * 44 ? best : nil   // edges and gaps belong to the nearest key, like the system keyboard
    }
    private func kind(of cap: KeyCap) -> KeyKind? { keys.first { $0.view === cap }?.def.kind }

    private var lastHaptic: CFTimeInterval = 0
    /// One vibration per key press at most (overlapping touches in fast typing must not double up).
    private func tick() {
        let t = CACurrentMediaTime()
        guard t - lastHaptic > 0.04 else { return }
        lastHaptic = t
        Diag.haptics += 1
        feedback.impactOccurred(intensity: 0.5)   // the system keyboard's tap is lighter than a full .light impact
    }

    private func press(_ c: KeyCap) {
        c.backgroundColor = c.pressedColor
        if haptics { tick() } else { UIDevice.current.playInputClick() }
    }
    private func release(_ c: KeyCap) { c.backgroundColor = c.normalColor }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if haptics { feedback.prepare() }
        for t in touches {
            let p = t.location(in: self)
            Diag.touches += 1
            Diag.touchStart = CACurrentMediaTime()
            guard let c = cap(at: p), let k = kind(of: c), k != .globe else { continue }
            // a new touch while another is down: the earlier key is typed now (fast two-thumb typing)
            if let prev = touch, let pk = touchKey { finish(prev, on: pk) }
            touch = t; touchKey = c; touchStart = p; slideFromLayer = false
            press(c)
            switch k {
            case .char:
                if traitCollection.horizontalSizeClass == .compact { popup.show(over: c, in: self) }
                startHold(after: 0.45) { [weak self] in self?.showAlternates(for: c) }
            case .backspace:
                delegate?.keyboard(self, didTap: .backspace)
                repeatCount = 0
                startHold(after: 0.45) { [weak self] in self?.startRepeat() }
            case .space:
                startHold(after: 0.4) { [weak self] in self?.enterCursorMode(at: p.x) }
            case .shift:
                delegate?.keyboard(self, didTap: .shift)
            case .layer:
                // the system keyboard switches on touch-down and lets you slide onto a symbol
                delegate?.keyboard(self, didTap: k)
                slideFromLayer = true
                if let nc = cap(at: p) { touchKey = nc; nc.backgroundColor = nc.pressedColor }
            default: break
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touch, touches.contains(t), let current = touchKey else { return }
        let p = t.location(in: self)
        if cursorMode {
            let step = 9 * bounds.width / 402
            let n = Int((p.x - cursorAnchor) / step)
            if n != 0 { delegate?.keyboard(self, moveCursorBy: n); cursorAnchor += CGFloat(n) * step }
            return
        }
        if !alternates.isHidden { alternates.select(at: t.location(in: alternates)); return }
        guard let k = kind(of: current), k != .backspace, k != .shift else { return }
        // a tap wobbles: keep the key it started on unless the finger really slid onto another one
        guard slideFromLayer || hypot(p.x - touchStart.x, p.y - touchStart.y) > 14 else { return }
        guard let c = cap(at: p), c !== current, c.frame.insetBy(dx: 2, dy: 2).contains(p),
              let nk = kind(of: c), nk != .globe, nk != .backspace, nk != .shift else { return }
        release(current)
        touchKey = c
        c.backgroundColor = c.pressedColor
        holdTimer?.invalidate()
        if case .char = nk, traitCollection.horizontalSizeClass == .compact { popup.show(over: c, in: self) } else { popup.isHidden = true }
        if case .char = nk { startHold(after: 0.45) { [weak self] in self?.showAlternates(for: c) } }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches where t === touch {
            if let c = touchKey { finish(t, on: c) }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches where t === touch {
            if let c = touchKey { release(c) }
            reset()
        }
    }

    /// The touch that owns a key ended (or a newer touch began): type that key.
    private func finish(_ t: UITouch, on c: KeyCap) {
        holdTimer?.invalidate(); holdTimer = nil
        release(c)
        popup.isHidden = true
        let wasSlide = slideFromLayer
        if cursorMode {
            cursorMode = false
            refreshLabels()
            delegate?.keyboardCursorModeEnded(self)
        } else if !alternates.isHidden {
            if let s = alternates.selected { delegate?.keyboard(self, insertAlternate: s) }
            alternates.isHidden = true
        } else if let k = kind(of: c) {
            switch k {
            case .backspace, .shift, .layer: break   // handled on touch-down
            default:
                delegate?.keyboard(self, didTap: k)
                if wasSlide, case .char = k { delegate?.keyboard(self, didTap: .layer(.letters)) }
            }
        }
        reset()
    }

    private func reset() {
        holdTimer?.invalidate(); holdTimer = nil
        touch = nil; touchKey = nil; slideFromLayer = false
        popup.isHidden = true
        alternates.isHidden = true
        if cursorMode { cursorMode = false; refreshLabels(); delegate?.keyboardCursorModeEnded(self) }
    }

    private func startHold(after s: TimeInterval, _ f: @escaping () -> Void) {
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: s, repeats: false) { _ in f() }
    }

    private func startRepeat() {
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.09, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.repeatCount += 1
            self.delegate?.keyboardBackspaceRepeat(self, count: self.repeatCount)
        }
    }

    private func enterCursorMode(at x: CGFloat) {
        cursorMode = true
        cursorAnchor = touch?.location(in: self).x ?? x
        popup.isHidden = true
        if haptics { tick() }
        refreshLabels()
    }

    // MARK: long-press alternates

    static let alternateTable: [String: [String]] = [
        "a": ["a", "ă", "â", "á", "à", "ả", "ã", "ạ"], "e": ["e", "ê", "é", "è", "ẻ", "ẽ", "ẹ"],
        "o": ["o", "ô", "ơ", "ó", "ò", "ỏ", "õ", "ọ"], "u": ["u", "ư", "ú", "ù", "ủ", "ũ", "ụ"],
        "i": ["i", "í", "ì", "ỉ", "ĩ", "ị"], "y": ["y", "ý", "ỳ", "ỷ", "ỹ", "ỵ"], "d": ["d", "đ"],
        ".": [".", "…"], "-": ["-", "–", "—", "•"], "'": ["'", "’", "‘", "`"], "\"": ["\"", "“", "”", "„", "«", "»"],
        "!": ["!", "¡"], "?": ["?", "¿"], "$": ["$", "₫", "€", "£", "¥", "₩", "¢"], "0": ["0", "°"], "&": ["&", "§"],
        "/": ["/", "\\"], "%": ["%", "‰"],
    ]

    private func showAlternates(for c: KeyCap) {
        guard let k = kind(of: c), case .char(let ch) = k, let list = Self.alternateTable[ch] else { return }
        let upper = shift != .off && layer_ == .letters
        popup.isHidden = true
        alternates.show(list.map { upper ? $0.uppercased() : $0 }, over: c, in: self)
        if haptics { tick() }
    }
}

/// One key.
final class KeyCap: UIView {
    let label = UILabel()
    let icon = UIImageView()
    var normalColor: UIColor = .white
    var pressedColor: UIColor = .lightGray
    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 8.5
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.22
        layer.shadowRadius = 0
        layer.shadowOffset = CGSize(width: 0, height: 1)
        label.textAlignment = .center
        icon.contentMode = .center
        addSubview(label); addSubview(icon)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: 2, dy: 0).offsetBy(dx: 0, dy: -1)
        icon.frame = bounds
        // an explicit shadow path: without it every key's shadow is rendered offscreen on each frame
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
    }
}

/// The balloon shown above a pressed letter: the key itself grows upward into a wider bubble.
final class KeyPopup: UIView {
    let label = UILabel()
    private let shape = CAShapeLayer()
    var dark = false { didSet { shape.fillColor = (dark ? UIColor(white: 0.42, alpha: 1) : .white).cgColor; label.textColor = dark ? .white : .black } }
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.addSublayer(shape)
        shape.fillColor = UIColor.white.cgColor
        shape.shadowColor = UIColor.black.cgColor
        shape.shadowOpacity = 0.28
        shape.shadowRadius = 3
        shape.shadowOffset = CGSize(width: 0, height: 1)
        label.font = .systemFont(ofSize: 38, weight: .regular)
        label.textAlignment = .center
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(over key: KeyCap, in parent: UIView) {
        label.text = key.label.text
        let k = key.frame
        let extra: CGFloat = 13, bubbleH: CGFloat = 54
        var bubble = CGRect(x: k.minX - extra, y: k.minY - bubbleH + 6, width: k.width + 2 * extra, height: bubbleH)
        // keep the bubble on screen at the left and right edges
        if bubble.minX < 1 { bubble.origin.x = 1 }
        if bubble.maxX > parent.bounds.width - 1 { bubble.origin.x = parent.bounds.width - 1 - bubble.width }
        bubble.origin.y = max(bubble.minY, 0)
        let all = bubble.union(k)
        frame = all
        let b = bubble.offsetBy(dx: -all.minX, dy: -all.minY), kk = k.offsetBy(dx: -all.minX, dy: -all.minY)
        let path = UIBezierPath()
        let r: CGFloat = 10, rk: CGFloat = 8.5, neck = kk.minY + 4
        path.move(to: CGPoint(x: b.minX + r, y: b.minY))
        path.addLine(to: CGPoint(x: b.maxX - r, y: b.minY))
        path.addQuadCurve(to: CGPoint(x: b.maxX, y: b.minY + r), controlPoint: CGPoint(x: b.maxX, y: b.minY))
        path.addLine(to: CGPoint(x: b.maxX, y: b.maxY - 10))
        path.addCurve(to: CGPoint(x: kk.maxX, y: neck + 8), controlPoint1: CGPoint(x: b.maxX, y: b.maxY), controlPoint2: CGPoint(x: kk.maxX, y: neck))
        path.addLine(to: CGPoint(x: kk.maxX, y: kk.maxY - rk))
        path.addQuadCurve(to: CGPoint(x: kk.maxX - rk, y: kk.maxY), controlPoint: CGPoint(x: kk.maxX, y: kk.maxY))
        path.addLine(to: CGPoint(x: kk.minX + rk, y: kk.maxY))
        path.addQuadCurve(to: CGPoint(x: kk.minX, y: kk.maxY - rk), controlPoint: CGPoint(x: kk.minX, y: kk.maxY))
        path.addLine(to: CGPoint(x: kk.minX, y: neck + 8))
        path.addCurve(to: CGPoint(x: b.minX, y: b.maxY - 10), controlPoint1: CGPoint(x: kk.minX, y: neck), controlPoint2: CGPoint(x: b.minX, y: b.maxY))
        path.addLine(to: CGPoint(x: b.minX, y: b.minY + r))
        path.addQuadCurve(to: CGPoint(x: b.minX + r, y: b.minY), controlPoint: CGPoint(x: b.minX, y: b.minY))
        path.close()
        shape.path = path.cgPath
        shape.shadowPath = path.cgPath
        label.frame = CGRect(x: b.minX, y: b.minY + 2, width: b.width, height: b.height - 8)
        isHidden = false
        parent.bringSubviewToFront(self)
    }
}

/// The strip of alternates shown when a key is held; the finger slides to pick one.
final class AlternatesView: UIView {
    private var labels: [UILabel] = []
    private(set) var selected: String?
    private let highlight = UIView()
    var dark = false { didSet { backgroundColor = dark ? UIColor(white: 0.42, alpha: 1) : .white; labels.forEach { $0.textColor = dark ? .white : .black } } }
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .white
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.28
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 1)
        highlight.backgroundColor = .systemBlue
        highlight.layer.cornerRadius = 7
        addSubview(highlight)
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(_ items: [String], over key: KeyCap, in parent: UIView) {
        labels.forEach { $0.removeFromSuperview() }
        labels = items.map { s in
            let l = UILabel(); l.text = s; l.font = .systemFont(ofSize: 24); l.textAlignment = .center
            l.textColor = dark ? .white : .black; addSubview(l); return l
        }
        let w: CGFloat = 34, h: CGFloat = 46
        let total = CGFloat(items.count) * w + 8
        var x = key.frame.minX - 4
        if x + total > parent.bounds.width - 2 { x = parent.bounds.width - 2 - total }
        x = max(2, x)
        frame = CGRect(x: x, y: max(0, key.frame.minY - h - 6), width: total, height: h)
        for (i, l) in labels.enumerated() { l.frame = CGRect(x: 4 + CGFloat(i) * w, y: 0, width: w, height: h) }
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 10).cgPath
        selectIndex(0)
        isHidden = false
        parent.bringSubviewToFront(self)
    }

    func select(at p: CGPoint) {
        guard !labels.isEmpty else { return }
        let i = min(max(Int((p.x - 4) / 34), 0), labels.count - 1)
        selectIndex(i)
    }

    private func selectIndex(_ i: Int) {
        selected = labels[i].text
        highlight.frame = labels[i].frame.insetBy(dx: 1, dy: 5)
        for (j, l) in labels.enumerated() { l.textColor = j == i ? .white : (dark ? .white : .black) }
    }
}
