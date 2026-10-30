import Foundation

/// Next-word table: "context<TAB>w1<TAB>w2<TAB>w3" lines, sorted by context bytes (Tools/predict/pack.py from
/// vikey-data's counts of 2- and 3-word sequences). Memory-mapped and binary-searched: no load time, little memory.
final class NextWords {
    static let shared = NextWords()
    private let data: Data?
    private var lineStarts: [Int32] = []

    init(bundle: Bundle = .main) {
        let url = bundle.url(forResource: "NextWords", withExtension: "tsv") ?? Bundle(for: NextWords.self).url(forResource: "NextWords", withExtension: "tsv")
        data = url.flatMap { try? Data(contentsOf: $0, options: .alwaysMapped) }
        guard let d = data else { return }
        d.withUnsafeBytes { (p: UnsafeRawBufferPointer) in
            let b = p.bindMemory(to: UInt8.self)
            var starts: [Int32] = [0]
            starts.reserveCapacity(b.count / 24)
            for i in 0..<b.count where b[i] == 10 && i + 1 < b.count { starts.append(Int32(i + 1)) }
            lineStarts = starts
        }
    }

    var isEmpty: Bool { lineStarts.isEmpty }

    /// Up to 3 next words after the last one or two words of `before` (2-word context first).
    func predict(before: String) -> [String] {
        let words = Self.lastWords(before)
        guard !words.isEmpty else { return [] }
        var out: [String] = []
        if words.count == 2 { out = lookup(words.joined(separator: " ")) }
        if out.count < 3, let last = words.last {
            for w in lookup(last) where !out.contains(w) && out.count < 3 { out.append(w) }
        }
        return out
    }

    /// The last two words of the text if the cursor sits after a space (lowercase; a sentence end stops it).
    static func lastWords(_ before: String) -> [String] {
        guard before.hasSuffix(" ") else { return [] }
        var words: [String] = [], cur = ""
        for ch in before.dropLast().reversed() {
            if ch.isLetter { cur.insert(ch, at: cur.startIndex); continue }
            if !cur.isEmpty { words.insert(cur.lowercased(), at: 0); cur = "" }
            if words.count == 2 || ch != " " { break }
        }
        if !cur.isEmpty && words.count < 2 { words.insert(cur.lowercased(), at: 0) }
        return Array(words.suffix(2))
    }

    private func lookup(_ key: String) -> [String] {
        guard let d = data, !lineStarts.isEmpty else { return [] }
        let k = Array(key.precomposedStringWithCanonicalMapping.utf8)
        return d.withUnsafeBytes { (p: UnsafeRawBufferPointer) -> [String] in
            let b = p.bindMemory(to: UInt8.self)
            func compare(_ line: Int) -> Int {   // the line's context vs the key
                var i = Int(lineStarts[line]), j = 0
                while i < b.count, b[i] != 9, b[i] != 10, j < k.count {
                    if b[i] != k[j] { return b[i] < k[j] ? -1 : 1 }
                    i += 1; j += 1
                }
                let lineEnded = i >= b.count || b[i] == 9 || b[i] == 10
                if lineEnded && j == k.count { return 0 }
                return lineEnded ? -1 : 1
            }
            var lo = 0, hi = lineStarts.count - 1
            while lo <= hi {
                let mid = (lo + hi) / 2, c = compare(mid)
                if c == 0 {
                    var i = Int(lineStarts[mid]), end = i
                    while end < b.count && b[end] != 10 { end += 1 }
                    while i < end && b[i] != 9 { i += 1 }
                    guard i < end else { return [] }
                    let rest = String(decoding: UnsafeBufferPointer(rebasing: b[(i + 1)..<end]), as: UTF8.self)
                    return rest.split(separator: "\t").map(String.init)
                }
                if c < 0 { lo = mid + 1 } else { hi = mid - 1 }
            }
            return []
        }
    }
}
