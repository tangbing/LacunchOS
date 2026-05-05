import AppKit

enum DisplayService {
    static var pointerScreen: NSScreen? {
        screen(containing: NSEvent.mouseLocation)
    }

    static func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { screen in
            screen.frame.contains(point)
        }
    }

    static func targetScreen(for strategy: LauncherDisplayStrategy) -> NSScreen? {
        switch strategy {
        case .pointer:
            pointerScreen ?? NSScreen.main
        case .main:
            NSScreen.main ?? pointerScreen
        }
    }
}
