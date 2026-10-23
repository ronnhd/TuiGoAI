import AppKit
import ApplicationServices

// MARK: - FixNow: in-place spelling, grammar and punctuation correction
//
// Triggered by a double-tap of the Right Command key. Reads the focused text
// field via Accessibility, takes the last complete sentences before the caret
// (cap 2000 characters, rounded down to a sentence boundary), asks Ollama to
// fix spelling/grammar/punctuation without changing tone or structure, and
// writes the corrected text back in place. RAM-only, no history, no logs.

@MainActor
public final class FixNowManager: ObservableObject {
    public static let shared = FixNowManager()

    @Published public private(set) var isFixing: Bool = false
    @Published public private(set) var lastResult: FixNowResult?

    public struct FixNowResult {
        public let original: String
        public let corrected: String
        public let changed: Bool
    }

    nonisolated static let maxWindowCharacters = 2000
    static let doubleTapInterval: TimeInterval = 0.4

    private var fixTask: Task<Void, Never>?
    private var suppressGhostUntil: Date = .distantPast

    private init() {}

    // MARK: - Sentence Window (pure, testable)

    /// Returns the last complete sentences within `text`, capped at
    /// `maxWindowCharacters`. If the cap cuts into a sentence, the window
    /// starts after the first sentence terminator inside the cut so the
    /// window always contains full sentences.
    nonisolated static func sentenceWindow(in text: String, maxCharacters: Int = FixNowManager.maxWindowCharacters) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard trimmed.count > maxCharacters else { return trimmed }

        let start = trimmed.index(trimmed.endIndex, offsetBy: -maxCharacters)
        let cut = String(trimmed[start...])

        // The window is the last complete sentence(s) inside the cut: take
        // everything after the sentence terminator that precedes the final
        // one, so the trailing sentence stays whole and earlier partial
        // content is dropped.
        let terminators: Set<Character> = [".", "!", "?", "\n"]
        let terminatorIndices = cut.indices.filter { terminators.contains(cut[$0]) }
        if terminatorIndices.count >= 2 {
            let rest = String(cut[cut.index(after: terminatorIndices[terminatorIndices.count - 2])...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !rest.isEmpty {
                return rest
            }
        }
        if let last = terminatorIndices.last {
            let rest = String(cut[cut.index(after: last)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !rest.isEmpty {
                return rest
            }
        }
        return cut
    }

    // MARK: - Prompt (pure, testable)

    nonisolated static let fixSystemPrompt = """
    Bạn là công cụ sửa lỗi chính tả, ngữ pháp và dấu câu cho bộ gõ TuiGoAI.
    Chỉ sửa lỗi chính tả, ngữ pháp, dấu câu. Giữ nguyên ý nghĩa, xưng hô, giọng văn, cấu trúc câu, xuống dòng và số lượng câu. Không viết lại câu không có lỗi. Không thêm câu mới. Không giải thích. Chỉ trả về văn bản đã sửa.
    """

    nonisolated static func buildFixUserPrompt(_ text: String) -> String {
        """
        Sửa lỗi chính tả, ngữ pháp, dấu câu trong đoạn sau. Nếu đoạn không có lỗi, trả về nguyên văn.

        Văn bản:
        \"\"\"
        \(text.precomposedStringWithCanonicalMapping)
        \"\"\"
        """
    }

    // MARK: - Trigger from keyboard hook

    /// Called from the CGEvent tap when a double Right Command tap is detected.
    public func trigger() {
        guard !isFixing else { return }
        guard AIService.shared.loadConfig().isEnabled else { return }

        fixTask?.cancel()
        suppressGhostUntil = Date().addingTimeInterval(30)
        GhostTextManager.shared.dismiss()

        fixTask = Task { [weak self] in
            await self?.performFix()
        }
    }

    /// Ghost text checks this so suggestions stay quiet while FixNow runs.
    public func isGhostSuppressed() -> Bool {
        Date() < suppressGhostUntil
    }

    // MARK: - Fix pipeline

    private func performFix() async {
        guard let field = Self.readFocusedField() else { return }
        let window = Self.sentenceWindow(in: field.textBeforeCaret)
        guard window.count >= 8 else { return }

        isFixing = true
        defer { isFixing = false }

        let corrected: String
        do {
            corrected = try await AIService.shared.fixSpelling(window)
        } catch {
            return
        }
        guard !Task.isCancelled else { return }

        let cleaned = corrected.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        let changed = !cleaned.localizedStandardContains("") && cleaned != window
        lastResult = FixNowResult(original: window, corrected: cleaned, changed: cleaned != window)
        guard cleaned != window else { return }
        _ = changed

        // Re-read the field right before writing: the user may have typed
        // while the model was running. Recompute the window start against the
        // fresh text and replace by exact-match of the original window.
        guard let fresh = Self.readFocusedField() else { return }
        let freshWindow = Self.sentenceWindow(in: fresh.textBeforeCaret)
        guard let full = fresh.fullText else { return }

        let newText: String
        if let range = full.range(of: window) {
            newText = full.replacingCharacters(in: range, with: cleaned)
        } else if window == freshWindow, let range = full.range(of: freshWindow) {
            newText = full.replacingCharacters(in: range, with: cleaned)
        } else {
            // Text drifted too much while the model ran; do not guess.
            return
        }

        Self.writeBack(field: field, newText: newText)
    }

    // MARK: - Accessibility read/write

    struct FocusedField {
        let element: AXUIElement
        let fullText: String?
        let textBeforeCaret: String
    }

    static func readFocusedField() -> FocusedField? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let ref = focusedRef,
              CFGetTypeID(ref) == AXUIElementGetTypeID()
        else { return nil }
        var element = unsafeBitCast(ref, to: AXUIElement.self)

        // Chromium / WebKit inner focus resolution
        var innerRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &innerRef) == .success,
           let inner = innerRef,
           CFGetTypeID(inner) == AXUIElementGetTypeID() {
            element = unsafeBitCast(inner, to: AXUIElement.self)
        }

        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        if (roleRef as? String) == "AXSecureTextField" { return nil }

        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let fullText = valueRef as? String, !fullText.isEmpty
        else { return nil }

        var rangeRef: CFTypeRef?
        var caretUTF16 = fullText.utf16.count
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rv = rangeRef,
           CFGetTypeID(rv) == AXValueGetTypeID() {
            var range = CFRange(location: 0, length: 0)
            if AXValueGetValue(unsafeBitCast(rv, to: AXValue.self), .cfRange, &range), range.location >= 0 {
                caretUTF16 = range.location
            }
        }
        guard caretUTF16 <= fullText.utf16.count else { return nil }
        let idx = String.Index(utf16Offset: caretUTF16, in: fullText)
        let before = String(fullText[..<idx]).precomposedStringWithCanonicalMapping

        return FocusedField(element: element, fullText: fullText, textBeforeCaret: before)
    }

    /// Writes the corrected full text back via AX and restores the caret to
    /// the end of the corrected window.
    static func writeBack(field: FocusedField, newText: String) {
        let element = field.element
        guard AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, newText as CFTypeRef) == .success else {
            return
        }
        // Place caret at end of the original text position (close enough: the
        // corrected window ends where the user last typed).
        var range = CFRange(location: newText.utf16.count, length: 0)
        if let axRange = AXValueCreate(.cfRange, &range) {
            AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axRange)
        }
    }
}
