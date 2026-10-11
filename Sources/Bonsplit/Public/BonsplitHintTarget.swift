import AppKit
import SwiftUI

/// Names a tab bar control for a host's keyboard hint mode: a transparent,
/// click-through view at the control's frame. In process a SwiftUI host shows
/// its controls only as unknown accessibility elements, so a host walking its
/// window finds this view among the subviews instead. Clipped by the tab
/// strip's scroll view like the control it marks (read its `visibleRect`).
public final class BonsplitHintTargetView: NSView {
    /// The control's name: a tab's title or a button's tooltip.
    public internal(set) var title = ""

    override public func hitTest(_ point: NSPoint) -> NSView? { nil }
    override public func isAccessibilityElement() -> Bool { false }
}

private struct BonsplitHintTarget: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> BonsplitHintTargetView {
        BonsplitHintTargetView(frame: .zero)
    }

    func updateNSView(_ view: BonsplitHintTargetView, context: Context) {
        view.title = title
    }
}

extension View {
    /// Marks this control for a host's hint mode, named `title`.
    func bonsplitHintTarget(_ title: String) -> some View {
        background(BonsplitHintTarget(title: title))
    }
}
