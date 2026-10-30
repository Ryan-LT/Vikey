import XCTest
import UIKit

/// Next words (the table, Apple Intelligence on top), proofread with a preview, other words for one word.
/// The model is stubbed: these test the keyboard's flow, not Apple's answers.
final class AIAssistFlowTests: XCTestCase {
    private let sender = KeyboardView()

    override func tearDown() { AIAssist.stub = nil; super.tearDown() }

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
    private func type(_ s: String, _ vc: KeyboardViewController) {
        for ch in s { vc.keyboard(sender, didTap: ch == " " ? .space : .char(String(ch).lowercased())) }
    }
    /// Lets the queued strip update and the model's (stubbed) answer land.
    private func settle(_ until: () -> Bool = { false }, timeout: TimeInterval = 1.5) {
        let end = Date().addingTimeInterval(timeout)
        repeat { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) } while !until() && Date() < end
    }
    private func strip(_ vc: KeyboardViewController) -> [Suggestion] { vc.keyboardViewForTests.suggestions }
    private func select(_ p: CursorProxy, _ vc: KeyboardViewController, _ part: String) {
        let r = p.text.range(of: part)!
        p.cursor = p.text.distance(from: p.text.startIndex, to: r.lowerBound); p.selection = part.count
        vc.selectionDidChange(nil)
    }

    // the table
    func testTableVietnameseAndEnglish() {
        XCTAssertEqual(NextWords.shared.predict(before: "cảm ơn ").first, "bạn")
        XCTAssertTrue(NextWords.shared.predict(before: "thank you ").contains("for"))
        XCTAssertTrue(NextWords.shared.predict(before: "cảm ơn").isEmpty, "only after a space")
    }

    func testNextWordsAfterASpaceAndPick() {
        let (vc, p) = make(1)
        type("camr own ", vc)
        settle { self.strip(vc).first?.kind == .next }
        XCTAssertEqual(strip(vc).first?.text, "bạn")
        XCTAssertTrue(strip(vc).allSatisfy { $0.kind == .next })
        vc.keyboard(sender, pickSuggestion: 0)
        XCTAssertEqual(p.text, "Cảm ơn bạn ")
        settle { self.strip(vc).first?.kind == .next }
        XCTAssertFalse(strip(vc).isEmpty, "and the next ones")
    }

    func testAIAddsAWordTheTableDoesntHave() {
        AIAssist.stub = .init(next: { _ in ["zzword"] })
        let (vc, _) = make(1)
        type("camr own ", vc)
        settle({ self.strip(vc).contains { $0.text == "zzword" } }, timeout: 2)
        XCTAssertEqual(strip(vc).count, 3)
        XCTAssertEqual(strip(vc).first?.text, "bạn", "the table's best stays first")
        XCTAssertEqual(strip(vc).last?.text, "zzword")
    }

    // proofread: preview, then apply or cancel
    func testProofreadPreviewThenApplyThenUndo() {
        AIAssist.stub = .init(proofread: { _ in "I have gone to the store." })
        let (vc, p) = make()
        p.text = "i has went to the store"; p.cursor = 0
        select(p, vc, p.text)
        settle { self.strip(vc).first?.kind == .proofread }
        XCTAssertEqual(strip(vc).map(\.kind), [.proofread])
        vc.keyboard(sender, pickSuggestion: 0)
        settle { vc.proofreadPanelForTests != nil }
        XCTAssertNotNil(vc.proofreadPanelForTests, "a preview first")
        XCTAssertEqual(p.text, "i has went to the store", "nothing changes before Apply")
        vc.proofreadPanelForTests?.onApply?()
        XCTAssertEqual(p.text, "I have gone to the store.")
        XCTAssertNil(vc.proofreadPanelForTests)
        settle { self.strip(vc).first?.kind == .undo }
        XCTAssertEqual(strip(vc).map(\.kind), [.undo])
        vc.keyboard(sender, pickSuggestion: 0)
        XCTAssertEqual(p.text, "i has went to the store")
    }

    func testProofreadCancelKeepsTheText() {
        AIAssist.stub = .init(proofread: { _ in "Fixed." })
        let (vc, p) = make()
        p.text = "fixd it"; p.cursor = 0
        select(p, vc, p.text)
        settle { self.strip(vc).first?.kind == .proofread }
        vc.keyboard(sender, pickSuggestion: 0)
        settle { vc.proofreadPanelForTests != nil }
        vc.proofreadPanelForTests?.onCancel?()
        XCTAssertNil(vc.proofreadPanelForTests)
        XCTAssertEqual(p.text, "fixd it")
    }

    func testProofreadWithNoMistakesSaysSo() {
        AIAssist.stub = .init(proofread: { $0 })
        let (vc, p) = make()
        p.text = "All good here."; p.cursor = 0
        select(p, vc, p.text)
        settle { self.strip(vc).first?.kind == .proofread }
        vc.keyboard(sender, pickSuggestion: 0)
        settle { self.strip(vc).first?.kind == .busy && self.strip(vc).first?.text != String(localized: "Đang sửa…") }
        XCTAssertNil(vc.proofreadPanelForTests)
        XCTAssertEqual(strip(vc).first?.text, String(localized: "Không có lỗi ✓"))
    }

    func testApplyNeedsTheSameSelection() {
        AIAssist.stub = .init(proofread: { _ in "Two words." })
        let (vc, p) = make()
        p.text = "two wrds"; p.cursor = 0
        select(p, vc, p.text)
        settle { self.strip(vc).first?.kind == .proofread }
        vc.keyboard(sender, pickSuggestion: 0)
        settle { vc.proofreadPanelForTests != nil }
        p.selection = 0; p.cursor = 3            // the user moved away meanwhile
        vc.proofreadPanelForTests?.onApply?()
        XCTAssertEqual(p.text, "two wrds", "never replaces the wrong text")
    }

    // one word selected: other words
    func testOtherWordsForOneWord() {
        AIAssist.stub = .init(alternatives: { _ in ["large", "huge", "giant"] })
        let (vc, p) = make()
        p.text = "a big house"; p.cursor = 0
        select(p, vc, "big")
        settle { self.strip(vc).first?.kind == .alternative }
        XCTAssertEqual(strip(vc).map(\.text), ["large", "huge", "giant"])
        vc.keyboard(sender, pickSuggestion: 1)
        XCTAssertEqual(p.text, "a huge house")
    }

    func testNoSelectionFeaturesWithoutAppleIntelligence() {
        guard !AIAssist.available else { return }   // a simulator/phone with the model: nothing to check here
        let (vc, p) = make()
        p.text = "some words here"; p.cursor = 0
        select(p, vc, p.text)
        settle()
        XCTAssertFalse(strip(vc).contains { $0.kind == .proofread || $0.kind == .busy })
    }
}
