import AppKit
import SwiftUI

struct FolderOverlayView: View {
    let folder: LauncherFolder
    let model: LauncherModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = Array(repeating: GridItem(.fixed(156), spacing: 18), count: 4)

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                Button {
                    model.requestRenameFolder(folder.id)
                } label: {
                    HStack(spacing: 8) {
                        Text(folder.name)
                            .font(.title2.weight(.semibold))
                            .lineLimit(1)

                        Image(systemName: "pencil")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .launcherFolderContextMenu(for: folder, model: model)

                Spacer()

                Button(action: model.closeFolder) {
                    Image(systemName: "xmark")
                        .font(.title3)
                }
                .launchOSGlassButton()
                .foregroundStyle(.secondary)
                .accessibilityLabel("Close Folder")
            }

            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(model.openedFolderApps) { app in
                    AppGridItemView(
                        app: app,
                        isSelected: false,
                        isDragging: model.draggingAppID == app.id && model.draggingSourceFolderID == folder.id,
                        canReorder: model.canReorderApps,
                        isFolderDropTarget: false,
                        iconRefreshToken: model.iconRefreshToken
                    ) {
                        model.launch(app)
                    }
                    .overlay {
                        NativeAppDragSourceView(
                            appID: app.id,
                            appURL: app.url,
                            icon: AppIconCache.icon(for: app.path),
                            isEnabled: model.canReorderApps
                        ) {
                            model.beginDraggingFolderApp(app.id, in: folder.id)
                        } finishDragging: {
                            model.finishDragging()
                        } cancelDragging: {
                            model.cancelDraggingRestoringLayout()
                        } launch: {
                            model.launch(app)
                        } updateDraggingPreview: { locationInWindow, cursorOffsetFromCenter in
                            model.updateDragPreview(
                                appID: app.id,
                                locationInWindow: locationInWindow,
                                cursorOffsetFromCenter: cursorOffsetFromCenter
                            )
                        } hoverDragging: { _ in
                            withAnimation(reorderAnimation) {
                                model.moveDraggingFolderApp(over: app.id, in: folder.id)
                            }
                        } performDraggingDrop: { _ in
                            model.finishDragging()
                        }
                        .frame(width: 156, height: 172)
                    }
                    .launcherAppContextMenu(for: app, model: model)
                }
            }
            .animation(reorderAnimation, value: model.openedFolderApps.map(\.id))
        }
        .padding(24)
        .frame(width: 740)
        .launchOSGlassSurface(cornerRadius: VisualStyle.panelRadius)
        .shadow(color: .black.opacity(0.22), radius: 28, y: 18)
        .background {
            FolderDragExitMonitorView(
                isEnabled: model.draggingSourceFolderID == folder.id,
                onOutsideClick: {
                    model.closeFolder()
                },
                onExit: {
                    withAnimation(reorderAnimation) {
                        model.moveDraggingFolderAppToTopLevel()
                    }
                }
            )
        }
        .accessibilityElement(children: .contain)
    }

    private var reorderAnimation: Animation? {
        reduceMotion ? nil : .interactiveSpring(response: 0.34, dampingFraction: 0.82, blendDuration: 0.04)
    }
}

private struct FolderDragExitMonitorView: NSViewRepresentable {
    let isEnabled: Bool
    let onOutsideClick: () -> Void
    let onExit: () -> Void

    func makeNSView(context: Context) -> FolderDragExitMonitorNSView {
        let view = FolderDragExitMonitorNSView()
        view.isEnabled = isEnabled
        view.onOutsideClick = onOutsideClick
        view.onExit = onExit
        return view
    }

    func updateNSView(_ nsView: FolderDragExitMonitorNSView, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.onOutsideClick = onOutsideClick
        nsView.onExit = onExit

        if !isEnabled {
            nsView.resetExitState()
        }
    }
}

private final class FolderDragExitMonitorNSView: NSView {
    var isEnabled = false
    var onOutsideClick: (() -> Void)?
    var onExit: (() -> Void)?

    private var dragMonitor: Any?
    private var hasExited = false
    private let exitMargin: CGFloat = 42

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            removeDragMonitor()
        } else {
            installDragMonitorIfNeeded()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    deinit {
        removeDragMonitor()
    }

    func resetExitState() {
        hasExited = false
    }

    private func installDragMonitorIfNeeded() {
        guard dragMonitor == nil else {
            return
        }

        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    private func handle(_ event: NSEvent) {
        if event.type == .leftMouseDown, event.window === window {
            let localPoint = convert(event.locationInWindow, from: nil)

            if !bounds.contains(localPoint) {
                onOutsideClick?()
            }

            return
        }

        guard
            isEnabled,
            !hasExited,
            event.type == .leftMouseDragged,
            event.window === window
        else {
            if event.type == .leftMouseUp {
                hasExited = false
            }
            return
        }

        let localPoint = convert(event.locationInWindow, from: nil)
        let expandedBounds = bounds.insetBy(dx: -exitMargin, dy: -exitMargin)

        guard !expandedBounds.contains(localPoint) else {
            return
        }

        hasExited = true
        onExit?()
    }

    private func removeDragMonitor() {
        guard let dragMonitor else {
            return
        }

        NSEvent.removeMonitor(dragMonitor)
        self.dragMonitor = nil
    }
}
