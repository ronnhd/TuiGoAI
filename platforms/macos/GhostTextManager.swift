import AppKit
import ApplicationServices
import Combine
import Foundation

// MARK: - Ghost Text State & Manager

@MainActor
public final class GhostTextManager: ObservableObject {
    public static let shared = GhostTextManager()

    @Published public private(set) var currentSuggestion: String = ""
    @Published public private(set) var isShowing: Bool = false

    private var debounceTask: Task<Void, Never>?
    private var completionTask: Task<Void, Never>?
    private var overlayWindow: GhostTextOverlayWindow?
    private var contextGeneration: UInt64 = 0

    private let axSystemWide = AXUIElementCreateSystemWide()
    nonisolated private static let snapshotLock = NSLock()
    nonisolated(unsafe) private static var snapshotSuggestion = ""

    // Config keys
    nonisolated public static let acceptShortcutKey = "tuigoai.ai.shortcut.accept"
    nonisolated public static let toggleShortcutKey = "tuigoai.ai.shortcut.toggle"
    nonisolated public static let aiEnabledKey = "tuigoai.ai.enabled"
    nonisolated public static let displayModeKey = "tuigoai.ai.display.mode"
    nonisolated public static let completionLengthKey = "tuigoai.ai.completion.length"
    nonisolated public static let clipboardContextEnabledKey = "tuigoai.ai.context.clipboard"

    private init() {
        setupOverlay()
    }

    private func setupOverlay() {
        overlayWindow = GhostTextOverlayWindow()
    }

    // MARK: - Keystroke Event Handling

    /// Called by keyboard hook when a key event occurs
    public func handleKeystroke(keyCode: UInt16, isKeyDown: Bool) {
        contextGeneration &+= 1
        let generation = contextGeneration
        guard isKeyDown, AIService.shared.loadConfig().isEnabled else {
            dismiss()
            return
        }

        // On new keystroke, cancel ongoing completion immediately
        completionTask?.cancel()
        completionTask = nil

        // If suggestion was already visible and user types, check matching or dismiss
        if isShowing {
            dismiss()
        }

        // Debounce before fetching new ghost text suggestion (150-250ms)
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 200_000_000) // 200ms
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            guard let self, self.contextGeneration == generation else { return }
            self.requestSuggestion(generation: generation)
        }
    }

    // MARK: - Suggestion Request

    public func requestSuggestion(generation: UInt64? = nil) {
        let generation = generation ?? contextGeneration
        guard AIService.shared.loadConfig().isEnabled else { return }

        // Read context around caret via Accessibility
        guard let context = readCaretContext() else {
            dismiss()
            return
        }

        // Smart suppression check: skip secure fields, URLs, code, or completed sentences
        if context.isSecure || Self.shouldSuppress(prefixText: context.prefixText) {
            dismiss()
            return
        }

        completionTask?.cancel()
        completionTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                let suggestion = try await AIService.shared.suggestCompletion(
                    prefixText: context.prefixText,
                    suffixText: context.suffixText,
                    appName: context.appName,
                    bundleId: context.bundleId
                )
                guard !Task.isCancelled, self.contextGeneration == generation else { return }

                let cleanSuggestion = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleanSuggestion.isEmpty else {
                    self.dismiss()
                    return
                }

                let isMidLine = !context.suffixText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                self.show(suggestion: cleanSuggestion, at: context.caretRect, isMidLine: isMidLine)
            } catch {
                // Fail silently on timeout or network cancel
                self.dismiss()
            }
        }
    }

    // MARK: - Display & Dismiss

    public func show(suggestion: String, at caretRect: CGRect?, isMidLine: Bool = false) {
        self.currentSuggestion = suggestion
        self.isShowing = true
        Self.snapshotLock.lock()
        Self.snapshotSuggestion = suggestion
        Self.snapshotLock.unlock()
        overlayWindow?.display(text: suggestion, at: caretRect, isMidLine: isMidLine)
    }

    public func dismiss() {
        debounceTask?.cancel()
        debounceTask = nil
        completionTask?.cancel()
        completionTask = nil
        currentSuggestion = ""
        isShowing = false
        Self.snapshotLock.lock()
        Self.snapshotSuggestion = ""
        Self.snapshotLock.unlock()
        overlayWindow?.hide()
    }

    /// Xử lý khi người dùng bấm phím Enter/Return (gửi tin nhắn trong app chat)
    public func handleReturnKey() {
        guard let context = readCaretContext() else { return }
        let text = context.prefixText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty, let bundle = context.bundleId {
            ChatHistoryBuffer.shared.record(text: text, bundleId: bundle)
        }
        dismiss()
    }

    public nonisolated static func invalidateSuggestionFromHook() {
        snapshotLock.lock()
        snapshotSuggestion = ""
        snapshotLock.unlock()
    }

    public nonisolated static func hasSuggestionSnapshot() -> Bool {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return !snapshotSuggestion.isEmpty
    }

    /// Accept suggestion and inject text into active app
    public func acceptSuggestion() -> String? {
        guard isShowing, !currentSuggestion.isEmpty else { return nil }
        let acceptedText = currentSuggestion
        if let context = readCaretContext(), let bundle = context.bundleId {
            let fullSentence = (context.prefixText + acceptedText).trimmingCharacters(in: .whitespacesAndNewlines)
            if !fullSentence.isEmpty {
                ChatHistoryBuffer.shared.record(text: fullSentence, bundleId: bundle)
            }
        }
        dismiss()
        return acceptedText
    }

    public func handleAcceptShortcut(keyCode: UInt16, flags: CGEventFlags) -> String? {
        let shortcut = loadShortcut()
        let modifierMask: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn]
        guard shortcut.keyCode == keyCode,
              shortcut.modifiers == flags.intersection(modifierMask).rawValue
        else { return nil }
        return acceptSuggestion()
    }

    public nonisolated static func matchesToggleShortcutFromHook(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        let modifierMask: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn]
        let shortcut: KeyboardShortcut
        if let data = UserDefaults.standard.data(forKey: toggleShortcutKey),
           let decoded = try? JSONDecoder().decode(KeyboardShortcut.self, from: data) {
            shortcut = decoded
        } else {
            shortcut = KeyboardShortcut(keyCode: 0x31, modifiers: CGEventFlags.maskControl.union(.maskAlternate).rawValue)
        }
        return shortcut.keyCode == keyCode && shortcut.modifiers == flags.intersection(modifierMask).rawValue
    }

    public nonisolated static func acceptSuggestionFromHook(keyCode: UInt16, flags: CGEventFlags) -> String? {
        let modifierMask: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn]
        let shortcut: KeyboardShortcut
        if let data = UserDefaults.standard.data(forKey: acceptShortcutKey),
           let decoded = try? JSONDecoder().decode(KeyboardShortcut.self, from: data) {
            shortcut = decoded
        } else {
            shortcut = KeyboardShortcut(keyCode: 0x30, modifiers: 0)
        }
        guard shortcut.keyCode == keyCode,
              shortcut.modifiers == flags.intersection(modifierMask).rawValue
        else { return nil }

        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        guard !snapshotSuggestion.isEmpty else { return nil }
        let accepted = snapshotSuggestion
        snapshotSuggestion = ""
        return accepted
    }

    public nonisolated static func acceptNextWordFromHook(keyCode: UInt16, flags: CGEventFlags) -> (head: String, rest: String)? {
        // Option + Right Arrow (keyCode 124 = right arrow, modifier: maskAlternate)
        let modifierMask: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn]
        let currentModifiers = flags.intersection(modifierMask)
        guard keyCode == 124, currentModifiers == .maskAlternate else { return nil }

        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        guard !snapshotSuggestion.isEmpty else { return nil }

        let (head, rest) = NextWordSplitter.split(snapshotSuggestion)
        guard !head.isEmpty else { return nil }
        snapshotSuggestion = rest
        return (head, rest)
    }

    public func updateRemainingSuggestion(_ rest: String) {
        currentSuggestion = rest
        if rest.isEmpty {
            dismiss()
        } else {
            if let context = readCaretContext() {
                let isMidLine = !context.suffixText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                show(suggestion: rest, at: context.caretRect, isMidLine: isMidLine)
            } else {
                dismiss()
            }
        }
    }

    /// Bộ lọc Smart Suppression: ngăn gợi ý không cần thiết khi gõ URL, code, số hoặc sau dấu chấm
    public nonisolated static func shouldSuppress(prefixText: String) -> Bool {
        let trimmed = prefixText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 3 { return true }

        // 1. Dấu câu kết thúc đoạn văn và chưa có chữ mới
        if let lastChar = trimmed.last, [".", "!", "?", ";", ":"].contains(lastChar) {
            return true
        }

        // 2. URL hoặc Email
        let lower = trimmed.lowercased()
        if lower.contains("http://") || lower.contains("https://") || lower.contains("www.") ||
           (trimmed.contains("@") && !trimmed.contains(" ") && trimmed.count > 5) {
            return true
        }

        // 3. Chuỗi số điện thoại / OTP / mã số
        if trimmed.suffix(6).allSatisfy({ $0.isNumber || $0 == " " }) && trimmed.filter(\.isNumber).count >= 4 {
            return true
        }

        // 4. Cú pháp lập trình / lệnh dòng lệnh
        if lower.hasPrefix("import ") || lower.hasPrefix("func ") || lower.hasPrefix("class ") ||
           lower.hasPrefix("def ") || lower.hasPrefix("const ") || lower.hasPrefix("let ") ||
           lower.hasPrefix("git ") || lower.hasPrefix("curl ") {
            return true
        }

        return false
    }

    private func loadShortcut() -> KeyboardShortcut {
        guard let data = UserDefaults.standard.data(forKey: Self.acceptShortcutKey),
              let shortcut = try? JSONDecoder().decode(KeyboardShortcut.self, from: data)
        else {
            return KeyboardShortcut(keyCode: 0x30, modifiers: 0)
        }
        return shortcut
    }

    // MARK: - Caret Context Extraction (AXUIElement)

    public struct CaretContext {
        public let prefixText: String
        public let suffixText: String
        public let caretRect: CGRect?
        public let isSecure: Bool
        public let bundleId: String?
        public let appName: String?
    }

    public func readCaretContext() -> CaretContext? {
        let frontApp = NSWorkspace.shared.frontmostApplication
        let currentBundleId = frontApp?.bundleIdentifier
        let currentAppName = frontApp?.localizedName

        var focusedAppValue: CFTypeRef?
        let appErr = AXUIElementCopyAttributeValue(axSystemWide, kAXFocusedApplicationAttribute as CFString, &focusedAppValue)
        guard appErr == .success, let focusedApp = focusedAppValue else {
            return nil
        }
        guard CFGetTypeID(focusedApp) == AXUIElementGetTypeID() else { return nil }
        let focusedAppElement = unsafeBitCast(focusedApp, to: AXUIElement.self)

        // Enable Enhanced User Interface for Chromium / WebKit to calculate character metrics
        AXUIElementSetAttributeValue(focusedAppElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)

        var focusedElementValue: CFTypeRef?
        let elemErr = AXUIElementCopyAttributeValue(focusedAppElement, kAXFocusedUIElementAttribute as CFString, &focusedElementValue)
        guard elemErr == .success, let focusedElement = focusedElementValue else {
            return nil
        }
        guard CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else { return nil }
        var element = unsafeBitCast(focusedElement, to: AXUIElement.self)

        // In Chromium / WebKit, if focusedElement is a WebArea or container, resolve active inner text element
        var innerFocusValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &innerFocusValue) == .success,
           let innerFocus = innerFocusValue,
           CFGetTypeID(innerFocus) == AXUIElementGetTypeID() {
            element = unsafeBitCast(innerFocus, to: AXUIElement.self)
        }

        // Check if secure field (password)
        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        var subroleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue)

        let isSecureRole = (subroleValue as? String) == "AXSecureTextField" || (roleValue as? String) == "AXSecureTextField"
        if isSecureRole {
            return CaretContext(prefixText: "", suffixText: "", caretRect: nil, isSecure: true, bundleId: currentBundleId, appName: currentAppName)
        }

        // Get selected text range (or caret location)
        var selectedRangeValue: CFTypeRef?
        let rangeErr = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue)
        var selectedRange = CFRange(location: 0, length: 0)
        guard rangeErr == .success, let rangeValue = selectedRangeValue,
              CFGetTypeID(rangeValue) == AXValueGetTypeID(),
              AXValueGetType(unsafeBitCast(rangeValue, to: AXValue.self)) == .cfRange,
              AXValueGetValue(unsafeBitCast(rangeValue, to: AXValue.self), .cfRange, &selectedRange),
              selectedRange.location >= 0, selectedRange.length == 0
        else { return nil }

        // AX offsets are UTF-16 offsets, not Swift Character offsets.
        var textValue: CFTypeRef?
        let textErr = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textValue)
        var fullText = ""
        if textErr == .success, let text = textValue as? String {
            fullText = text
        }

        // Extract context using UTF-16 offsets returned by Accessibility.
        let utf16 = fullText.utf16
        guard selectedRange.location <= utf16.count else { return nil }
        let caretIndex = selectedRange.location
        let endIndex = String.Index(utf16Offset: caretIndex, in: fullText)
        let beforeCaret = String(fullText[..<endIndex])
        let afterCaret = String(fullText[endIndex...])
        let prefixText = String(beforeCaret.suffix(2000))
        let suffixText = String(afterCaret.prefix(500))

        // Bounds for caret position to anchor floating overlay.
        var caretRect: CGRect?

        func queryBounds(range: CFRange) -> CGRect? {
            var r = range
            guard let axVal = AXValueCreate(.cfRange, &r) else { return nil }
            var boundsValue: CFTypeRef?
            let boundsErr = AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXBoundsForRangeParameterizedAttribute as CFString,
                axVal,
                &boundsValue
            )
            guard boundsErr == .success, let boundsVal = boundsValue,
                  CFGetTypeID(boundsVal) == AXValueGetTypeID() else { return nil }
            let boundsAXValue = unsafeBitCast(boundsVal, to: AXValue.self)
            var rect = CGRect.zero
            if AXValueGetType(boundsAXValue) == .cgRect,
               AXValueGetValue(boundsAXValue, .cgRect, &rect) {
                if rect.isNull || rect.isInfinite || rect.height <= 0 {
                    return nil
                }
                // Zero-length selection legitimately has width <= 0 in Cocoa / Blink
                if rect.width <= 0 {
                    rect.size.width = 2
                }
                return rect
            }
            return nil
        }

        // 1. Try zero-length caret rect (valid caret rect has width <= 5)
        if let rect = queryBounds(range: selectedRange), rect.width <= 5 {
            caretRect = rect
        } else if selectedRange.location > 0 {
            // 2. Character-bounds fallback for WebKit / Electron / Chromium:
            // Query bounds of single character immediately preceding the caret
            if let charRect = queryBounds(range: CFRange(location: selectedRange.location - 1, length: 1)) {
                caretRect = CGRect(x: charRect.maxX, y: charRect.origin.y, width: 2, height: charRect.height)
            }
        } else if selectedRange.location == 0 && utf16.count > 0 {
            // 3. Start of text: bounds of the first character
            if let charRect = queryBounds(range: CFRange(location: 0, length: 1)) {
                caretRect = CGRect(x: charRect.minX, y: charRect.origin.y, width: 2, height: charRect.height)
            }
        }

        // 4. Fallback for fields where kAXBoundsForRange is not supported: anchor using element frame + text width
        if caretRect == nil {
            var posValue: CFTypeRef?
            var sizeValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
               AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
               let pVal = posValue, let sVal = sizeValue {
                var pos = CGPoint.zero
                var size = CGSize.zero
                let axPos = unsafeBitCast(pVal, to: AXValue.self)
                let axSize = unsafeBitCast(sVal, to: AXValue.self)
                if AXValueGetType(axPos) == .cgPoint, AXValueGetType(axSize) == .cgSize,
                   AXValueGetValue(axPos, .cgPoint, &pos),
                   AXValueGetValue(axSize, .cgSize, &size),
                   size.width > 10, size.height > 0 {
                    let lastLine = prefixText.components(separatedBy: .newlines).last ?? prefixText
                    let font = NSFont.systemFont(ofSize: 13)
                    let textWidth = (lastLine as NSString).size(withAttributes: [.font: font]).width
                    let estimatedX = min(pos.x + 8 + textWidth, pos.x + size.width - 24)
                    caretRect = CGRect(
                        x: max(pos.x + 8, estimatedX),
                        y: pos.y + max(0, size.height - 24),
                        width: 2,
                        height: min(size.height, 22)
                    )
                }
            }
        }

        return CaretContext(prefixText: prefixText, suffixText: suffixText, caretRect: caretRect, isSecure: false, bundleId: currentBundleId, appName: currentAppName)
    }
}

// MARK: - Overlay Window (Non-activating floating panel)

final class GhostTextOverlayWindow: NSPanel {
    private let label = NSTextField(labelWithString: "")
    private let badge = NSTextField(labelWithString: "Tab ⇥")
    private let visualEffect = NSVisualEffectView()
    private var stack: NSStackView!

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 250, height: 26),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )

        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none

        let container = NSView()
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 6
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderWidth = 0.5
        visualEffect.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        visualEffect.translatesAutoresizingMaskIntoConstraints = false

        label.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        badge.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        badge.textColor = NSColor.secondaryLabelColor
        badge.translatesAutoresizingMaskIntoConstraints = false

        stack = NSStackView(views: [label, badge])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(visualEffect)
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            visualEffect.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            visualEffect.topAnchor.constraint(equalTo: container.topAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        contentView = container
    }

    func display(text: String, at caretRect: CGRect?, isMidLine: Bool = false) {
        let isInline = (UserDefaults.standard.string(forKey: GhostTextManager.displayModeKey) ?? "inline") == "inline"
        updateBadgeText(isInline: isInline)
        label.stringValue = text

        // Visual effect HUD ensures crisp, high-contrast readability across all web pages and light/dark modes
        visualEffect.isHidden = false
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        hasShadow = true
        label.textColor = NSColor.labelColor.withAlphaComponent(0.9)

        if isInline {
            badge.isHidden = true
            stack.edgeInsets = NSEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
        } else {
            badge.isHidden = false
            stack.edgeInsets = NSEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)
        }

        let size = label.intrinsicContentSize
        let totalWidth: CGFloat
        if isInline {
            totalWidth = size.width + 16
        } else {
            totalWidth = min(max(size.width + 64, 110), 650)
        }
        let totalHeight: CGFloat = 26

        var screenOrigin = CGPoint(x: 100, y: 100)
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? (NSScreen.main?.frame.height ?? 1080)

        guard let caret = caretRect, !caret.isEmpty else {
            hide()
            return
        }

        // Coordinate conversion: AX coords have (0,0) at top-left of primary screen.
        // AppKit coords have (0,0) at bottom-left of primary screen.
        let caretBottomY = primaryScreenHeight - (caret.origin.y + caret.height)
        let y: CGFloat
        if isMidLine {
            // Position 4px below caret line to never overlap the suffix text on the same line
            y = caretBottomY - totalHeight - 4
        } else {
            y = caretBottomY + (caret.height - totalHeight) / 2
        }
        let horizontalGap: CGFloat = isInline ? 10 : 12
        let x = caret.origin.x + caret.width + horizontalGap
        screenOrigin = CGPoint(x: x, y: y)

        // Clamp to screen bounds so overlay doesn't overflow screen right edge
        if let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(screenOrigin) }) ?? NSScreen.main {
            let maxX = targetScreen.frame.maxX - totalWidth - 8
            if screenOrigin.x > maxX {
                screenOrigin.x = max(targetScreen.frame.minX + 8, maxX)
            }
        }

        setFrame(NSRect(origin: screenOrigin, size: CGSize(width: totalWidth, height: totalHeight)), display: true)
        if !isVisible {
            orderFrontRegardless()
        }
    }

    private func updateBadgeText(isInline: Bool) {
        guard !isInline else { return }
        if let data = UserDefaults.standard.data(forKey: GhostTextManager.acceptShortcutKey),
           let shortcut = try? JSONDecoder().decode(KeyboardShortcut.self, from: data) {
            if shortcut.keyCode == 0x30 && shortcut.modifiers == 0 {
                badge.stringValue = "Tab ⇥ | ⌥→ từ"
            } else {
                let parts = shortcut.displayParts.joined()
                badge.stringValue = parts.isEmpty ? "⇥" : "\(parts) ⇥ | ⌥→ từ"
            }
        } else {
            badge.stringValue = "Tab ⇥ | ⌥→ từ"
        }
    }

    func hide() {
        orderOut(nil)
    }
}
