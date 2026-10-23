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
    nonisolated static let doubleTapInterval: TimeInterval = 0.4

    // Config keys
    nonisolated public static let fixNowEnabledKey = "tuigoai.fixnow.enabled"
    nonisolated public static let fixNowTapKeyCodeKey = "tuigoai.fixnow.tap.keycode"
    nonisolated public static let fixNowWindowKey = "tuigoai.fixnow.window.characters"

    nonisolated public static var windowCharacters: Int {
        let stored = UserDefaults.standard.integer(forKey: fixNowWindowKey)
        if stored > 0 { return stored }
        return 800
    }

    /// Modifier keycodes that support double-tap. AX flagsChanged reports the
    /// physical key, so left and right variants are separate options.
    nonisolated public static let tapKeyOptions: [(keyCode: UInt16, label: String)] = [
        (54, "Right Command"),
        (55, "Left Command"),
        (58, "Right Option"),
        (61, "Left Option"),
        (59, "Right Control"),
        (62, "Left Control")
    ]

    nonisolated public static var tapKeyCode: UInt16 {
        let stored = UserDefaults.standard.integer(forKey: fixNowTapKeyCodeKey)
        return (stored > 0) ? UInt16(stored) : 54
    }

    nonisolated public static var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: fixNowEnabledKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: fixNowEnabledKey)
    }

    private var fixTask: Task<Void, Never>?
    private var suppressGhostUntil: Date = .distantPast
    private var statusWindow: FixNowStatusWindow?

    private init() {}

    // MARK: - Sentence Window (pure, testable)

    /// Returns the last complete sentences within `text`, capped at
    /// `windowCharacters` (configurable in Settings). If the cap cuts into a
    /// sentence, the window starts after the first sentence terminator inside
    /// the cut so the window always contains full sentences.
    nonisolated static func sentenceWindow(in text: String, maxCharacters: Int = FixNowManager.windowCharacters) -> String {
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

    /// Called from the CGEvent tap when a double tap of the configured key is detected.
    public func trigger() {
        guard Self.isEnabled else { return }
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

    @Published public private(set) var lastStatus: String = "Chưa chạy lần nào"

    private func setStatus(_ text: String) {
        Task { @MainActor in
            self.lastStatus = text
        }
    }

    private func performFix() async {
        setStatus("Đang đọc ô nhập")
        guard let field = Self.readFocusedField() else {
            setStatus("Không đọc được ô nhập đang focus")
            return
        }
        let window = Self.sentenceWindow(in: field.textBeforeCaret)
        guard window.count >= 8 else {
            setStatus("Đoạn trước con trỏ quá ngắn")
            return
        }

        isFixing = true
        showIndicator()
        setStatus("Đang gửi cho model sửa")
        defer {
            isFixing = false
            hideIndicator()
        }

        let corrected: String
        do {
            corrected = try await AIService.shared.fixSpelling(window)
        } catch {
            setStatus("Model không phản hồi")
            return
        }
        guard !Task.isCancelled else {
            setStatus("Đã huỷ lượt sửa")
            return
        }

        let cleaned = corrected.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            setStatus("Model trả về rỗng")
            return
        }

        // Model refused to fix and answered with a meta comment instead of
        // corrected prose; keep the original text in that case.
        guard Self.looksLikeCorrectedProse(cleaned, original: window) else {
            setStatus("Model trả lời lung tung, đã bỏ qua")
            return
        }

        lastResult = FixNowResult(original: window, corrected: cleaned, changed: cleaned != window)

        guard cleaned != window else {
            setStatus("Không có lỗi cần sửa")
            return
        }

        // Re-read the field right before writing: the user may have typed
        // while the model was running. Recompute the window start against the
        // fresh text and replace by exact-match of the original window.
        guard let fresh = Self.readFocusedField() else {
            setStatus("Ô nhập đã đổi, bỏ qua lượt sửa")
            return
        }
        let freshWindow = Self.sentenceWindow(in: fresh.textBeforeCaret)
        guard let full = fresh.fullText else {
            setStatus("Không đọc lại được nội dung")
            return
        }

        let newText: String
        if let range = full.range(of: window) {
            newText = full.replacingCharacters(in: range, with: cleaned)
        } else if window == freshWindow, let range = full.range(of: freshWindow) {
            newText = full.replacingCharacters(in: range, with: cleaned)
        } else {
            // Text drifted too much while the model ran; do not guess.
            setStatus("Văn bản đã thay đổi, bỏ qua để không mất chữ")
            return
        }

        Self.writeBack(field: fresh, newText: newText)
        setStatus("Đã sửa xong")
    }

    /// Meta answers from the model ("không có lỗi cần sửa", preamble lines)
    /// must never reach the text field. A safe replacement shares most words
    /// with the original; a meta reply does not.
    nonisolated static func looksLikeCorrectedProse(_ candidate: String, original: String) -> Bool {
        // Obvious meta phrases in Vietnamese or English.
        let lowered = candidate.lowercased()
        let metaMarkers = [
            "không có lỗi",
            "khong co loi",
            "cần sửa",
            "can sua",
            "văn bản này",
            "van ban nay",
            "đoạn văn bản",
            "doan van ban",
            "no errors",
            "nothing to fix",
            "the text is already",
            "as an ai",
            "tôi là",
            "toi la",
            "i'm an ai",
            "xin lỗi",
            "xin loi"
        ]
        if metaMarkers.contains(where: { lowered.contains($0) }) {
            return false
        }
        // Overlap guard: the candidate must reuse at least half of the
        // original's significant words, compared with diacritics removed so
        // "toi" matches "tôi". Otherwise the candidate is not an edit of
        // this text (model hallucination guard).
        func significantWords(_ text: String) -> Set<String> {
            Set(text.lowercased()
                .folding(options: .diacriticInsensitive, locale: Locale(identifier: "vi_VN"))
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 })
        }
        let originalWords = significantWords(original)
        guard !originalWords.isEmpty else { return true }
        let candidateWords = significantWords(candidate)
        let shared = originalWords.intersection(candidateWords).count
        return Double(shared) >= Double(originalWords.count) * 0.5
    }

    // MARK: - Indicator overlay

    @Published public private(set) var isIndicatorVisible: Bool = false

    private func showIndicator() {
        Task { @MainActor in
            guard let field = Self.readFocusedField() else { return }
            if self.statusWindow == nil {
                self.statusWindow = FixNowStatusWindow()
            }
            self.statusWindow?.display(at: field.caretRect)
            self.isIndicatorVisible = true
        }
    }

    private func hideIndicator() {
        Task { @MainActor in
            self.statusWindow?.hide()
            self.isIndicatorVisible = false
        }
    }

    // MARK: - Accessibility read/write
    struct FocusedField {
        let element: AXUIElement
        let fullText: String?
        let textBeforeCaret: String
        let caretRect: CGRect?
    }

    static func readFocusedField() -> FocusedField? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedAppRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedAppRef) == .success,
           let appRef = focusedAppRef,
           CFGetTypeID(appRef) == AXUIElementGetTypeID() {
            // Chromium and WebKit only expose character metrics after the
            // enhanced user interface flag is set (same trick as ghost text).
            let appElement = unsafeBitCast(appRef, to: AXUIElement.self)
            AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }

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

        // Caret bounds for anchoring the status indicator.
        var caretRect: CGRect?
        if caretUTF16 > 0 {
            var query = CFRange(location: caretUTF16 - 1, length: 1)
            if let axQuery = AXValueCreate(.cfRange, &query) {
                var boundsRef: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(
                    element,
                    kAXBoundsForRangeParameterizedAttribute as CFString,
                    axQuery,
                    &boundsRef
                ) == .success, let boundsVal = boundsRef,
                   CFGetTypeID(boundsVal) == AXValueGetTypeID() {
                    var rect = CGRect.zero
                    if AXValueGetType(unsafeBitCast(boundsVal, to: AXValue.self)) == .cgRect,
                       AXValueGetValue(unsafeBitCast(boundsVal, to: AXValue.self), .cgRect, &rect),
                       !rect.isEmpty {
                        caretRect = rect
                    }
                }
            }
        }

        return FocusedField(element: element, fullText: fullText, textBeforeCaret: before, caretRect: caretRect)
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
