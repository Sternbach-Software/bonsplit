import AppKit
@testable import Bonsplit
import SwiftUI
import XCTest

// TEMPORARY PROBE for CMUXTERM-MACOS-41NN; not for merge.
@MainActor
final class ZZProbeHintTests: XCTestCase {
    private func log(_ s: String) { print("PROBE " + s); fflush(stdout) }

    func testProbePaneChromeRenderCost() throws {
        _ = NSApplication.shared
        let controller = BonsplitController(configuration: BonsplitConfiguration(appearance: .init(enableAnimations: false)))
        controller.tabShortcutHintsEnabled = true
        for i in 0..<3 { _ = controller.createTab(title: "Terminal \(i)", icon: "terminal.fill", kind: "terminal") }
        let p1 = try XCTUnwrap(controller.focusedPaneId)
        let p2 = try XCTUnwrap(controller.splitPane(p1, orientation: .horizontal))
        let p3 = try XCTUnwrap(controller.splitPane(p1, orientation: .vertical))
        let p4 = try XCTUnwrap(controller.splitPane(p2, orientation: .vertical))
        for p in [p2, p3, p4] { for i in 0..<3 { _ = controller.createTab(title: "T\(i)", icon: "terminal.fill", kind: "terminal", inPane: p) } }
        let hostingView = NSHostingView(rootView: BonsplitView(controller: controller) { _, _ in Color.clear } emptyPane: { _ in Color.clear })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        hostingView.frame = window.contentView!.bounds
        hostingView.autoresizingMask = [.width, .height]
        window.contentView!.addSubview(hostingView)
        window.makeKeyAndOrderFront(nil)
        func settle(_ seconds: Double) {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end {
                window.contentView?.layoutSubtreeIfNeeded()
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }
        }
        settle(1.0)
        log("panes=\(controller.allPaneIds.count) tabs=\(controller.allTabIds.count)")
        ProbeCounters.reset(); settle(2.0)
        log("idle2s \(ProbeCounters.summary)")

        for i in 0..<6 {
            ProbeCounters.reset()
            let t0 = CFAbsoluteTimeGetCurrent()
            UserDefaults.standard.set(i % 2 == 0, forKey: "shortcutHintAlwaysShow")
            window.contentView?.layoutSubtreeIfNeeded()
            let t1 = CFAbsoluteTimeGetCurrent()
            settle(0.5)
            log("hintToggle\(i) syncMs=\(String(format: "%.2f", (t1 - t0) * 1000)) \(ProbeCounters.summary)")
        }
        UserDefaults.standard.removeObject(forKey: "shortcutHintAlwaysShow")
        settle(0.3)

        for (name, pane) in [("focusP2", p2), ("focusP3", p3), ("focusP1", p1)] {
            ProbeCounters.reset()
            let t0 = CFAbsoluteTimeGetCurrent()
            controller.focusPane(pane)
            window.contentView?.layoutSubtreeIfNeeded()
            let t1 = CFAbsoluteTimeGetCurrent()
            settle(0.5)
            log("\(name) syncMs=\(String(format: "%.2f", (t1 - t0) * 1000)) \(ProbeCounters.summary)")
        }

        // Title change in one tab of one pane (a terminal title update).
        let someTab = try XCTUnwrap(controller.tabs(inPane: p4).first)
        for i in 0..<3 {
            ProbeCounters.reset()
            let t0 = CFAbsoluteTimeGetCurrent()
            controller.updateTab(someTab.id, title: "Renamed \(i)")
            window.contentView?.layoutSubtreeIfNeeded()
            let t1 = CFAbsoluteTimeGetCurrent()
            settle(0.3)
            log("titleChange\(i) syncMs=\(String(format: "%.2f", (t1 - t0) * 1000)) \(ProbeCounters.summary)")
        }

        // Window resize (divider geometry propagates through every split).
        for (i, w) in [1300.0, 1400.0].enumerated() {
            ProbeCounters.reset()
            let t0 = CFAbsoluteTimeGetCurrent()
            window.setContentSize(NSSize(width: w, height: 900))
            window.contentView?.layoutSubtreeIfNeeded()
            let t1 = CFAbsoluteTimeGetCurrent()
            settle(0.5)
            log("resize\(i) syncMs=\(String(format: "%.2f", (t1 - t0) * 1000)) \(ProbeCounters.summary)")
        }

        // Steady-state per-TabItemView body cost.
        ProbeCounters.reset()
        let t0 = CFAbsoluteTimeGetCurrent()
        for i in 0..<40 {
            UserDefaults.standard.set(i % 2 == 0, forKey: "shortcutHintAlwaysShow")
            window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.001))
        }
        let dt = CFAbsoluteTimeGetCurrent() - t0
        UserDefaults.standard.removeObject(forKey: "shortcutHintAlwaysShow")
        log("toggle40 ms=\(String(format: "%.1f", dt * 1000)) \(ProbeCounters.summary) usPerTabItemBody=\(String(format: "%.1f", dt * 1e6 / Double(max(1, ProbeCounters.tabItemBody))))")
        ProbeCounters.reset(); settle(2.0)
        log("idleEnd2s \(ProbeCounters.summary)")
    }
}
