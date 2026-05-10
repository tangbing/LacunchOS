import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppReorderDropDelegate: DropDelegate {
    let targetItem: LauncherItem
    let model: LauncherModel

    func validateDrop(info: DropInfo) -> Bool {
        model.canReorderApps && model.draggingAppID != nil
    }

    func dropEntered(info: DropInfo) {
        updateDropState(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateDropState(info: info)
        return DropProposal(operation: model.canReorderApps ? .move : .cancel)
    }

    func dropExited(info: DropInfo) {
        model.clearFolderDropTarget(for: targetItem.id)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard model.canReorderApps else {
            model.finishDragging(saveChanges: false)
            return false
        }

        if shouldCreateFolder(info: info) {
            withAnimation(.snappy(duration: 0.18)) {
                model.groupDraggingApp(with: targetItem)
            }
        }

        model.finishDragging()
        return true
    }

    private func updateDropState(info: DropInfo) {
        guard model.canReorderApps else {
            return
        }

        if isFolderDrop(info: info) {
            model.previewFolderDrop(on: targetItem.id)
        } else {
            model.clearFolderDropTarget(for: targetItem.id)
            withAnimation(.snappy(duration: 0.16)) {
                model.moveDraggingApp(over: targetItem.id)
            }
        }
    }

    private func isFolderDrop(info: DropInfo) -> Bool {
        guard model.canGroupDraggingApp(with: targetItem) else {
            return false
        }

        let location = info.location
        return CGRect(x: 12, y: 0, width: 132, height: 132).contains(location)
    }

    private func shouldCreateFolder(info: DropInfo) -> Bool {
        model.folderDropTargetID == targetItem.id || isFolderDrop(info: info)
    }
}

struct AppGridDropDelegate: DropDelegate {
    let model: LauncherModel

    func validateDrop(info: DropInfo) -> Bool {
        model.canReorderApps && model.draggingAppID != nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: model.canReorderApps ? .move : .cancel)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard model.canReorderApps else {
            model.finishDragging(saveChanges: false)
            return false
        }

        withAnimation(.snappy(duration: 0.18)) {
            model.moveDraggingAppToEnd()
        }
        model.finishDragging()
        return true
    }
}

struct NativeAppDragSourceView: NSViewRepresentable {
    let appID: AppRecord.ID
    let icon: NSImage
    let isEnabled: Bool
    let beginDragging: () -> Void
    let finishDragging: () -> Void
    let launch: () -> Void
    let hoverDragging: (CGPoint) -> Void
    let performDraggingDrop: (CGPoint) -> Void

    func makeNSView(context: Context) -> NativeAppDragSourceNSView {
        let view = NativeAppDragSourceNSView()
        view.appID = appID
        view.icon = icon
        view.isEnabled = isEnabled
        view.beginDragging = beginDragging
        view.finishDragging = finishDragging
        view.launch = launch
        view.hoverDragging = hoverDragging
        view.performDraggingDrop = performDraggingDrop
        return view
    }

    func updateNSView(_ nsView: NativeAppDragSourceNSView, context: Context) {
        nsView.appID = appID
        nsView.icon = icon
        nsView.isEnabled = isEnabled
        nsView.beginDragging = beginDragging
        nsView.finishDragging = finishDragging
        nsView.launch = launch
        nsView.hoverDragging = hoverDragging
        nsView.performDraggingDrop = performDraggingDrop
    }
}

final class NativeAppDragSourceNSView: NSView, NSDraggingSource {
    private static var activeDragAppID: AppRecord.ID?
    private static var isManualDragActive = false
    private static var didHandleManualDrop = false

    var appID = ""
    var icon = NSImage()
    var isEnabled = false
    var beginDragging: (() -> Void)?
    var finishDragging: (() -> Void)?
    var launch: (() -> Void)?
    var hoverDragging: ((CGPoint) -> Void)?
    var performDraggingDrop: ((CGPoint) -> Void)?

    private var dragEventMonitor: Any?
    private var mouseDownLocationInWindow: CGPoint?
    private var isDraggingSessionActive = false
    private let dragThreshold: CGFloat = 4

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            removeDragEventMonitor()
        } else {
            installDragEventMonitorIfNeeded()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard
            isEnabled,
            bounds.contains(point)
        else {
            return nil
        }

        switch NSApp.currentEvent?.type {
        case .leftMouseDown, .leftMouseDragged, nil:
            return self
        default:
            return nil
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    deinit {
        removeDragEventMonitor()
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .move
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        Self.clearActiveDrag()
        isDraggingSessionActive = false
        mouseDownLocationInWindow = nil
        finishDragging?()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else {
            return
        }

        mouseDownLocationInWindow = event.locationInWindow
        isDraggingSessionActive = false
    }

    override func mouseDragged(with event: NSEvent) {
        if Self.isManualDragActive {
            updateManualDrag(with: event)
        } else {
            startManualDraggingIfNeeded(with: event, allowsImmediateStart: false)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if Self.isManualDragActive {
            finishManualDragIfNeeded(with: event)
            return
        }

        defer {
            mouseDownLocationInWindow = nil
            isDraggingSessionActive = false
        }

        guard isEnabled else {
            return
        }

        launch?()
    }

    private func installDragEventMonitorIfNeeded() {
        guard dragEventMonitor == nil else {
            return
        }

        dragEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.handleDragMonitorEvent(event)
            return event
        }
    }

    private func handleDragMonitorEvent(_ event: NSEvent) {
        guard event.window === window else {
            return
        }

        if Self.isManualDragActive {
            switch event.type {
            case .leftMouseDragged:
                updateManualDrag(with: event)
            case .leftMouseUp:
                finishManualDragIfNeeded(with: event)
            default:
                break
            }
            return
        }

        if event.type == .leftMouseDragged {
            startManualDraggingIfNeeded(with: event, allowsImmediateStart: true)
        }
    }

    private func startManualDraggingIfNeeded(with event: NSEvent, allowsImmediateStart: Bool) {
        guard
            isEnabled,
            !isDraggingSessionActive,
            Self.activeDragAppID == nil || Self.activeDragAppID == appID,
            event.type == .leftMouseDragged,
            let window,
            event.window === window
        else {
            return
        }

        if mouseDownLocationInWindow == nil {
            guard allowsImmediateStart, containsWindowLocation(event.locationInWindow) else {
                return
            }

            mouseDownLocationInWindow = event.locationInWindow
            startManualDragging(with: event)
            return
        }

        guard let mouseDownLocationInWindow else {
            return
        }

        let deltaX = event.locationInWindow.x - mouseDownLocationInWindow.x
        let deltaY = event.locationInWindow.y - mouseDownLocationInWindow.y

        guard hypot(deltaX, deltaY) >= dragThreshold else {
            return
        }

        startManualDragging(with: event)
    }

    private func updateManualDrag(with event: NSEvent) {
        guard
            isEnabled,
            Self.isManualDragActive,
            Self.activeDragAppID != appID,
            containsWindowLocation(event.locationInWindow)
        else {
            return
        }

        hoverDragging?(convert(event.locationInWindow, from: nil))
    }

    private func finishManualDragIfNeeded(with event: NSEvent) {
        guard Self.isManualDragActive, let activeDragAppID = Self.activeDragAppID else {
            return
        }

        if activeDragAppID != appID, containsWindowLocation(event.locationInWindow) {
            Self.didHandleManualDrop = true
            performDraggingDrop?(convert(event.locationInWindow, from: nil))
            Self.clearActiveDrag()
            mouseDownLocationInWindow = nil
            isDraggingSessionActive = false
            return
        }

        guard activeDragAppID == appID else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard
                let self,
                Self.isManualDragActive,
                Self.activeDragAppID == self.appID,
                !Self.didHandleManualDrop
            else {
                return
            }

            self.finishDragging?()
            Self.clearActiveDrag()
            self.mouseDownLocationInWindow = nil
            self.isDraggingSessionActive = false
        }
    }

    private func containsWindowLocation(_ locationInWindow: CGPoint) -> Bool {
        bounds.contains(convert(locationInWindow, from: nil))
    }

    private func startManualDragging(with event: NSEvent) {
        guard !appID.isEmpty else {
            return
        }

        Self.activeDragAppID = appID
        Self.isManualDragActive = true
        Self.didHandleManualDrop = false
        isDraggingSessionActive = true
        beginDragging?()
    }

    private func removeDragEventMonitor() {
        guard let dragEventMonitor else {
            return
        }

        NSEvent.removeMonitor(dragEventMonitor)
        self.dragEventMonitor = nil
    }

    private static func clearActiveDrag() {
        activeDragAppID = nil
        isManualDragActive = false
        didHandleManualDrop = false
    }
}
