import XCTest
@testable import TuiGoAI

final class FixNowManagerTests: XCTestCase {
    func testSentenceWindowShortTextReturnsWhole() {
        let text = "Toi dang lam viec. Ban co khong?"
        XCTAssertEqual(FixNowManager.sentenceWindow(in: text), text)
    }

    func testSentenceWindowCutsToCompleteSentences() {
        let s1 = String(repeating: "a", count: 700) + ". "
        let s2 = String(repeating: "b", count: 700) + ". "
        let s3 = String(repeating: "c", count: 700) + ". "
        let text = s1 + s2 + s3 // 2106 chars, window cap 2000 cuts into s2
        let window = FixNowManager.sentenceWindow(in: text)
        XCTAssertFalse(window.hasPrefix("b")) // s2 must not be half-included
        XCTAssertTrue(window.hasPrefix("cccc")) // window starts at the last full sentence
        XCTAssertEqual(window, s3.trimmingCharacters(in: .whitespaces))
    }

    func testSentenceWindowEmptyReturnsEmpty() {
        XCTAssertEqual(FixNowManager.sentenceWindow(in: "   "), "")
    }

    func testFixUserPromptContainsText() {
        let prompt = FixNowManager.buildFixUserPrompt("Toi dang hop.")
        XCTAssertTrue(prompt.contains("Toi dang hop."))
        XCTAssertTrue(prompt.contains("Sửa lỗi chính tả"))
    }

    func testFixSystemPromptMentionsConstraints() {
        XCTAssertTrue(FixNowManager.fixSystemPrompt.contains("Giữ nguyên"))
        XCTAssertTrue(FixNowManager.fixSystemPrompt.contains("Không giải thích"))
    }

    func testTapKeyOptionsCoverLeftAndRightVariants() {
        let keyCodes = FixNowManager.tapKeyOptions.map { $0.keyCode }
        XCTAssertTrue(keyCodes.contains(54)) // Right Command
        XCTAssertTrue(keyCodes.contains(55)) // Left Command
        XCTAssertEqual(Set(keyCodes).count, keyCodes.count, "options must be unique")
    }

    func testModifierMaskMapping() {
        XCTAssertEqual(FixNowDoubleTapTracker.modifierMask(for: 54), .maskCommand)
        XCTAssertEqual(FixNowDoubleTapTracker.modifierMask(for: 61), .maskAlternate)
        XCTAssertEqual(FixNowDoubleTapTracker.modifierMask(for: 59), .maskControl)
        XCTAssertNil(FixNowDoubleTapTracker.modifierMask(for: 0))
    }

    func testLooksLikeCorrectedProseRejectsMetaAnswer() {
        let original = "Toi dang lam viec o cong ty moi"
        XCTAssertFalse(FixNowManager.looksLikeCorrectedProse(
            "Không có lỗi chính tả, ngữ pháp, hoặc dấu câu cần sửa trong đoạn văn bản này.",
            original: original
        ))
    }

    func testLooksLikeCorrectedProseAcceptsRealEdit() {
        let original = "Toi dang lam viec o cong ty moi"
        let corrected = "Tôi đang làm việc ở công ty mới"
        XCTAssertTrue(FixNowManager.looksLikeCorrectedProse(corrected, original: original))
    }

    func testLooksLikeCorrectedProseRejectsHallucination() {
        let original = "Toi dang lam viec o cong ty moi"
        XCTAssertFalse(FixNowManager.looksLikeCorrectedProse(
            "The weather in Da Lat is quite nice today for traveling",
            original: original
        ))
    }

    func testWindowCharactersDefaultIsConfigurable() {
        XCTAssertEqual(FixNowManager.windowCharacters >= 300, true)
    }
}
