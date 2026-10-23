import AppKit

// MARK: - FixNow Status Window
//
// Small non-activating HUD next to the caret showing an animated three-dot
// sequence while FixNow is correcting text. Reuses the same panel mechanics
// as the ghost text overlay: borderless, floating, click-through.

final class FixNowStatusWindow: NSPanel {
    private let dotsLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "Đang sửa")
    private let visualEffect = NSVisualEffectView()
    private var animationTimer: Timer?
    private var dotCount = 0

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 96, height: 24),
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

        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = NSColor.secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        dotsLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        dotsLabel.textColor = NSColor.secondaryLabelColor
        dotsLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [titleLabel, dotsLabel])
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)
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

    func display(at caretRect: CGRect?) {
        startAnimation()

        let totalSize = NSSize(width: 96, height: 24)
        let primaryScreenHeight = NSScreen.screens.first?.frame.height
            ?? (NSScreen.main?.frame.height ?? 1080)

        guard let caret = caretRect, !caret.isEmpty else {
            // No caret bounds available: show at bottom-right as fallback so
            // the user still sees that FixNow is running.
            let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let origin = CGPoint(
                x: screenFrame.maxX - totalSize.width - 24,
                y: screenFrame.minY + 24
            )
            setFrame(NSRect(origin: origin, size: totalSize), display: true)
            if !isVisible { orderFrontRegardless() }
            return
        }

        let caretBottomY = primaryScreenHeight - (caret.origin.y + caret.height)
        let y = caretBottomY - totalSize.height - 6
        let x = caret.origin.x + caret.width + 10
        let origin = CGPoint(x: x, y: y)

        setFrame(NSRect(origin: origin, size: totalSize), display: true)
        if !isVisible {
            orderFrontRegardless()
        }
    }

    func hide() {
        stopAnimation()
        orderOut(nil)
    }

    private func startAnimation() {
        stopAnimation()
        dotCount = 0
        dotsLabel.stringValue = "."
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.dotCount = (self.dotCount + 1) % 4
            let dots = String(repeating: ".", count: max(self.dotCount, 1))
            self.dotsLabel.stringValue = dots
        }
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
}
