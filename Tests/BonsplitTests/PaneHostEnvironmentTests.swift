import AppKit
import SwiftUI
import Testing
@testable import Bonsplit

/// A new split defers its initial divider position to the next run loop turn.
/// If the window closes first, that deferred work used to lay out the split's
/// pane hosts after they had left `BonsplitView`, and their views trapped on
/// `@Environment(BonsplitController.self)` (manaflow-ai/cmux app-host crash,
/// macOS 27.0.1).
@Suite("Pane host environment")
@MainActor
struct PaneHostEnvironmentTests {
    @Test("Closing the window before a new split's deferred divider apply does not trap")
    func splitTornDownBeforeDeferredDividerApply() throws {
        _ = NSApplication.shared
        let controller = BonsplitController()
        controller.createTab(title: "First")
        let hostingView = NSHostingView(rootView:
            BonsplitView(controller: controller) { _, _ in Color.clear } emptyPane: { _ in Color.clear }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil) }
        let contentView = try #require(window.contentView)
        hostingView.frame = contentView.bounds
        hostingView.autoresizingMask = [.width, .height]
        contentView.addSubview(hostingView)
        window.makeKeyAndOrderFront(nil)
        contentView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        let firstPane = try #require(controller.focusedPaneId)
        _ = try #require(controller.splitPane(firstPane, orientation: .horizontal))
        // Mount the split in this turn: makeSplitView queues its initial
        // divider apply for the next turn.
        contentView.layoutSubtreeIfNeeded()
        let splitView = try #require(Self.firstSplitView(in: hostingView))

        // Tear the window down before that turn, the way cmux closes a window
        // right after a split.
        hostingView.removeFromSuperview()
        window.close()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        #expect(splitView.window == nil)
    }

    private static func firstSplitView(in root: NSView) -> NSSplitView? {
        if let split = root as? NSSplitView { return split }
        for subview in root.subviews {
            if let match = firstSplitView(in: subview) { return match }
        }
        return nil
    }
}
