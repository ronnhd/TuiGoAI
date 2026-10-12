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

    func testToneInstructions() {
        XCTAssertFalse(AIRewriteTone.formal.promptInstruction.isEmpty)
        XCTAssertFalse(AIRewriteTone.casual.promptInstruction.isEmpty)
        XCTAssertFalse(AIRewriteTone.concise.promptInstruction.isEmpty)
        XCTAssertFalse(AIRewriteTone.elaborate.promptInstruction.isEmpty)
    }
}
