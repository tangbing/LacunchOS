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
                            icon: AppIconCache.icon(for: app.path),
                            isEnabled: model.canReorderApps
                        ) {
                            model.beginDraggingFolderApp(app.id, in: folder.id)
                        } finishDragging: {
                            model.finishDragging()
                        } launch: {
                            model.launch(app)
                        } hoverDragging: { _ in
                            withAnimation(.snappy(duration: 0.16)) {
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
            .animation(reduceMotion ? nil : .snappy(duration: 0.20), value: model.openedFolderApps.map(\.id))
        }
        .padding(24)
        .frame(width: 740)
        .launchOSGlassSurface(cornerRadius: VisualStyle.panelRadius)
        .shadow(color: .black.opacity(0.22), radius: 28, y: 18)
        .background {
            FolderDragExitMonitorView(
                isEnabled: model.draggingSourceFolderID == folder.id,
                onExit: {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.24)) {
                        model.moveDraggingFolderAppToTopLevel()
                    }
                }
            )
        }
        .accessibilityElement(children: .contain)
    }
}

private struct FolderDragExitMonitorView: NSViewRepresentable {
    let isEnabled: Bool
    let onExit: () -> Void

    func makeNSView(context: Context) -> FolderDragExitMonitorNSView {
        let view = FolderDragExitMonitorNSView()
        view.isEnabled = isEnabled
        view.onExit = onExit
        return view
    }

    func updateNSView(_ nsView: FolderDragExitMonitorNSView, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.onExit = onExit

        if !isEnabled {
            nsView.resetExitState()
        }
    }
}

private final class FolderDragExitMonitorNSView: NSView {
    var isEnabled = false
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

        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    private func handle(_ event: NSEvent) {
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
