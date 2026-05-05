import AppKit
import SwiftUI

@main
struct LaunchOSApp: App {
    @State private var launcherModel = LauncherModel()
    @State private var settingsStore = SettingsStore()
    @State private var hotkeyService = HotkeyService()
    @State private var hotCornerService = HotCornerService()

    var body: some Scene {
        WindowGroup {
            ContentView(model: launcherModel, settingsStore: settingsStore)
                .background(LauncherWindowAccessor())
                .onAppear {
                    configureApplicationIcon()
                    configureSettingsWindow()
                    configureSystemServices()
                    LauncherWindowController.showLauncher()
                }
                .onChange(of: settingsStore.settings) {
                    configureSystemServices()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandGroup(replacing: .appSettings) {
                Button("设置...") {
                    SettingsWindowController.showSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandMenu("LaunchOS") {
                Button("显示/隐藏 LaunchOS") {
                    LauncherWindowController.toggleLauncher()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("刷新应用") {
                    Task {
                        await launcherModel.refreshApps()
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

    }

    private func configureSystemServices() {
        LoginItemService.configure(isEnabled: settingsStore.settings.isLaunchAtLoginEnabled)
        MenuBarController.shared.configure(
            isVisible: settingsStore.settings.showsMenuBarIcon,
            launcherModel: launcherModel
        )
        LauncherWindowController.updateDisplayStrategy(settingsStore.settings.displayStrategy)
        LauncherWindowController.updateFullScreenMode(settingsStore.settings.isFullScreenModeEnabled)
        hotkeyService.configure(settings: settingsStore.settings) { _ in
            LauncherWindowController.toggleLauncher(
                on: DisplayService.targetScreen(for: settingsStore.settings.displayStrategy)
            )
        }
        hotCornerService.configure(settings: settingsStore.settings) {
            LauncherWindowController.toggleLauncher(
                on: DisplayService.targetScreen(for: settingsStore.settings.displayStrategy)
            )
        }
    }

    private func configureSettingsWindow() {
        SettingsWindowController.configure(
            settingsStore: settingsStore,
            launcherModel: launcherModel,
            hotkeyService: hotkeyService,
            hotCornerService: hotCornerService
        )
    }

    private func configureApplicationIcon() {
        if let icon = NSImage(named: "LaunchOSAboutIcon") {
            NSApp.applicationIconImage = icon
        }
    }
}
