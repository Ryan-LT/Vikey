import XCTest
import UIKit

/// Behaviors copied from the iOS system keyboard (Tony: "learn all of these from the default keyboard").
final class KeyboardSystemParityTests: XCTestCase {
    private let sender = KeyboardView()

    private func make(_ lang: Int = 0) -> (KeyboardViewController, CursorProxy) {
        let vc = KeyboardViewController()
        let p = CursorProxy()
        vc.proxy = p
        vc.loadViewIfNeeded()
        vc.view.frame = CGRect(x: 0, y: 0, width: 402, height: 300)
        vc.view.layoutIfNeeded()
        vc.viewWillAppear(false)
        vc.setLanguageForTests(lang)
        return (vc, p)
    }
    /// Types like a person: letters go through the keyboard's own shift state (auto-capitals).
    private func type(_ s: String, _ vc: KeyboardViewController) {
        for ch in s {
            switch ch {
            case " ": vc.keyboard(sender, didTap: .space)
            case "\n": vc.keyboard(sender, didTap: .returnKey)
            default: vc.keyboard(sender, didTap: .char(String(ch).lowercased()))
            }
        }
    }

    // contractions
    func testLetsWithCapitalBecomesLetUs() { let (vc, p) = make(); type("lets go ", vc); XCTAssertEqual(p.text, "Let's go ") }
    func testLetsMidSentenceStaysAVerb() { let (vc, p) = make(); type("she lets me ", vc); XCTAssertEqual(p.text, "She lets me ") }
    func testWont() { let (vc, p) = make(); type("i wont go ", vc); XCTAssertEqual(p.text, "I won't go ") }

    // auto-capitals
    func testCapitalAtStartAndAfterSentences() {
        let (vc, p) = make()
        type("hi. there? yes! ok\nnew line ", vc)
        XCTAssertEqual(p.text, "Hi. There? Yes! Ok\nNew line ")
    }
    func testCapitalAfterClosingQuoteOrBracket() {
        let (vc, p) = make()
        type("he said \"go.\" then (wow.) next ", vc)
        XCTAssertTrue(p.text.hasSuffix(") Next "), p.text)
        XCTAssertTrue(p.text.contains("\" Then") || p.text.contains("” Then"), p.text)
    }
    func testNoCapitalAfterComma() { let (vc, p) = make(); type("hi, there ", vc); XCTAssertEqual(p.text, "Hi, there ") }

    // punctuation typed after a space moves back onto the word
    func testPeriodSnapsBack() { let (vc, p) = make(); type("this . ", vc); XCTAssertEqual(p.text, "This. ") }
    func testCommaSnapsBack() { let (vc, p) = make(); type("this , that ", vc); XCTAssertEqual(p.text, "This, that ") }
    func testQuestionAndExclamation() { let (vc, p) = make(); type("really ? yes ! ", vc); XCTAssertEqual(p.text, "Really? Yes! ") }
    func testClosingQuoteSnapsBack() {
        let (vc, p) = make()
        type("say \"hello \" ok ", vc)
        XCTAssertEqual(p.text, "Say \"hello\" ok ")
    }
    func testOpeningQuoteStays() { let (vc, p) = make(); type("say \"hi", vc); XCTAssertEqual(p.text, "Say \"hi") }
    func testClosingBracketSnapsBack() { let (vc, p) = make(); type("(this ) ok ", vc); XCTAssertEqual(p.text, "(this) ok ") }
    func testVietnameseToo() {
        let (vc, p) = make(1)
        type("xin chaof . ", vc)
        XCTAssertEqual(p.text, "Xin chào. ")
    }

    func testSmartDash() { let (vc, p) = make(); type("a--b ", vc); XCTAssertEqual(p.text, "A—b ") }
    func testTextReplacement() {
        let (vc, p) = make()
        vc.setTextReplacementsForTests(["omw": "On my way!"])
        type("omw ", vc)
        XCTAssertEqual(p.text, "On my way! ")
        vc.keyboard(sender, didTap: .backspace)       // like an auto-correct: delete puts the keys back
        XCTAssertEqual(p.text, "Omw")   // same as an auto-correct undo
    }

    func testReturnOn123StartsTheNextLineWithACapital() {
        let (vc, p) = make()
        type("hi", vc)
        vc.keyboard(sender, didTap: .layer(.numbers))
        vc.keyboard(sender, didTap: .char("1"))
        vc.keyboard(sender, didTap: .returnKey)
        type("next", vc)
        XCTAssertEqual(p.text, "Hi1\nNext")
    }
}
