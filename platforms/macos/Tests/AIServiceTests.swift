import XCTest
@testable import TuiGoAI

final class AIServiceTests: XCTestCase {
    func testDefaultConfig() {
        let config = AIConfig.default
        XCTAssertTrue(config.isEnabled)
        XCTAssertEqual(config.providerType, .localOllama)
        XCTAssertEqual(config.baseURL, "http://localhost:11434/v1")
        XCTAssertEqual(config.model, "qwen2.5:3b")
    }

    func testConfigPersistence() {
        let service = AIService.shared
        var config = service.loadConfig()
        config.temperature = 0.5
        config.model = "test-model"
        service.saveConfig(config)

        let reloaded = service.loadConfig()
        XCTAssertEqual(reloaded.model, "test-model")
        XCTAssertEqual(reloaded.temperature, 0.5)

        // Restore default
        service.saveConfig(.default)
    }

    func testCleanCompletionStripsEchoAndLimitsWords() {
        let cleaned = AIService.cleanCompletion(
            "Mình gửi bạn bản đề xuất proposal cho chiến dịch PR tại Việt Nam ngay hôm nay",
            prefix: "Mình gửi bạn bản đề xuất ",
            suffix: ""
        )
        XCTAssertEqual(cleaned, "proposal cho chiến dịch PR tại Việt Nam")
    }

    func testCleanCompletionRejectsContinuationThatRepeatsCursorSuffix() {
        let cleaned = AIService.cleanCompletion(
            "cho chiến dịch PR.",
            prefix: "Mình gửi bạn bản đề xuất ",
            suffix: " cho chiến dịch PR."
        )
        XCTAssertEqual(cleaned, "")
    }

    func testCleanCompletionCollapsesRepeatedTokens() {
        let cleaned = AIService.cleanCompletion(
            "proposal proposal mới kickoff kickoff hôm nay",
            prefix: "Mình gửi bạn bản đề xuất ",
            suffix: ""
        )
        XCTAssertEqual(cleaned, "proposal mới kickoff hôm nay")
    }

    func testCleanCompletionWithoutTrailingSpaceAddsLeadingSpace() {
        let cleaned = AIService.cleanCompletion(
            "proposal cho chiến dịch PR tại Việt Nam",
            prefix: "Mình gửi bạn bản đề xuất",
            suffix: ""
        )
        XCTAssertEqual(cleaned, " proposal cho chiến dịch PR tại Việt Nam")
    }

    func testToneInstructions() {
        XCTAssertFalse(AIRewriteTone.formal.promptInstruction.isEmpty)
        XCTAssertFalse(AIRewriteTone.casual.promptInstruction.isEmpty)
        XCTAssertFalse(AIRewriteTone.concise.promptInstruction.isEmpty)
        XCTAssertFalse(AIRewriteTone.elaborate.promptInstruction.isEmpty)
    }

    func testAutocompleteUserPromptKeepsPrefixAsPlainText() {
        let prompt = AIService.buildAutocompleteUserPrompt(prefix: "mai mình")
        XCTAssertTrue(prompt.contains("Đã gõ (không lặp lại):\nmai mình"))
        XCTAssertTrue(prompt.contains("Từ mới tiếp theo:"))
        XCTAssertFalse(prompt.contains("- mai mình"))
    }

    func testAutocompleteUserPromptJoinsChatHistoryWithoutBullets() {
        let prompt = AIService.buildAutocompleteUserPrompt(
            prefix: "còn họp lúc",
            recentMessages: ["Chào bạn, hôm nay có họp không?", "Tôi vừa gửi file qua email"],
            appName: "Telegram"
        )
        XCTAssertTrue(prompt.contains("Ứng dụng: Telegram."))
        XCTAssertTrue(prompt.contains("Các câu tôi vừa gửi:"))
        XCTAssertTrue(prompt.contains("Chào bạn, hôm nay có họp không?\nTôi vừa gửi file qua email"))
        XCTAssertTrue(prompt.contains("Đã gõ (không lặp lại):\ncòn họp lúc"))
        XCTAssertFalse(prompt.contains("- Chào bạn"))
        XCTAssertFalse(prompt.contains("- còn họp lúc"))
    }

    func testCleanCompletionStripsRewrittenPrefix() {
        let cleaned = AIService.cleanCompletion(
            "mai mình đi họp với team",
            prefix: "mai mình đi",
            suffix: ""
        )
        XCTAssertEqual(cleaned, " họp với team")
    }

    func testCleanCompletionStripsPartialWordOverlap() {
        let cleaned = AIService.cleanCompletion(
            "mình gửi proposal",
            prefix: "Mình gửi ",
            suffix: ""
        )
        XCTAssertEqual(cleaned, "proposal")
    }

    // MARK: - AutocompleteCore Tests (KeyType ported)

    func testCaretBoundaryTrimming() {
        XCTAssertEqual(CaretBoundary.trimmingTrailingWhitespace("Xin chào "), "Xin chào")
        XCTAssertEqual(CaretBoundary.trimmingTrailingWhitespace("Xin chào   \n"), "Xin chào")
        XCTAssertEqual(CaretBoundary.trimmingTrailingWhitespace("Xin chào"), "Xin chào")
    }

    func testCaretBoundaryReconciliation() {
        // Model emits space after whitespace: should strip leading space
        XCTAssertEqual(CaretBoundary.reconcile(" bạn", beforeCursor: "Chào "), "bạn")
        // Model emits space after word: keep leading space
        XCTAssertEqual(CaretBoundary.reconcile(" bạn", beforeCursor: "Chào"), " bạn")
        // Strip leading newline artifact
        XCTAssertEqual(CaretBoundary.reconcile("\n\nbạn ơi", beforeCursor: "Chào "), "bạn ơi")
    }

    func testSuffixOverlapGuard() {
        XCTAssertTrue(SuffixOverlapGuard.duplicatesSuffix(
            completion: "chiến dịch PR",
            beforeCursor: "Gửi ",
            afterCursor: "chiến dịch PR sắp tới"
        ))
        XCTAssertFalse(SuffixOverlapGuard.duplicatesSuffix(
            completion: "kế hoạch mới",
            beforeCursor: "Gửi ",
            afterCursor: "chiến dịch PR sắp tới"
        ))
    }

    func testNextWordSplitter() {
        let (head1, rest1) = NextWordSplitter.split("bạn ơi hôm nay")
        XCTAssertEqual(head1, "bạn")
        XCTAssertEqual(rest1, " ơi hôm nay")

        let (head2, rest2) = NextWordSplitter.split(" ơi hôm nay")
        XCTAssertEqual(head2, " ơi")
        XCTAssertEqual(rest2, " hôm nay")

        let (head3, rest3) = NextWordSplitter.split(".")
        XCTAssertEqual(head3, ".")
        XCTAssertEqual(rest3, "")
    }
}
