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

    private let axSystemWide = AXUIElementCreateSystemWide()
    nonisolated private static let snapshotLock = NSLock()
    nonisolated(unsafe) private static var snapshotSuggestion = ""

    // Config keys
    nonisolated public static let acceptShortcutKey = "tuigoai.ai.shortcut.accept"
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
        guard AIService.shared.loadConfig().isEnabled else {
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
            self?.requestSuggestion()
        }
    }

    // MARK: - Suggestion Request

    public func requestSuggestion() {
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
                let suggestion = try await AIService.shared.suggestCompletion(prefixText: context.prefixText)
                guard !Task.isCancelled else { return }

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
        public let caretRect: CGRect?
        public let isSecure: Bool
    }

    public func readCaretContext() -> CaretContext? {
        var focusedAppValue: CFTypeRef?
        let appErr = AXUIElementCopyAttributeValue(axSystemWide, kAXFocusedApplicationAttribute as CFString, &focusedAppValue)
        guard appErr == .success, let focusedApp = focusedAppValue else {
            return nil
        }
        let focusedAppElement = unsafeBitCast(focusedApp, to: AXUIElement.self)

        var focusedElementValue: CFTypeRef?
        let elemErr = AXUIElementCopyAttributeValue(focusedAppElement, kAXFocusedUIElementAttribute as CFString, &focusedElementValue)
        guard elemErr == .success, let focusedElement = focusedElementValue else {
            return nil
        }
        let element = unsafeBitCast(focusedElement, to: AXUIElement.self)

        // Check if secure field (password)
        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        var subroleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue)

        let isSecureRole = (subroleValue as? String) == "AXSecureTextField" || (roleValue as? String) == "AXSecureTextField"
        if isSecureRole {
            return CaretContext(prefixText: "", caretRect: nil, isSecure: true)
        }

        // Get selected text range (or caret location)
        var selectedRangeValue: CFTypeRef?
        let rangeErr = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue)
        var caretIndex: Int = 0

        if rangeErr == .success, let rangeValue = selectedRangeValue {
            let rangeAXValue = unsafeBitCast(rangeValue, to: AXValue.self)
            var range = CFRange()
            if AXValueGetValue(rangeAXValue, .cfRange, &range) {
                caretIndex = range.location
            }
        }

        // Get text value
        var textValue: CFTypeRef?
        let textErr = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textValue)
        var fullText = ""
        if textErr == .success, let text = textValue as? String {
            fullText = text
        }

        // Extract last 1-2 sentences before caret
        var prefixText = ""
        if !fullText.isEmpty && caretIndex > 0 && caretIndex <= fullText.count {
            let endIndex = fullText.index(fullText.startIndex, offsetBy: caretIndex)
            let beforeCaret = String(fullText[..<endIndex])
            // Take up to last 200 characters
            prefixText = String(beforeCaret.suffix(200))
        }

        // Bounds for caret position to anchor floating overlay
        var caretRect: CGRect?
        if let rangeValue = selectedRangeValue {
            let rangeAXValue = unsafeBitCast(rangeValue, to: AXValue.self)
            var boundsValue: CFTypeRef?
            let boundsErr = AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXBoundsForRangeParameterizedAttribute as CFString,
                rangeAXValue,
                &boundsValue
            )
            if boundsErr == .success, let boundsVal = boundsValue {
                let boundsAXValue = unsafeBitCast(boundsVal, to: AXValue.self)
                var rect = CGRect.zero
                if AXValueGetValue(boundsAXValue, .cgRect, &rect) {
                    caretRect = rect
                }
            }
        }

        return CaretContext(prefixText: prefixText, caretRect: caretRect, isSecure: false)
    }
}

// MARK: - Overlay Window (Non-activating floating panel)

final class GhostTextOverlayWindow: NSPanel {
    private let label = NSTextField(labelWithString: "")

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
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 6
        visualEffect.layer?.masksToBounds = true

        label.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        label.textColor = NSColor.secondaryLabelColor
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false

        let badge = NSTextField(labelWithString: "Tab ⇥")
        badge.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        badge.textColor = NSColor.tertiaryLabelColor
        badge.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [label, badge])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
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
        label.stringValue = text

        // Size to fit
        let size = label.intrinsicContentSize
        let totalWidth = max(size.width + 70, 120)
        let totalHeight: CGFloat = 28

        var screenOrigin = CGPoint(x: 100, y: 100)
        if let caret = caretRect, !caret.isEmpty {
            // Flip cocoa coordinate system: macOS AX returns top-left coords
            if let mainScreen = NSScreen.main {
                let screenHeight = mainScreen.frame.height
                screenOrigin = CGPoint(x: caret.origin.x + caret.width + 4, y: screenHeight - caret.origin.y - totalHeight - 2)
            } else {
                screenOrigin = CGPoint(x: caret.origin.x + caret.width + 4, y: caret.origin.y)
            }
        } else if let mouseLoc = NSEvent.mouseLocation as CGPoint? {
            screenOrigin = CGPoint(x: mouseLoc.x + 10, y: mouseLoc.y - 20)
        }

        setFrame(NSRect(origin: screenOrigin, size: CGSize(width: totalWidth, height: totalHeight)), display: true)
        orderFront(nil)
    }

    func hide() {
        orderOut(nil)
    }
}
