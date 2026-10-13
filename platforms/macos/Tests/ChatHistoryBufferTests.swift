import XCTest
@testable import TuiGoAI

final class ChatHistoryBufferTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ChatHistoryBuffer.shared.clearAll()
    }

    func testRecordAndRetrieveHistory() {
        let bundle = "ru.keepcoder.Telegram"
        ChatHistoryBuffer.shared.record(text: "Chào bạn, hôm nay có họp không?", bundleId: bundle)
        ChatHistoryBuffer.shared.record(text: "Tôi vừa gửi file qua email", bundleId: bundle)

        let history = ChatHistoryBuffer.shared.recentHistory(for: bundle)
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0], "Chào bạn, hôm nay có họp không?")
        XCTAssertEqual(history[1], "Tôi vừa gửi file qua email")
    }

    func testDeduplicationConsecutive() {
        let bundle = "com.vng.zalo"
        ChatHistoryBuffer.shared.record(text: "ok bạn", bundleId: bundle)
        ChatHistoryBuffer.shared.record(text: "ok bạn", bundleId: bundle)

        let history = ChatHistoryBuffer.shared.recentHistory(for: bundle)
        XCTAssertEqual(history.count, 1)
    }

    func testMaxEntriesBounded() {
        let bundle = "com.tinyspeck.slackmacgap"
        ChatHistoryBuffer.shared.record(text: "tin 1", bundleId: bundle)
        ChatHistoryBuffer.shared.record(text: "tin 2", bundleId: bundle)
        ChatHistoryBuffer.shared.record(text: "tin 3", bundleId: bundle)
        ChatHistoryBuffer.shared.record(text: "tin 4", bundleId: bundle)
        ChatHistoryBuffer.shared.record(text: "tin 5", bundleId: bundle)

        let history = ChatHistoryBuffer.shared.recentHistory(for: bundle)
        XCTAssertEqual(history.count, 4)
        XCTAssertEqual(history.last, "tin 5")
    }

    func testIsChatAppDetection() {
        XCTAssertTrue(ChatHistoryBuffer.isChatApp("ru.keepcoder.Telegram"))
        XCTAssertTrue(ChatHistoryBuffer.isChatApp("com.vng.zalo"))
        XCTAssertTrue(ChatHistoryBuffer.isChatApp("com.tinyspeck.slackmacgap"))
        XCTAssertTrue(ChatHistoryBuffer.isChatApp("com.hnc.Discord"))
        XCTAssertTrue(ChatHistoryBuffer.isChatApp("com.apple.MobileSMS"))
        XCTAssertFalse(ChatHistoryBuffer.isChatApp("com.apple.TextEdit"))
        XCTAssertFalse(ChatHistoryBuffer.isChatApp("com.microsoft.VSCode"))
    }
}
