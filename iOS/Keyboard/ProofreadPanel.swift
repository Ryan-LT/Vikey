import UIKit

/// The proofread preview above the keys: the corrected text (changed words highlighted), Cancel and Apply.
/// Nothing changes in the app until Apply (Tony: preview before replacing).
final class ProofreadPanel: UIView {
    static let height: CGFloat = 132
    var onApply: (() -> Void)?
    var onCancel: (() -> Void)?
    var dark = false { didSet { restyle() } }
    private let title = UILabel()
    private let text = UITextView()
    private let cancel = UIButton(type: .system)
    private let apply = UIButton(type: .system)
    private var original = "", corrected = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.text = String(localized: "Bản đã sửa").uppercased()
        text.isEditable = false; text.isSelectable = false
        text.backgroundColor = .clear
        text.textContainerInset = .zero; text.textContainer.lineFragmentPadding = 0
        cancel.setTitle(String(localized: "Huỷ"), for: .normal)
        apply.setTitle(String(localized: "Áp dụng"), for: .normal)
        for b in [cancel, apply] { b.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold); b.layer.cornerRadius = 8.5; b.layer.cornerCurve = .continuous }
        cancel.addTarget(self, action: #selector(tapCancel), for: .touchUpInside)
        apply.addTarget(self, action: #selector(tapApply), for: .touchUpInside)
        [title, text, cancel, apply].forEach(addSubview)
        restyle()
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(original: String, corrected: String) {
        self.original = original; self.corrected = corrected
        restyle()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // the buttons line up with the keys below: the same side margin and gap
        let W = bounds.width, side: CGFloat = 6.67, gap: CGFloat = 6, M: CGFloat = 14
        title.frame = CGRect(x: M, y: 10, width: W - 2 * M, height: 16)
        let bh: CGFloat = 38
        let by = bounds.height - bh - 6
        text.frame = CGRect(x: M, y: 30, width: W - 2 * M, height: by - 36)
        let bw = (W - 2 * side - gap) / 2
        cancel.frame = CGRect(x: side, y: by, width: bw, height: bh)
        apply.frame = CGRect(x: side + bw + gap, y: by, width: bw, height: bh)
    }

    private func restyle() {
        let fg: UIColor = dark ? .white : .black
        let brand = dark ? UIColor(red: 0.62, green: 0.60, blue: 1, alpha: 1) : UIColor(red: 0.31, green: 0.27, blue: 0.90, alpha: 1)
        title.textColor = .secondaryLabel
        cancel.backgroundColor = dark ? UIColor(white: 1, alpha: 0.16) : UIColor(white: 1, alpha: 0.9)
        cancel.setTitleColor(fg, for: .normal)
        apply.backgroundColor = brand
        apply.setTitleColor(.white, for: .normal)
        text.attributedText = Self.highlighted(corrected, against: original, fg: fg, mark: brand)
    }

    /// The corrected text with the words that changed in the brand colour (word-level diff).
    static func highlighted(_ new: String, against old: String, fg: UIColor, mark: UIColor) -> NSAttributedString {
        let a = old.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let b = new.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        // longest common subsequence of words: what's not in it changed
        var dp = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        if a.count * b.count < 40_000 {
            for i in stride(from: a.count - 1, through: 0, by: -1) {
                for j in stride(from: b.count - 1, through: 0, by: -1) {
                    dp[i][j] = a[i] == b[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
                }
            }
        }
        var same = Set<Int>(), i = 0, j = 0
        while i < a.count && j < b.count {
            if a[i] == b[j] { same.insert(j); i += 1; j += 1 } else if dp[i + 1][j] >= dp[i][j + 1] { i += 1 } else { j += 1 }
        }
        let out = NSMutableAttributedString()
        let font = UIFont.systemFont(ofSize: 16)
        for (k, w) in b.enumerated() {
            if k > 0 { out.append(NSAttributedString(string: " ", attributes: [.font: font, .foregroundColor: fg])) }
            let changed = !same.contains(k) && !w.isEmpty
            out.append(NSAttributedString(string: w, attributes: [.font: changed ? UIFont.systemFont(ofSize: 16, weight: .semibold) : font,
                                                                  .foregroundColor: changed ? mark : fg]))
        }
        return out
    }

    @objc private func tapCancel() { onCancel?() }
    @objc private func tapApply() { onApply?() }
}
