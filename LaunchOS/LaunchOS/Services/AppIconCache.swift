import AppKit

@MainActor
enum AppIconCache {
    private static var icons: [String: NSImage] = [:]

    static func icon(for path: String) -> NSImage {
        if let icon = icons[path] {
            return icon
        }

        NSWorkspace.shared.noteFileSystemChanged(path)
        let icon = NSWorkspace.shared.icon(forFile: path)
        icons[path] = icon
        return icon
    }

    static func removeAll() {
        icons.removeAll()
    }
}
