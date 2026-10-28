import XCTest
import UIKit

/// Performance lock for the keyboard (Tony: "tests that guarantee performance").
/// What made build 2 laggy was cross-process work per key, not the engine, so these tests count it:
/// at most one read of the text field per key, no shared-settings reads while typing, shadows with a
/// fixed path, and a time budget per key.
class CountingProxy: NSObject, UITextDocumentProxy {
    var text = ""
    var reads = 0, deletes = 0, inserts = 0
    var documentContextBeforeInput: String? { reads += 1; return text }
    var documentContextAfterInput: String? { nil }
    var selectedText: String? { nil }
    var documentInputMode: UITextInputMode? { nil }
    var documentIdentifier: UUID { UUID() }
    var hasText: Bool { !text.isEmpty }
    func adjustTextPosition(byCharacterOffset offset: Int) {}
    func setMarkedText(_ markedText: String, selectedRange: NSRange) {}
    func unmarkText() {}
    func insertText(_ t: String) { inserts += 1; text += t }
    func deleteBackward() { deletes += 1; if !text.isEmpty { text.removeLast() } }
}

/// A text field that models marked text: committed text + the marked word.
final class MarkedProxy: CountingProxy {
    var committed = "", marked = ""
    override var documentContextBeforeInput: String? { reads += 1; return committed + marked }
    override func setMarkedText(_ markedText: String, selectedRange: NSRange) { inserts += 1; marked = markedText; text = committed + marked }
    override func unmarkText() { committed += marked; marked = ""; text = committed }
    override func insertText(_ t: String) { inserts += 1; committed += marked + t; marked = ""; text = committed }
    override func deleteBackward() { deletes += 1; if !marked.isEmpty { marked.removeLast() } else if !committed.isEmpty { committed.removeLast() }; text = committed + marked }
}

final class KeyboardPerformanceTests: XCTestCase {
    // mixed Vietnamese/English, typed in Telex, ~2,000 keys
    static let sample = String(repeating: "tooi ddi hocj sorry em i love phowr order traf suwax nhes booking phongf chuaw meeting lucs ba giowf nhes mixx verr ", count: 18)

    private func makeKeyboard() -> (KeyboardViewController, CountingProxy) {
        let vc = KeyboardViewController()
        let p = CountingProxy()
        vc.proxy = p
        vc.loadViewIfNeeded()
        vc.viewWillAppear(false)
        return (vc, p)
    }

    private let sender = KeyboardView()
    private func type(_ s: String, into vc: KeyboardViewController) {
        for ch in s {
            if ch == " " { vc.keyboard(sender, didTap: .space) }
            else { vc.keyboard(sender, didTap: .char(String(ch))) }
        }
    }

    func testMarkedTextModeTypesCorrectly() {
        VKSettings.defaults.set(true, forKey: VKSettings.Key.markedText)
        defer { VKSettings.defaults.set(false, forKey: VKSettings.Key.markedText) }
        let vc = KeyboardViewController()
        let p = MarkedProxy()
        vc.proxy = p
        vc.loadViewIfNeeded()
        vc.viewWillAppear(false)
        type("tooi ddi hocj sorry em i love phowr mixx ", into: vc)
        XCTAssertEqual(p.committed + p.marked, "Tôi đi học sorry em i love phở mix ")
        let before = p.deletes + p.inserts
        type(Self.sample, into: vc)
        let calls = Double(p.deletes + p.inserts - before) / Double(Self.sample.count)
        print("keyboard (marked): \(String(format: "%.2f", calls)) text edits per key")
        XCTAssertLessThan(calls, 1.6)
    }

    func testTypesCorrectly() {
        let (vc, p) = makeKeyboard()
        type("tooi ddi hocj sorry em ", into: vc)
        XCTAssertEqual(p.text, "Tôi đi học sorry em ")
    }

    func testAtMostOneTextReadPerKey() {
        let (vc, p) = makeKeyboard()
        let readsBefore = p.reads
        let keys = Self.sample.count
        type(Self.sample, into: vc)
        let perKey = Double(p.reads - readsBefore) / Double(keys)
        XCTAssertLessThanOrEqual(perKey, 1.0, "text field reads per key: \(perKey) (each one is a cross-process call on device)")
    }

    func testNoSettingsReadsWhileTyping() {
        let (vc, _) = makeKeyboard()
        let before = VKSettings.reads
        type(Self.sample, into: vc)
        XCTAssertEqual(VKSettings.reads, before, "shared settings were read while typing")
    }

    func testFewEditsPerKey() {
        let (vc, p) = makeKeyboard()
        let keys = Self.sample.count
        type(Self.sample, into: vc)
        let calls = Double(p.deletes + p.inserts) / Double(keys)
        print("keyboard: \(String(format: "%.2f", calls)) text edits per key")
        XCTAssertLessThan(calls, 1.6, "\(calls) delete/insert calls per key: send only the characters that change")
    }

    func testTimePerKey() {
        let (vc, _) = makeKeyboard()
        let keys = Self.sample.count
        let start = CFAbsoluteTimeGetCurrent()
        type(Self.sample, into: vc)
        let perKeyUs = (CFAbsoluteTimeGetCurrent() - start) / Double(keys) * 1e6
        print("keyboard: \(Int(perKeyUs)) µs per key")
        XCTAssertLessThan(perKeyUs, 300, "keyboard logic takes \(Int(perKeyUs)) µs per key")
    }

    func testKeyShadowsHaveFixedPaths() {
        let kb = KeyboardView(frame: CGRect(x: 0, y: 0, width: 402, height: KeyboardView.keyboardHeight(compactHeight: false)))
        kb.layoutIfNeeded()
        let caps = kb.subviews.compactMap { $0 as? KeyCap }
        XCTAssertGreaterThan(caps.count, 30)
        for c in caps { c.layoutIfNeeded(); XCTAssertNotNil(c.layer.shadowPath, "a key shadow without a path is re-rendered offscreen every frame") }
    }
}
