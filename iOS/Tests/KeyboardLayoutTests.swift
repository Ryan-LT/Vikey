import XCTest
import UIKit

/// Field-specific layouts like the system keyboard (email, URL, web search, number pads), rendered for a look.
final class KeyboardLayoutTests: XCTestCase {
    private func render(_ type: UIKeyboardType, layer: KeyboardView.Layer = .letters, _ name: String) -> KeyboardView {
        let kb = KeyboardView(frame: CGRect(x: 0, y: 0, width: 402, height: KeyboardView.keyboardHeight(compactHeight: false)))
        kb.fieldType = type
        kb.layer_ = layer
        kb.backgroundColor = UIColor(red: 0.82, green: 0.83, blue: 0.86, alpha: 1)
        kb.layoutIfNeeded()
        let img = UIGraphicsImageRenderer(bounds: kb.bounds).image { ctx in kb.layer.render(in: ctx.cgContext) }
        try? FileManager.default.createDirectory(atPath: "/tmp/claude-501/layouts", withIntermediateDirectories: true)
        try? img.pngData()?.write(to: URL(fileURLWithPath: "/tmp/claude-501/layouts/\(name).png"))
        return kb
    }
    private func titles(_ kb: KeyboardView) -> [String] { kb.subviews.compactMap { ($0 as? KeyCap)?.label.text } }

    func testEmailHasAtAndDot() { let t = titles(render(.emailAddress, "email")); XCTAssertTrue(t.contains("@") && t.contains(".")) }
    func testURLHasSlashAndDotCom() { let t = titles(render(.URL, "url")); XCTAssertTrue(t.contains("/") && t.contains(".com")) }
    func testWebSearchHasDot() { XCTAssertTrue(titles(render(.webSearch, "websearch")).contains(".")) }
    func testNumberPad() {
        let kb = render(.numberPad, layer: .numpad, "numberpad")
        XCTAssertEqual(Set(titles(kb).filter { !$0.isEmpty }), Set("1234567890".map(String.init)))
    }
    func testDecimalAndPhonePads() {
        XCTAssertTrue(titles(render(.decimalPad, layer: .numpad, "decimalpad")).contains(Locale.current.decimalSeparator ?? "."))
        XCTAssertTrue(titles(render(.phonePad, layer: .numpad, "phonepad")).contains("+"))
    }
    func testDefaultUnchanged() { let t = titles(render(.default, "default")); XCTAssertFalse(t.contains("@")) }
}
