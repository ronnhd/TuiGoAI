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

        // Skip secure/password fields or very short context
        if context.isSecure || context.prefixText.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 {
            dismiss()
            return
        }

        completionTask?.cancel()
        completionTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                let suggestion = try await AIService.shared.suggestCompletion(
                    prefixText: context.prefixText,
                    suffixText: context.suffixText
                )
                guard !Task.isCancelled, self.contextGeneration == generation else { return }

                let cleanSuggestion = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleanSuggestion.isEmpty else {
                    self.dismiss()
                    return
                }

                self.show(suggestion: cleanSuggestion, at: context.caretRect)
            } catch {
                // Fail silently on timeout or network cancel
                self.dismiss()
            }
        }
    }

    // MARK: - Display & Dismiss

    public func show(suggestion: String, at caretRect: CGRect?) {
        self.currentSuggestion = suggestion
        self.isShowing = true
        Self.snapshotLock.lock()
        Self.snapshotSuggestion = suggestion
        Self.snapshotLock.unlock()
        overlayWindow?.display(text: suggestion, at: caretRect)
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
    }

    public func readCaretContext() -> CaretContext? {
        var focusedAppValue: CFTypeRef?
        let appErr = AXUIElementCopyAttributeValue(axSystemWide, kAXFocusedApplicationAttribute as CFString, &focusedAppValue)
        guard appErr == .success, let focusedApp = focusedAppValue else {
            return nil
        }
        guard CFGetTypeID(focusedApp) == AXUIElementGetTypeID() else { return nil }
        let focusedAppElement = unsafeBitCast(focusedApp, to: AXUIElement.self)

        var focusedElementValue: CFTypeRef?
        let elemErr = AXUIElementCopyAttributeValue(focusedAppElement, kAXFocusedUIElementAttribute as CFString, &focusedElementValue)
        guard elemErr == .success, let focusedElement = focusedElementValue else {
            return nil
        }
        guard CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeBitCast(focusedElement, to: AXUIElement.self)

        // Check if secure field (password)
        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        var subroleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue)

        let isSecureRole = (subroleValue as? String) == "AXSecureTextField" || (roleValue as? String) == "AXSecureTextField"
        if isSecureRole {
            return CaretContext(prefixText: "", suffixText: "", caretRect: nil, isSecure: true)
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
        let prefixText = String(beforeCaret.suffix(240))
        let suffixText = String(afterCaret.prefix(240))

        // Bounds for caret position to anchor floating overlay.
        var caretRect: CGRect?
        if let rangeValue = selectedRangeValue,
           CFGetTypeID(rangeValue) == AXValueGetTypeID() {
            let rangeAXValue = unsafeBitCast(rangeValue, to: AXValue.self)
            var boundsValue: CFTypeRef?
            let boundsErr = AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXBoundsForRangeParameterizedAttribute as CFString,
                rangeAXValue,
                &boundsValue
            )
            if boundsErr == .success, let boundsVal = boundsValue,
               CFGetTypeID(boundsVal) == AXValueGetTypeID() {
                let boundsAXValue = unsafeBitCast(boundsVal, to: AXValue.self)
                var rect = CGRect.zero
                if AXValueGetType(boundsAXValue) == .cgRect,
                   AXValueGetValue(boundsAXValue, .cgRect, &rect) {
                    caretRect = rect
                }
            }
        }

        // Some Electron/WebKit text fields expose text and selection but do not
        // implement kAXBoundsForRangeParameterizedAttribute. Keep the context
        // usable; the overlay will fall back to the current mouse position.
        return CaretContext(prefixText: prefixText, suffixText: suffixText, caretRect: caretRect, isSecure: false)
    }
}

// MARK: - Overlay Window (Non-activating floating panel)

final class GhostTextOverlayWindow: NSPanel {
    private let label = NSTextField(labelWithString: "")
    private let badge = NSTextField(labelWithString: "Tab ⇥")
    private let visualEffect = NSVisualEffectView()

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
        hasShadow = true
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none

        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 6
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderWidth = 0.5
        visualEffect.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor

        label.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        label.textColor = NSColor.labelColor.withAlphaComponent(0.85)
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        badge.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        badge.textColor = NSColor.secondaryLabelColor
        badge.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [label, badge])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false

        visualEffect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
        ])

        contentView = visualEffect
    }

    func display(text: String, at caretRect: CGRect?) {
        updateBadgeText()
        label.stringValue = text

        let size = label.intrinsicContentSize
        let totalWidth = min(max(size.width + 64, 110), 650)
        let totalHeight: CGFloat = 26

        var screenOrigin = CGPoint(x: 100, y: 100)
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? (NSScreen.main?.frame.height ?? 1080)

        if let caret = caretRect, !caret.isEmpty {
            // Coordinate conversion: AX coords have (0,0) at top-left of primary screen.
            // AppKit coords have (0,0) at bottom-left of primary screen.
            let caretBottomY = primaryScreenHeight - (caret.origin.y + caret.height)
            let y = caretBottomY + (caret.height - totalHeight) / 2
            let x = caret.origin.x + caret.width + 4
            screenOrigin = CGPoint(x: x, y: y)
        } else if let mouseLoc = NSEvent.mouseLocation as CGPoint? {
            // Fallback for Electron / WebKit fields where caret rect is unavailable
            screenOrigin = CGPoint(x: mouseLoc.x + 8, y: mouseLoc.y - totalHeight - 4)
        }

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

    private func updateBadgeText() {
        if let data = UserDefaults.standard.data(forKey: GhostTextManager.acceptShortcutKey),
           let shortcut = try? JSONDecoder().decode(KeyboardShortcut.self, from: data) {
            if shortcut.keyCode == 0x30 && shortcut.modifiers == 0 {
                badge.stringValue = "Tab ⇥"
            } else {
                let parts = shortcut.displayParts.joined()
                badge.stringValue = parts.isEmpty ? "⇥" : "\(parts) ⇥"
            }
        } else {
            badge.stringValue = "Tab ⇥"
        }
    }

    func hide() {
        orderOut(nil)
    }
}
