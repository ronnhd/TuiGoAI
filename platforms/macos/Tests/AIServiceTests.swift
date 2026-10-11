import XCTest
@testable import GoNhanh

final class AIServiceTests: XCTestCase {
    func testDefaultConfig() {
        let config = AIConfig.default
        XCTAssertTrue(config.isEnabled)
        XCTAssertEqual(config.providerType, .localOllama)
        XCTAssertEqual(config.baseURL, "http://localhost:11434/v1")
        XCTAssertEqual(config.model, "qwen2.5:latest")
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

    func testToneInstructions() {
        XCTAssertFalse(AIRewriteTone.formal.promptInstruction.isEmpty)
        XCTAssertFalse(AIRewriteTone.casual.promptInstruction.isEmpty)
        XCTAssertFalse(AIRewriteTone.concise.promptInstruction.isEmpty)
        XCTAssertFalse(AIRewriteTone.elaborate.promptInstruction.isEmpty)
    }
}
