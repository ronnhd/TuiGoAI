import AppKit
import Foundation

// MARK: - Chat History Buffer (Ephemeral My-Chat Memory)

/// Lưu tạm thời các câu gần nhất mà chính người dùng đã gửi trong từng ứng dụng chat
/// Chỉ lưu trên RAM, tự động hết hạn sau 5 phút (TTL) hoặc khi đóng app.
/// Không bao giờ ghi ra ổ đĩa hay gửi ra ngoài.
public final class ChatHistoryBuffer: @unchecked Sendable {
    public static let shared = ChatHistoryBuffer()

    private let lock = NSLock()
    private var historyByBundle: [String: [(text: String, timestamp: Date)]] = [:]
    private let maxEntries = 4
    private let ttl: TimeInterval = 300 // 5 phút

    private init() {}

    /// Ghi nhận 1 câu vừa được gửi đi (bấm Return/Enter không kèm phím Shift/Option)
    public func record(text: String, bundleId: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 2, cleaned.count <= 1000 else { return }

        lock.lock()
        defer { lock.unlock() }

        pruneExpiredLocked()

        var list = historyByBundle[bundleId] ?? []
        // Tránh trùng lặp câu liền kề
        if list.last?.text != cleaned {
            list.append((cleaned, Date()))
            if list.count > maxEntries {
                list.removeFirst(list.count - maxEntries)
            }
            historyByBundle[bundleId] = list
        }
    }

    /// Lấy danh sách các câu người dùng vừa gõ gần nhất trong bundleId này
    public func recentHistory(for bundleId: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }

        pruneExpiredLocked()
        if let specific = historyByBundle[bundleId], !specific.isEmpty {
            return specific.map(\.text)
        }
        // Fallback: Nếu bundle hiện tại chưa có câu nào, lấy 2 câu gần nhất trên toàn hệ thống để giữ văn phong xưng hô
        let all = historyByBundle.values.flatMap { $0 }
            .sorted { $0.timestamp < $1.timestamp }
            .suffix(2)
        return all.map(\.text)
    }

    /// Xóa lịch sử khi người dùng muốn xóa bộ đệm
    public func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        historyByBundle.removeAll()
    }

    private func pruneExpiredLocked() {
        let now = Date()
        for (bundle, entries) in historyByBundle {
            let active = entries.filter { now.timeIntervalSince($0.timestamp) < ttl }
            if active.isEmpty {
                historyByBundle.removeValue(forKey: bundle)
            } else {
                historyByBundle[bundle] = active
            }
        }
    }

    /// Kiểm tra ứng dụng có phải là app chat / nhắn tin phổ biến
    public static func isChatApp(_ bundleId: String) -> Bool {
        let lower = bundleId.lowercased()
        return lower.contains("telegram") ||
               lower.contains("zalo") ||
               lower.contains("slack") ||
               lower.contains("discord") ||
               lower.contains("mobilesms") ||
               lower.contains("messenger") ||
               lower.contains("whatsapp") ||
               lower.contains("viber") ||
               lower.contains("skype") ||
               lower.contains("teams")
    }
}
