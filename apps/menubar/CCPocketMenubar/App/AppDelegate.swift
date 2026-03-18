import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private let appViewModel = AppViewModel()

    /// Monitor for clicks outside the panel to dismiss it
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = Self.createMenuBarIcon()
            button.image?.isTemplate = true
            button.action = #selector(togglePanel)
            button.target = self
        }

        // Create a borderless, floating panel
        let contentView = NSHostingView(
            rootView: PopoverContentView(viewModel: appViewModel)
        )

        let panelSize = NSSize(width: 380, height: 500)

        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.contentView = contentView
        panel.isReleasedWhenClosed = false

        // Glass effect handles corner rounding; ensure layer is available
        panel.contentView?.wantsLayer = true
    }

    @objc private func togglePanel() {
        if panel.isVisible {
            closePanel()
        } else {
            openPanel()
        }
    }

    private func openPanel() {
        guard let button = statusItem.button,
              let buttonWindow = button.window else { return }

        // Position the panel below the status bar button, right-aligned
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)

        let panelWidth = panel.frame.width
        let x = screenRect.midX - panelWidth / 2
        let y = screenRect.minY - panel.frame.height - 4

        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFrontRegardless()

        // Monitor for outside clicks to dismiss
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.closePanel()
        }
    }

    private func closePanel() {
        panel.orderOut(nil)

        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: - Menu Bar Icon (drawn in code)

    /// Create "cc" logo icon for the menu bar. Drawn programmatically to avoid
    /// asset catalog issues. Returns a template image at 18×18 pt (Retina-ready).
    private static func createMenuBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()

            // Left C: arc with gap on the right
            let leftC = NSBezierPath()
            let cx1: CGFloat = 6.8, cy1: CGFloat = 7.5
            let outerR1: CGFloat = 5.5, innerR1: CGFloat = 3.5
            let gapHalf1: CGFloat = 52.0  // degrees

            // Outer arc (counterclockwise from bottom-gap to top-gap)
            leftC.appendArc(
                withCenter: NSPoint(x: cx1, y: cy1),
                radius: outerR1,
                startAngle: -gapHalf1,
                endAngle: gapHalf1,
                clockwise: true
            )
            // Inner arc back (clockwise)
            leftC.appendArc(
                withCenter: NSPoint(x: cx1, y: cy1),
                radius: innerR1,
                startAngle: gapHalf1,
                endAngle: -gapHalf1,
                clockwise: false
            )
            leftC.close()
            leftC.fill()

            // Right C: arc with gap on the left (mirrored)
            let rightC = NSBezierPath()
            let cx2: CGFloat = 11.2, cy2: CGFloat = 10.5
            let outerR2: CGFloat = 5.5, innerR2: CGFloat = 3.5
            let gapHalf2: CGFloat = 52.0

            // Outer arc (gap faces left = 180°)
            rightC.appendArc(
                withCenter: NSPoint(x: cx2, y: cy2),
                radius: outerR2,
                startAngle: 180 - gapHalf2,
                endAngle: 180 + gapHalf2,
                clockwise: true
            )
            // Inner arc back
            rightC.appendArc(
                withCenter: NSPoint(x: cx2, y: cy2),
                radius: innerR2,
                startAngle: 180 + gapHalf2,
                endAngle: 180 - gapHalf2,
                clockwise: false
            )
            rightC.close()
            rightC.fill()

            return true
        }
        image.isTemplate = true
        return image
    }
}
