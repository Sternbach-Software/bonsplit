import AppKit
import SwiftUI
import Testing
@testable import Bonsplit

@Suite("Hint targets")
@MainActor
struct BonsplitHintTargetTests {
    @Test("Tabs and split action buttons carry hint targets named like them")
    func tabsAndButtonsCarryHintTargets() {
        _ = NSApplication.shared
        let controller = BonsplitController()
        controller.createTab(title: "hint probe one")
        controller.createTab(title: "hint probe two")
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = NSHostingView(rootView:
            BonsplitView(controller: controller) { _, _ in Color.clear }
        )
        for _ in 0..<5 {
            window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }

        let targets = Self.hintTargets(in: window.contentView)
        let titles = Set(targets.map(\.title))
        let tooltips = BonsplitConfiguration.SplitButtonTooltips.default
        for title in ["hint probe one", "hint probe two", tooltips.newTerminal, tooltips.splitRight] {
            #expect(titles.contains(title), "missing \(title) in \(titles.sorted())")
        }
        #expect(targets.allSatisfy { $0.hitTest(NSPoint(x: 1, y: 1)) == nil })
    }

    private static func hintTargets(in view: NSView?) -> [BonsplitHintTargetView] {
        guard let view else { return [] }
        return (view as? BonsplitHintTargetView).map { [$0] } ?? view.subviews.flatMap { hintTargets(in: $0) }
    }
}
