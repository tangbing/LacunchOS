import AppKit

@MainActor
final class MenuBarController: NSObject {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private weak var launcherModel: LauncherModel?

    private override init() {}

    func configure(isVisible: Bool, launcherModel: LauncherModel) {
        self.launcherModel = launcherModel

        if isVisible {
            ensureStatusItem()
        } else {
            removeStatusItem()
        }
    }

    private func ensureStatusItem() {
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.image = NSImage(
                systemSymbolName: "square.grid.3x3",
                accessibilityDescription: "LaunchOS"
            )
            item.button?.imagePosition = .imageOnly
            statusItem = item
        }

        statusItem?.menu = makeMenu()
    }

    private func removeStatusItem() {
        guard let statusItem else {
            return
        }

        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "LaunchOS")

        menu.addItem(
            NSMenuItem(
                title: "显示/隐藏 LaunchOS",
                action: #selector(toggleLaunchOS),
                keyEquivalent: ""
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "刷新应用",
                action: #selector(refreshApps),
                keyEquivalent: ""
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "设置...",
                action: #selector(showSettings),
                keyEquivalent: ","
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "退出 LaunchOS",
                action: #selector(quitLaunchOS),
                keyEquivalent: "q"
            )
        )

        for item in menu.items {
            item.target = self
        }

        return menu
    }

    @objc private func toggleLaunchOS() {
        LauncherWindowController.toggleLauncher()
    }

    @objc private func refreshApps() {
        guard let launcherModel else {
            return
        }

        Task {
            await launcherModel.refreshApps()
        }
    }

    @objc private func showSettings() {
        SettingsWindowController.showSettings()
    }

    @objc private func quitLaunchOS() {
        NSApplication.shared.terminate(nil)
    }
}
