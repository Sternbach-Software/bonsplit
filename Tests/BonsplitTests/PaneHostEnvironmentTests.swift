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
        let newPane = try #require(controller.splitPane(orientation: .horizontal))
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
        var hosts: [NSView] = []
        for _ in 0..<40 where hosts.count < 2 {
            Self.settle(contentView)
            hosts = Self.paneHosts(in: contentView)
        }
        let host = try #require(hosts.first, "No pane host under: \(Self.tree(contentView))")

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

    /// cmux's crashing test splits a window's only pane. The root pane is
    /// hosted by `SinglePaneWrapper`, which SwiftUI dismantles when the root
    /// becomes a split; its host can still receive an update afterwards.
    @Test("The root pane host survives its pane turning into a split")
    func rootPaneHostAfterSplit() throws {
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
        var rootHost: NSView?
        for _ in 0..<40 where rootHost == nil {
            Self.settle(contentView)
            rootHost = Self.singlePaneHost(in: contentView)
        }
        let host = try #require(rootHost, "No root pane host under: \(Self.tree(contentView))")
        let firstPane = try #require(controller.focusedPaneId)

        _ = try #require(controller.splitPane(firstPane, orientation: .horizontal))
        Self.settle(contentView)
        // The dismantled root host still holds the first pane; change it.
        controller.createTab(title: "After split", inPane: firstPane)
        for pane in controller.internalController.rootNode.allPanes {
            pane.tabs.append(TabItem(title: "Extra", icon: nil))
        }
        let parkingWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        parkingWindow.isReleasedWhenClosed = false
        defer { parkingWindow.orderOut(nil) }
        if host.window == nil {
            host.frame = parkingWindow.contentView?.bounds ?? .zero
            parkingWindow.contentView?.addSubview(host)
            parkingWindow.orderFront(nil)
        }
        Self.settle(host)
        host.display()
        Self.settle(contentView)

        #expect(host.window != nil)
    }

    private static func singlePaneHost(in root: NSView) -> NSView? {
        if root is PaneDragContainerView {
            return root.subviews.first { String(describing: type(of: $0)).contains("HostingView") }
        }
        for subview in root.subviews {
            if let match = singlePaneHost(in: subview) { return match }
        }
        return nil
    }

    private static func settle(_ view: NSView?) {
        view?.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        view?.layoutSubtreeIfNeeded()
        view?.displayIfNeeded()
    }

    private static func tree(_ view: NSView, depth: Int = 0) -> String {
        guard depth < 12 else { return "" }
        return String(describing: type(of: view)) + "[" + view.subviews.map { tree($0, depth: depth + 1) }.joined(separator: ",") + "]"
    }

    private static func paneHosts(in root: NSView?) -> [NSView] {
        guard let root else { return [] }
        // Each split child is a SplitArrangedContainerView holding one pane's hosting view.
        if root is SplitArrangedContainerView {
            return root.subviews.filter { $0 is NSHostingView<AnyView> }
        }
        return root.subviews.flatMap { paneHosts(in: $0) }
    }
}
