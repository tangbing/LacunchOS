import AppKit
import SwiftUI

@MainActor
enum SettingsWindowController {
    private static var window: NSWindow?
    private static weak var settingsStore: SettingsStore?
    private static weak var launcherModel: LauncherModel?
    private static weak var hotkeyService: HotkeyService?
    private static weak var hotCornerService: HotCornerService?

    static func configure(
        settingsStore: SettingsStore,
        launcherModel: LauncherModel,
        hotkeyService: HotkeyService,
        hotCornerService: HotCornerService
    ) {
        self.settingsStore = settingsStore
        self.launcherModel = launcherModel
        self.hotkeyService = hotkeyService
        self.hotCornerService = hotCornerService
    }

    static func showSettings() {
        guard
            let settingsStore,
            let launcherModel,
            let hotkeyService,
            let hotCornerService
        else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)

        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let rootView = SettingsView(
            settingsStore: settingsStore,
            launcherModel: launcherModel,
            hotkeyService: hotkeyService,
            hotCornerService: hotCornerService
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 720),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = String(localized: "LaunchOS Settings")
        window.contentView = NSHostingView(rootView: rootView)
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }
}
