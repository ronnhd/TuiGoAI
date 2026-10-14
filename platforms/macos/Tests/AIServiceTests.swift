import XCTest
@testable import TuiGoAI

final class AIServiceTests: XCTestCase {
    func testDefaultConfig() {
        let config = AIConfig.default
        XCTAssertTrue(config.isEnabled)
        XCTAssertEqual(config.providerType, .localOllama)
        XCTAssertEqual(config.baseURL, "http://localhost:11434/v1")
        XCTAssertEqual(config.model, "qwen2.5:3b")
        XCTAssertEqual(config.temperature, 0.1)
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

    func testCleanCompletionPreservesVietnameseReduplication() {
        // Từ láy toàn phần bên trong phần gợi ý ("luôn luôn", "đều đều")
        let cleaned1 = AIService.cleanCompletion(
            "luôn luôn đồng hành cùng khách hàng",
            prefix: "Chúng tôi ",
            suffix: ""
        )
        XCTAssertEqual(cleaned1, "luôn luôn đồng hành cùng khách hàng")

        // Từ láy toàn phần nối qua ranh giới con trỏ ("cứ từ " + "từ thôi nhé")
        let cleaned2 = AIService.cleanCompletion(
            "từ thôi nhé anh ơi",
            prefix: "Anh cứ từ ",
            suffix: ""
        )
        XCTAssertEqual(cleaned2, "từ thôi nhé anh ơi")

        // Nhưng nếu lặp quá 2 lần ("luôn luôn luôn") thì vẫn cắt về tối đa 2 lần
        let cleaned3 = AIService.cleanCompletion(
            "luôn luôn luôn sẵn sàng hỗ trợ",
            prefix: "Chúng tôi ",
            suffix: ""
        )
        XCTAssertEqual(cleaned3, "luôn luôn sẵn sàng hỗ trợ")
    }

    func testCleanCompletionCollapsesCompoundNGramLoops() {
        // Từ ghép 2 âm tiết bị lặp ("kế hoạch kế hoạch")
        let cleaned2Gram = AIService.cleanCompletion(
            "kế hoạch kế hoạch triển khai tuần tới",
            prefix: "Em gửi anh bản ",
            suffix: ""
        )
        XCTAssertEqual(cleaned2Gram, "kế hoạch triển khai tuần tới")

        // Cụm 3 âm tiết bị lặp ("cho dự án cho dự án")
        let cleaned3Gram = AIService.cleanCompletion(
            "cho dự án cho dự án mới của team",
            prefix: "Mình chuẩn bị tài liệu ",
            suffix: ""
        )
        XCTAssertEqual(cleaned3Gram, "cho dự án mới của team")
    }

    func testCleanCompletionRejectsConversationalReplyHallucination() {
        let reply = AIService.cleanCompletion(
            "Dạ vâng, anh cứ hỏi đi ạ",
            prefix: "Anh ơi cho em hỏi ",
            suffix: ""
        )
        XCTAssertEqual(reply, "")
    }

    func testCleanCompletionNormalizesDecomposedUnicodeNFD() {
        // Chuỗi NFD có dấu rời vẫn phải khớp và chuẩn hóa về NFC
        let decomposedPrefix = "Mình gửi bạn bản đề xuất ".decomposedStringWithCanonicalMapping
        let decomposedRaw = "Mình gửi bạn bản đề xuất kế hoạch mới".decomposedStringWithCanonicalMapping
        let cleaned = AIService.cleanCompletion(decomposedRaw, prefix: decomposedPrefix, suffix: "")
        XCTAssertEqual(cleaned, "kế hoạch mới")
    }

    func testUnfinishedVietnameseOnsetCompletion() {
        // Phụ âm đầu treo được nhận diện để chặn gợi ý sớm khi đang gõ
        XCTAssertTrue(CaretBoundary.hasUnfinishedTrailingSyllable("Em gửi bản chương tr"))
        XCTAssertTrue(CaretBoundary.hasUnfinishedTrailingSyllable("Đang nghiên c"))
        XCTAssertFalse(CaretBoundary.hasUnfinishedTrailingSyllable("Em gửi bản chương trình"))
        XCTAssertFalse(CaretBoundary.hasUnfinishedTrailingSyllable("Em gửi bản chương tr "))

        // Nếu model trả về cả từ hoàn chỉnh ("trình đào tạo mới") khi con trỏ ở "chương tr",
        // stripOverlappingPrefix + CaretBoundary.reconcile nối mượt không bị chèn dấu cách thừa
        let cleaned = AIService.cleanCompletion(
            "trình đào tạo mới cho nhân sự",
            prefix: "Em gửi bản chương tr",
            suffix: ""
        )
        XCTAssertEqual(cleaned, "ình đào tạo mới cho nhân sự")
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

    func testAutocompletePromptUsesChatMLAndPrefill() {
        let prompt = AIService.buildAutocompletePrompt(prefix: "mai mình")
        XCTAssertTrue(prompt.contains("<|im_start|>system"))
        XCTAssertTrue(prompt.contains("<|im_start|>assistant\nmai mình"))
        XCTAssertTrue(prompt.hasSuffix("mai mình"))
    }

    func testAutocompletePromptIncludesChatHistory() {
        let prompt = AIService.buildAutocompletePrompt(
            prefix: "còn họp lúc",
            recentMessages: ["Chào bạn, hôm nay có họp không?", "Tôi vừa gửi file qua email"],
            appName: "Telegram"
        )
        // Ensure app name does not leak into the prompt to prevent LLM topic bias
        XCTAssertFalse(prompt.contains("Telegram"))
        XCTAssertFalse(prompt.contains("Ứng dụng:"))
        XCTAssertTrue(prompt.contains("Các câu người dùng vừa viết gần đây:"))
        XCTAssertTrue(prompt.contains("- Chào bạn, hôm nay có họp không?"))
        XCTAssertTrue(prompt.contains("- Tôi vừa gửi file qua email"))
        XCTAssertTrue(prompt.contains("<|im_start|>assistant\ncòn họp lúc"))
    }

    func testAutocompletePromptIncludesClipboardContext() {
        let prompt = AIService.buildAutocompletePrompt(
            prefix: "em gửi anh link",
            clipboardText: "https://meet.google.com/xyz"
        )
        XCTAssertTrue(prompt.contains("Nội dung vừa sao chép (tham khảo nếu liên quan):"))
        XCTAssertTrue(prompt.contains("https://meet.google.com/xyz"))
        XCTAssertTrue(prompt.contains("<|im_start|>assistant\nem gửi anh link"))
    }

    func testAutocompletePromptIncludesSuffixFIM() {
        let prompt = AIService.buildAutocompletePrompt(
            prefix: "Em đã gửi báo cáo",
            suffix: "cho sếp rồi nhé ạ."
        )
        XCTAssertTrue(prompt.contains("Đoạn văn tiếp theo ngay sau con trỏ (tránh lặp lại):"))
        XCTAssertTrue(prompt.contains("cho sếp rồi nhé ạ."))
        XCTAssertTrue(prompt.contains("Viết tiếp phần nối ở giữa câu bằng tiếng Việt:"))
        XCTAssertTrue(prompt.contains("<|im_start|>assistant\nEm đã gửi báo cáo"))
    }

    func testSmartSuppression() {
        XCTAssertTrue(GhostTextManager.shouldSuppress(prefixText: "ab"))
        XCTAssertTrue(GhostTextManager.shouldSuppress(prefixText: "Xin chào bạn."))
        XCTAssertTrue(GhostTextManager.shouldSuppress(prefixText: "Hôm nay vui quá!"))
        XCTAssertTrue(GhostTextManager.shouldSuppress(prefixText: "https://google.com/"))
        XCTAssertTrue(GhostTextManager.shouldSuppress(prefixText: "0912345678"))
        XCTAssertTrue(GhostTextManager.shouldSuppress(prefixText: "func myMethod()"))
        XCTAssertTrue(GhostTextManager.shouldSuppress(prefixText: "Em gửi bản chương tr"))
        XCTAssertFalse(GhostTextManager.shouldSuppress(prefixText: "mai mình "))
        XCTAssertFalse(GhostTextManager.shouldSuppress(prefixText: "chiều nay họp "))
    }

    func testAcceptNextWordSplitting() {
        let (head, rest) = NextWordSplitter.split("sẽ đi mua sắm")
        XCTAssertEqual(head, "sẽ")
        XCTAssertEqual(rest, " đi mua sắm")

        let (head2, rest2) = NextWordSplitter.split(rest)
        XCTAssertEqual(head2, " đi")
        XCTAssertEqual(rest2, " mua sắm")
    }

    func testCleanCompletionRejectsForeignScripts() {
        let cleanedChinese = AIService.cleanCompletion("một mùa新春快乐", prefix: "chúc bạn ", suffix: "")
        XCTAssertEqual(cleanedChinese, "")

        let cleanedKorean = AIService.cleanCompletion("파일을 보냅니다", prefix: "tôi gửi ", suffix: "")
        XCTAssertEqual(cleanedKorean, "")
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
