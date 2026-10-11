import AppKit

/// AppKit bridge that keeps one authoritative pointer-to-index calculation per strip.
@MainActor
final class TabBarDropDestinationNSView: NSView {
    weak var pane: PaneState?
    weak var bonsplitController: BonsplitController?
    weak var splitViewController: SplitViewController?
    weak var geometryRegistry: TabBarItemGeometryRegistry?
    var onIndicatorIndexChanged: ((Int?) -> Void)?
    /// Whether a drop lands at once instead of settling (tests set it).
    var reducesMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private let dropIndexResolver: TabDropIndexResolver
    private var presentedIndicatorIndex: Int?

    override init(frame frameRect: NSRect) {
        dropIndexResolver = TabDropIndexResolver()
        super.init(frame: frameRect)
        registerForDraggedTypes([
            TabBarDropHandler.tabTransferPasteboardType,
            .fileURL,
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard super.hitTest(point) === self else { return nil }
        let dragPasteboard = NSPasteboard(name: .drag)
        let handler = makeHandler()
        guard Self.shouldCaptureHitTest(
            eventType: NSApp.currentEvent?.type,
            pasteboardTypes: dragPasteboard.types,
            hasLocalTabDrag: handler?.hasLiveTabDrag == true
        ), handler?.operation(for: dragPasteboard) != [] else {
            return nil
        }
        return self
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        updateDrag(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        updateDrag(sender)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        clearDropState()
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        updateDrag(sender) != []
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        defer { clearDropState() }
        guard let handler = makeHandler(),
              let targetIndex = insertionIndex(for: sender) else {
            return false
        }
        // Read from the strip before the move reflows it.
        let before = settleSnapshot(for: sender)
        guard handler.performDrop(from: sender.draggingPasteboard, at: targetIndex) else { return false }
        if let before, let slot = settleSlot(after: before) {
            // AppKit slides the drag image into the slot; the tab shows there
            // when the session ends (SplitViewController.beginTabSettle).
            sender.animatesToDestination = true
            sender.enumerateDraggingItems(options: [], for: self, classes: [NSPasteboardItem.self], searchOptions: [:]) { item, _, _ in
                item.draggingFrame = slot
            }
            splitViewController?.beginTabSettle(before.tabId)
        }
        return true
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        clearDropState()
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        clearDropState()
    }

    /// The strip as a drop found it: the dragged tab, where it was in this
    /// strip (nil from another pane), its width and every tab's frame here.
    private struct SettleSnapshot {
        let tabId: UUID
        let source: Int?
        let width: CGFloat
        let frames: [CGRect?]
    }

    /// Nil when the drop lands at once: not a tab dragged from this app,
    /// Reduce Motion, a strip whose tabs have no frames.
    private func settleSnapshot(for sender: any NSDraggingInfo) -> SettleSnapshot? {
        guard !reducesMotion(), let pane, let geometryRegistry,
              sender.draggingPasteboard.types?.contains(TabBarDropHandler.tabTransferPasteboardType) == true,
              let session = splitViewController?.tabDragSession else { return nil }
        let frames = pane.tabs.map { geometryRegistry.frame(for: $0.id, in: self) }
        let source = session.sourcePaneId == pane.id ? pane.tabs.firstIndex(where: { $0.id == session.tab.id }) : nil
        var width: CGFloat = 0
        if let source {
            width = frames[source]?.width ?? 0
        } else {
            sender.enumerateDraggingItems(options: [], for: self, classes: [NSPasteboardItem.self], searchOptions: [:]) { item, _, stop in
                width = item.draggingFrame.width
                stop.pointee = true
            }
        }
        guard width > 0 else { return nil }
        return SettleSnapshot(tabId: session.tab.id, source: source, width: width, frames: frames)
    }

    /// The slot, in this view, of the tab's place after the drop (as the
    /// pane placed it, pinned tabs first), measured on the strip before the
    /// drop. Nil when it is not fully in view: the strip scrolls to reveal it.
    private func settleSlot(after before: SettleSnapshot) -> NSRect? {
        guard let pane, let landed = pane.tabs.firstIndex(where: { $0.id == before.tabId }),
              let row = before.frames.lazy.compactMap({ $0 }).first else { return nil }
        let frames = before.frames
        let minX: CGFloat
        if let source = before.source, landed > source {
            // The tabs between move over by its width.
            guard let end = frames[landed] else { return nil }
            minX = end.maxX - before.width
        } else if landed < frames.count {
            guard let at = frames[landed] else { return nil }
            minX = at.minX
        } else {
            guard let last = frames.last ?? nil else { return nil }
            minX = last.maxX
        }
        let slot = NSRect(x: minX, y: row.minY, width: before.width, height: row.height)
        let visible = NSRect(x: bounds.minX, y: bounds.minY,
                             width: bounds.width - (geometryRegistry?.trailingObscuredWidth ?? 0), height: bounds.height)
        return visible.contains(slot) ? slot : nil
    }

    static func shouldCaptureHitTest(
        eventType: NSEvent.EventType?,
        pasteboardTypes: [NSPasteboard.PasteboardType]?,
        hasLocalTabDrag: Bool = false
    ) -> Bool {
        let hasSupportedPasteboardType = pasteboardTypes?.contains(
            TabBarDropHandler.tabTransferPasteboardType
        ) == true || pasteboardTypes?.contains(.fileURL) == true
        guard hasLocalTabDrag || hasSupportedPasteboardType else {
            return false
        }
        // NSPasteboard(name: .drag) retains its advertised types after a drag
        // ends. A passive hit test must therefore be owned by the live local
        // tab-drag session; otherwise stale file/tab types can cover the tab
        // hit regions and swallow ordinary hover/cursor events.
        guard let eventType else { return hasLocalTabDrag }
        switch eventType {
        case .leftMouseDragged:
            // External Finder and cross-process tab drags arrive through the
            // AppKit drag event even though they have no local tab state.
            return true
        case .leftMouseUp,
             .mouseMoved,
             .cursorUpdate,
             .periodic,
             .appKitDefined,
             .applicationDefined,
             .systemDefined:
            return hasLocalTabDrag
        default:
            return false
        }
    }

    private func updateDrag(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard let handler = makeHandler(),
              let targetIndex = insertionIndex(for: sender) else {
            clearDropState()
            return []
        }
        let operation = handler.operation(for: sender.draggingPasteboard)
        guard operation != [] else {
            clearDropState()
            return []
        }
        presentIndicator(at: handler.indicatorIndex(for: targetIndex))
        return operation
    }

    private func insertionIndex(for sender: any NSDraggingInfo) -> Int? {
        guard let pane, let geometryRegistry else { return nil }
        let indexedFrames = pane.tabs.enumerated().compactMap { index, tab -> TabDropIndexResolver.IndexedFrame? in
            guard let frame = geometryRegistry.frame(for: tab.id, in: self) else { return nil }
            return TabDropIndexResolver.IndexedFrame(index: index, frame: frame)
        }
        return dropIndexResolver.insertionIndex(
            at: convert(sender.draggingLocation, from: nil),
            in: bounds,
            indexedTabFrames: indexedFrames,
            tabCount: pane.tabs.count
        )
    }

    private func makeHandler() -> TabBarDropHandler? {
        guard let pane, let bonsplitController, let splitViewController else { return nil }
        return TabBarDropHandler(
            pane: pane,
            bonsplitController: bonsplitController,
            splitViewController: splitViewController
        )
    }

    private func presentIndicator(at index: Int?) {
        guard presentedIndicatorIndex != index else { return }
        presentedIndicatorIndex = index
        onIndicatorIndexChanged?(index)
    }

    private func clearDropState() {
        presentIndicator(at: nil)
    }
}
