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

/// Design proposals: the VI/EN key in the top-left corner of the suggestion strip (Tony). Renders only.
final class LanguageKeyProposalTests: XCTestCase {
    func testRenderProposals() {
        KeyboardView.barOn = true
        for dark in [false, true] {
            for style in 0...3 {
                KeyboardView.langStyle = style
                let kb = KeyboardView(frame: CGRect(x: 0, y: 0, width: 402, height: KeyboardView.keyboardHeight(compactHeight: false)))
                kb.dark = dark
                kb.languageShort = "VI"; kb.languageTitle = "Tiếng Việt"
                kb.backgroundColor = dark ? UIColor(white: 0.17, alpha: 1) : UIColor(red: 0.82, green: 0.83, blue: 0.86, alpha: 1)
                kb.suggestions = [Suggestion(text: "tooi", quoted: true), Suggestion(text: "tôi", highlighted: true), Suggestion(text: "tối")]
                kb.layoutIfNeeded()
                let img = UIGraphicsImageRenderer(bounds: kb.bounds).image { ctx in kb.layer.render(in: ctx.cgContext) }
                try? img.pngData()?.write(to: URL(fileURLWithPath: "/tmp/claude-501/layouts/lang_\(style)_\(dark ? "dark" : "light").png"))
            }
        }
        KeyboardView.langStyle = 1
    }

    func testPillStates() {
        KeyboardView.barOn = true; KeyboardView.langStyle = 1
        for (lang, title) in [("VI", "Tiếng Việt"), ("EN", "English")] {
            let kb = KeyboardView(frame: CGRect(x: 0, y: 0, width: 402, height: KeyboardView.keyboardHeight(compactHeight: false)))
            kb.languageShort = lang; kb.languageTitle = title
            kb.backgroundColor = UIColor(red: 0.82, green: 0.83, blue: 0.86, alpha: 1)
            kb.layoutIfNeeded()
            let img = UIGraphicsImageRenderer(bounds: kb.bounds).image { ctx in kb.layer.render(in: ctx.cgContext) }
            try? img.pngData()?.write(to: URL(fileURLWithPath: "/tmp/claude-501/layouts/pill_\(lang).png"))
            let caps = kb.subviews.compactMap { $0 as? KeyCap }
            XCTAssertTrue(caps.contains { $0.frame.minY < 40 && ($0.label.attributedText?.string == lang) }, "the pill sits in the strip's corner")
        }
        KeyboardView.barOn = false
        let kb = KeyboardView(frame: CGRect(x: 0, y: 0, width: 402, height: KeyboardView.keyboardHeight(compactHeight: false)))
        kb.layoutIfNeeded()
        XCTAssertTrue(kb.subviews.compactMap { $0 as? KeyCap }.contains { $0.label.text == "VI" && $0.frame.minY > 150 }, "no strip: back in the bottom row")
    }
}

