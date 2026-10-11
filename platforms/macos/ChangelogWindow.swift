import AppKit
import SwiftUI

@MainActor
final class ChangelogWindowController {
    static let shared = ChangelogWindowController()

    private var window: NSWindow?
    private let seenKey = "tuigoai.changelog.last-seen-version"

    func showIfNeeded() {
        let version = AppMetadata.version
        guard UserDefaults.standard.string(forKey: seenKey) != version else { return }
        UserDefaults.standard.set(version, forKey: seenKey)

        let view = ChangelogView(version: version) { [weak self] in
            self?.window?.close()
        }
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Có gì mới trong TuiGoAI"
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

private struct ChangelogView: View {
    let version: String
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("TuiGoAI Beta")
                .font(.system(size: 26, weight: .semibold))
            Text("Phiên bản \(version)")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                changelogRow("wand.and.stars", "AI Copilot local", "Gợi ý phần tiếp theo khi đang gõ, chạy qua Ollama.")
                changelogRow("arrow.down.circle", "Model do người dùng chọn", "Xem model phù hợp, tự tải, chọn hoặc xóa model.")
                changelogRow("keyboard", "Phím tắt có thể ghi lại", "Tự custom phím nhận gợi ý và bật/tắt AI.")
                changelogRow("lock.shield", "Giữ đường gõ cơ bản độc lập", "AI lỗi hoặc tắt thì bộ gõ tiếng Việt vẫn hoạt động.")
            }
            Spacer()
            HStack {
                Spacer()
                Button("Đã hiểu") { close() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func changelogRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundColor(.secondary)
            }
        }
    }
}
