import AppKit

enum LauncherWindowController {
    private static weak var launcherWindow: NSWindow?
    private static var displayStrategy = LauncherDisplayStrategy.pointer
    private static var isFullScreenModeEnabled = false
    private static var previousPresentationOptions: NSApplication.PresentationOptions?

    static func updateDisplayStrategy(_ strategy: LauncherDisplayStrategy) {
        displayStrategy = strategy
    }

    static func updateFullScreenMode(_ isEnabled: Bool) {
        isFullScreenModeEnabled = isEnabled

        guard let launcherWindow, launcherWindow.isVisible else {
            return
        }

        configure(launcherWindow)
    }

    static func showLauncher(on screen: NSScreen? = nil) {
        NSApp.activate(ignoringOtherApps: true)

        if let window = launcherWindow ?? NSApp.windows.first(where: { $0.canBecomeKey }) {
            configure(window, on: screen)
            applyLauncherPresentationOptions()
            window.makeKeyAndOrderFront(nil)
        }
    }

    static func hideLauncher() {
        if let launcherWindow {
            launcherWindow.orderOut(nil)
        } else {
            NSApp.keyWindow?.orderOut(nil)
        }

        restorePresentationOptions()
    }

    static func toggleLauncher(on screen: NSScreen? = nil) {
        if launcherWindow?.isVisible == true {
            hideLauncher()
        } else {
            showLauncher(on: screen)
        }
    }

    static func configure(_ window: NSWindow, on screen: NSScreen? = nil) {
        launcherWindow = window
        window.title = "LaunchOS"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.remove(.titled)
        window.styleMask.insert(.borderless)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = isFullScreenModeEnabled ? .screenSaver : .floating
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        window.isReleasedWhenClosed = false

        for button in [
            NSWindow.ButtonType.closeButton,
            .miniaturizeButton,
            .zoomButton
        ] {
            window.standardWindowButton(button)?.isHidden = true
        }

        if let screen = screen ?? DisplayService.targetScreen(for: displayStrategy) ?? window.screen {
            window.setFrame(launcherFrame(on: screen), display: true)
        }
    }

    private static func launcherFrame(on screen: NSScreen) -> NSRect {
        guard !isFullScreenModeEnabled else {
            return screen.frame
        }

        let frame = screen.frame
        let visibleFrame = screen.visibleFrame
        var launcherFrame = frame

        if visibleFrame.minX > frame.minX {
            launcherFrame.origin.x = visibleFrame.minX
            launcherFrame.size.width = frame.maxX - visibleFrame.minX
        } else if visibleFrame.maxX < frame.maxX {
            launcherFrame.size.width = visibleFrame.maxX - frame.minX
        } else if visibleFrame.minY > frame.minY {
            launcherFrame.origin.y = visibleFrame.minY
            launcherFrame.size.height = frame.maxY - visibleFrame.minY
        }

        return launcherFrame
    }

    private static func applyLauncherPresentationOptions() {
        if previousPresentationOptions == nil {
            previousPresentationOptions = NSApp.presentationOptions
        }

        NSApp.presentationOptions = isFullScreenModeEnabled ? [.hideDock, .hideMenuBar] : []
    }

    private static func restorePresentationOptions() {
        guard let previousPresentationOptions else {
            return
        }

        NSApp.presentationOptions = previousPresentationOptions
        self.previousPresentationOptions = nil
    }
}
