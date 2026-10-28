import UIKit

/// What a key does.
enum KeyKind: Equatable {
    case char(String)      // inserts this (letters stored lowercase)
    case shift, backspace, space, returnKey, globe, language
    case layer(KeyboardView.Layer)
}

struct KeyDef {
    var kind: KeyKind
    var width: CGFloat = 1     // in letter-key units
    var gapBefore: CGFloat = 0
}

protocol KeyboardViewDelegate: AnyObject {
    func keyboard(_ view: KeyboardView, didTap kind: KeyKind)
    func keyboardBackspaceRepeat(_ view: KeyboardView)
}

/// A system-looking keyboard: keys are plain views, touches are handled by the container so fast
/// typing between keys never gets lost.
final class KeyboardView: UIView {
    enum Layer { case letters, numbers, symbols }
    enum Shift { case off, on, locked }

    weak var delegate: KeyboardViewDelegate?
    var layer_: Layer = .letters { didSet { rebuild() } }
    var shift: Shift = .off { didSet { if shift != oldValue { refreshLabels() } } }
    var dark = false { didSet { if dark != oldValue { refreshColors() } } }
    var showsGlobe = true { didSet { if showsGlobe != oldValue { rebuild() } } }
    var languageTitle = "Tiếng Việt" { didSet { refreshLabels() } }
    var languageShort = "VI" { didSet { refreshLabels() } }
    var returnTitle = "return" { didSet { refreshLabels() } }
    var returnIsBlue = false { didSet { refreshColors() } }
    var globeButton: UIButton?

    private var keyViews: [(def: KeyDef, view: KeyCap)] = []
    private var activeTouches: [UITouch: KeyCap] = [:]
    private let popup = KeyPopup()
    private var repeatTimer: Timer?

    /// Shorter rows in landscape on iPhone, like the system keyboard.
    static func rowHeight(compactHeight: Bool) -> CGFloat { compactHeight ? 42 : 56 }
    static func keyboardHeight(compactHeight: Bool) -> CGFloat { 4 * rowHeight(compactHeight: compactHeight) + 12 }
    private var rowH: CGFloat { Self.rowHeight(compactHeight: traitCollection.verticalSizeClass == .compact) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        rebuild()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: layout

    private func rows() -> [[KeyDef]] {
        func chars(_ s: String) -> [KeyDef] { s.map { KeyDef(kind: .char(String($0))) } }
        var bottom: [KeyDef] = []
        switch layer_ {
        case .letters: bottom.append(KeyDef(kind: .layer(.numbers), width: 1.25))
        case .numbers, .symbols: bottom.append(KeyDef(kind: .layer(.letters), width: 1.25))
        }
        if showsGlobe { bottom.append(KeyDef(kind: .globe, width: 1.25)) }
        bottom.append(KeyDef(kind: .language, width: 1.25))
        bottom.append(KeyDef(kind: .space, width: showsGlobe ? 4.0 : 5.25))
        bottom.append(KeyDef(kind: .returnKey, width: 2.25))
        switch layer_ {
        case .letters:
            return [chars("qwertyuiop"),
                    chars("asdfghjkl"),
                    [KeyDef(kind: .shift, width: 1.3)] + chars("zxcvbnm").enumerated().map { i, k in var k = k; if i == 0 { k.gapBefore = 0.2 }; return k }
                        + [KeyDef(kind: .backspace, width: 1.3, gapBefore: 0.2)],
                    bottom]
        case .numbers:
            return [chars("1234567890"),
                    chars("-/:;()$&@\""),
                    [KeyDef(kind: .layer(.symbols), width: 1.3)] + [".", ",", "?", "!", "'"].enumerated().map { i, c in KeyDef(kind: .char(c), width: 1.42, gapBefore: i == 0 ? 0.2 : 0) }
                        + [KeyDef(kind: .backspace, width: 1.3, gapBefore: 0.2)],
                    bottom]
        case .symbols:
            return [chars("[]{}#%^*+="),
                    chars("_\\|~<>€£¥•"),
                    [KeyDef(kind: .layer(.numbers), width: 1.3)] + [".", ",", "?", "!", "'"].enumerated().map { i, c in KeyDef(kind: .char(c), width: 1.42, gapBefore: i == 0 ? 0.2 : 0) }
                        + [KeyDef(kind: .backspace, width: 1.3, gapBefore: 0.2)],
                    bottom]
        }
    }

    private func rebuild() {
        keyViews.forEach { $0.view.removeFromSuperview() }
        keyViews = []
        globeButton?.removeFromSuperview(); globeButton = nil
        for row in rows() {
            for def in row {
                let cap = KeyCap()
                cap.isUserInteractionEnabled = false
                addSubview(cap)
                keyViews.append((def, cap))
                if def.kind == .globe {
                    let b = UIButton(type: .custom)
                    addSubview(b)
                    globeButton = b
                }
            }
        }
        addSubview(popup)
        popup.isHidden = true
        refreshLabels(); refreshColors()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side: CGFloat = 3, hGap: CGFloat = 6, top: CGFloat = 8
        let rowsDefs = rows()
        var index = 0
        for (r, row) in rowsDefs.enumerated() {
            let units = row.reduce(0) { $0 + $1.width + $1.gapBefore }
            let letterUnits: CGFloat = 10
            let unit = (bounds.width - 2 * side) / letterUnits
            // rows with fewer units (asdf...) are centered like the system keyboard
            var x = side + max(0, (letterUnits - units) * unit / 2)
            if r == rowsDefs.count - 1 || units >= letterUnits - 0.01 { x = side }
            let scale = units > letterUnits ? letterUnits / units : 1
            for def in row {
                x += def.gapBefore * unit * scale
                let w = def.width * unit * scale
                let frame = CGRect(x: x + hGap / 2, y: top + CGFloat(r) * rowH, width: w - hGap, height: rowH - (rowH < 50 ? 8 : 12))
                let v = keyViews[index].view
                v.frame = frame
                if def.kind == .globe { globeButton?.frame = frame.insetBy(dx: -hGap / 2, dy: -6) }
                x += w
                index += 1
            }
        }
    }

    // MARK: appearance

    private func title(for kind: KeyKind) -> (String?, UIImage?) {
        let sym = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        switch kind {
        case .char(let c): return (shift != .off && layer_ == .letters ? c.uppercased() : c, nil)
        case .shift: return (nil, UIImage(systemName: shift == .locked ? "capslock.fill" : (shift == .on ? "shift.fill" : "shift"), withConfiguration: sym))
        case .backspace: return (nil, UIImage(systemName: "delete.left", withConfiguration: sym))
        case .space: return (languageTitle, nil)
        case .returnKey: return returnTitle == "return" ? (nil, UIImage(systemName: "return", withConfiguration: sym)) : (returnTitle, nil)
        case .globe: return (nil, UIImage(systemName: "globe", withConfiguration: sym))
        case .language: return (languageShort, nil)
        case .layer(let l): return (l == .letters ? "ABC" : (l == .numbers ? "123" : "#+="), nil)
        }
    }

    private func isSpecial(_ kind: KeyKind) -> Bool {
        switch kind { case .char, .space: return false; case .returnKey: return !returnIsBlue; default: return true }
    }

    private func refreshLabels() {
        for (def, v) in keyViews {
            let (t, img) = title(for: def.kind)
            v.label.text = t; v.icon.image = img
            switch def.kind {
            case .char: v.label.font = .systemFont(ofSize: 25, weight: .regular)
            case .space: v.label.font = .systemFont(ofSize: 15, weight: .regular)
            case .language: v.label.font = .systemFont(ofSize: 16, weight: .semibold)
            default: v.label.font = .systemFont(ofSize: 16, weight: .regular)
            }
        }
        refreshColors()
    }

    private func refreshColors() {
        let fg: UIColor = dark ? .white : .black
        let normal: UIColor = dark ? UIColor(white: 0.42, alpha: 1) : .white
        let special: UIColor = dark ? UIColor(white: 0.26, alpha: 1) : UIColor(red: 0.67, green: 0.70, blue: 0.74, alpha: 1)
        for (def, v) in keyViews {
            var bg = isSpecial(def.kind) ? special : normal
            var tint = fg
            if def.kind == .returnKey && returnIsBlue { bg = .systemBlue; tint = .white }
            if def.kind == .shift && shift != .off { bg = normal }
            if def.kind == .language { tint = UIColor(red: 0.31, green: 0.27, blue: 0.90, alpha: 1); if dark { tint = UIColor(red: 0.62, green: 0.60, blue: 1, alpha: 1) } }
            v.normalColor = bg
            v.pressedColor = isSpecial(def.kind) ? normal : special
            v.backgroundColor = bg
            v.label.textColor = tint; v.icon.tintColor = tint
        }
        popup.dark = dark
    }

    // MARK: touches

    private func cap(at p: CGPoint) -> KeyCap? {
        var best: KeyCap?; var bestD = CGFloat.greatestFiniteMagnitude
        for (_, v) in keyViews {
            let f = v.frame.insetBy(dx: -3, dy: -6)
            if f.contains(p) { return v }
            let dx = max(f.minX - p.x, 0, p.x - f.maxX), dy = max(f.minY - p.y, 0, p.y - f.maxY)
            let d = dx * dx + dy * dy
            if d < bestD { bestD = d; best = v }
        }
        return bestD < 400 ? best : nil
    }
    private func def(of cap: KeyCap) -> KeyDef? { keyViews.first { $0.view === cap }?.def }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            guard let c = cap(at: t.location(in: self)), let d = def(of: c) else { continue }
            if d.kind == .globe { continue }
            activeTouches[t] = c
            c.backgroundColor = c.pressedColor
            UIDevice.current.playInputClick()
            if case .char = d.kind, traitCollection.horizontalSizeClass == .compact { showPopup(for: c) }
            if d.kind == .backspace {
                delegate?.keyboard(self, didTap: .backspace)
                repeatTimer?.invalidate()
                repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
                    self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.09, repeats: true) { [weak self] _ in
                        guard let self else { return }
                        self.delegate?.keyboardBackspaceRepeat(self)
                    }
                }
            }
            if d.kind == .shift { delegate?.keyboard(self, didTap: .shift) }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            guard let old = activeTouches[t], let od = def(of: old), od.kind != .backspace, od.kind != .shift else { continue }
            guard let c = cap(at: t.location(in: self)), c !== old, let d = def(of: c), d.kind != .globe, d.kind != .backspace, d.kind != .shift else { continue }
            old.backgroundColor = old.normalColor
            activeTouches[t] = c
            c.backgroundColor = c.pressedColor
            if case .char = d.kind, traitCollection.horizontalSizeClass == .compact { showPopup(for: c) } else { popup.isHidden = true }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            guard let c = activeTouches.removeValue(forKey: t), let d = def(of: c) else { continue }
            c.backgroundColor = c.normalColor
            popup.isHidden = true
            switch d.kind {
            case .backspace: repeatTimer?.invalidate(); repeatTimer = nil
            case .shift: break
            default: delegate?.keyboard(self, didTap: d.kind)
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { activeTouches.removeValue(forKey: t)?.backgroundColor = .clear }
        repeatTimer?.invalidate(); repeatTimer = nil
        popup.isHidden = true
        refreshColors()
    }

    private func showPopup(for cap: KeyCap) {
        popup.label.text = cap.label.text
        let w = cap.frame.width + 20, h = cap.frame.height + 46
        popup.frame = CGRect(x: cap.frame.midX - w / 2, y: cap.frame.maxY - h, width: w, height: h)
        popup.frame.origin.x = min(max(popup.frame.minX, 0), bounds.width - w)
        popup.isHidden = false
        bringSubviewToFront(popup)
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
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 0
        layer.shadowOffset = CGSize(width: 0, height: 1)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        icon.contentMode = .center
        addSubview(label); addSubview(icon)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: 2, dy: 0)
        icon.frame = bounds
    }
}

/// The enlarged letter shown above a pressed key.
final class KeyPopup: UIView {
    let label = UILabel()
    var dark = false { didSet { backgroundColor = dark ? UIColor(white: 0.42, alpha: 1) : .white; label.textColor = dark ? .white : .black } }
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .white
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 1)
        label.font = .systemFont(ofSize: 34)
        label.textAlignment = .center
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = CGRect(x: 0, y: 4, width: bounds.width, height: bounds.height * 0.55)
    }
}
