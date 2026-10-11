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
        let settle = settleSlot(for: sender, at: targetIndex)
        guard handler.performDrop(from: sender.draggingPasteboard, at: targetIndex) else { return false }
        if let settle {
            // AppKit slides the drag image into the slot; the tab shows there
            // when the session ends (SplitViewController.beginTabSettle).
            sender.animatesToDestination = true
            sender.enumerateDraggingItems(options: [], for: self, classes: [NSPasteboardItem.self], searchOptions: [:]) { item, _, _ in
                item.draggingFrame = settle.frame
            }
            splitViewController?.beginTabSettle(settle.tabId)
        }
        return true
    }

    /// The slot, in this view, that the dragged tab takes when dropped at
    /// `index`: nil when the drop lands at once (not a tab drag from this
    /// app, Reduce Motion, a slot whose tabs have no frames).
    private func settleSlot(for sender: any NSDraggingInfo, at index: Int) -> (tabId: UUID, frame: NSRect)? {
        guard !reducesMotion(), let pane, let geometryRegistry,
              let session = splitViewController?.tabDragSession else { return nil }
        let frames = pane.tabs.map { geometryRegistry.frame(for: $0.id, in: self) }
        guard let row = frames.lazy.compactMap({ $0 }).first else { return nil }
        let minX: CGFloat
        let width: CGFloat
        if session.sourcePaneId == pane.id,
           let source = pane.tabs.firstIndex(where: { $0.id == session.tab.id }),
           let own = frames[source] {
            // The tabs between move over by its width.
            width = own.width
            if index > source {
                guard let before = frames[index - 1] else { return nil }
                minX = before.maxX - width
            } else {
                guard let at = frames[index] else { return nil }
                minX = at.minX
            }
        } else {
            // From another pane: the slot opens where the indicator showed.
            var imageWidth: CGFloat = 0
            sender.enumerateDraggingItems(options: [], for: self, classes: [NSPasteboardItem.self], searchOptions: [:]) { item, _, stop in
                imageWidth = item.draggingFrame.width
                stop.pointee = true
            }
            guard imageWidth > 0 else { return nil }
            width = imageWidth
            if index < frames.count {
                guard let at = frames[index] else { return nil }
                minX = at.minX
            } else {
                guard let last = frames.last ?? nil else { return nil }
                minX = last.maxX
            }
        }
        return (session.tab.id, NSRect(x: minX, y: row.minY, width: width, height: row.height))
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        clearDropState()
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        clearDropState()
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
