import AppKit
import SwiftUI
import Testing
@testable import Bonsplit

/// A pane's hosting view is its own `NSHostingView`. While it sits under
/// `BonsplitView` it inherits the controllers its views read from the
/// environment; once it is detached (a window closing, a pane turning into a
/// split) it must still be able to update without trapping on
/// `@Environment(BonsplitController.self)`.
@Suite("Pane host environment")
@MainActor
struct PaneHostEnvironmentTests {
    @Test("A detached pane host updates without the BonsplitView environment")
    func detachedPaneHostUpdates() throws {
        _ = NSApplication.shared
        let controller = BonsplitController()
        controller.createTab(title: "First")
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil) }
        window.contentView = NSHostingView(rootView:
            BonsplitView(controller: controller) { _, _ in Color.clear }
        )
        window.makeKeyAndOrderFront(nil)
        Self.settle(window.contentView)
        let newPane = try #require(controller.splitPane(orientation: .horizontal))
        var hosts: [NSView] = []
        for _ in 0..<40 where hosts.count < 2 {
            Self.settle(window.contentView)
            hosts = Self.paneHosts(in: window.contentView)
        }
        let host = try #require(hosts.first, "The split should mount a hosting view per pane")
        let detachedWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        detachedWindow.isReleasedWhenClosed = false
        defer { detachedWindow.orderOut(nil) }
        host.removeFromSuperview()
        host.frame = detachedWindow.contentView?.bounds ?? .zero
        detachedWindow.contentView?.addSubview(host)
        detachedWindow.orderFront(nil)

        // Invalidate the panes so the detached host re-evaluates its views.
        controller.createTab(title: "After detach", inPane: newPane)
        for pane in controller.internalController.rootNode.allPanes {
            pane.tabs.append(TabItem(title: "Extra", icon: nil))
        }
        Self.settle(detachedWindow.contentView)
        host.display()

        #expect(host.window === detachedWindow)
    }

    private static func settle(_ view: NSView?) {
        view?.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        view?.layoutSubtreeIfNeeded()
        view?.displayIfNeeded()
    }

    private static func paneHosts(in root: NSView?) -> [NSView] {
        guard let root else { return [] }
        let isPaneHost = String(describing: type(of: root)).hasPrefix("NonDraggableHostingView")
        return (isPaneHost ? [root] : []) + root.subviews.flatMap { paneHosts(in: $0) }
    }
}
