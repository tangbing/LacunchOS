import Foundation

struct LauncherSettings: Codable, Equatable, Sendable {
    var isCommandShiftLHotkeyEnabled = true
    var isF4HotkeyEnabled = true
    var isHotCornerEnabled = false
    var isLaunchAtLoginEnabled = false
    var showsMenuBarIcon = true
    var isFullScreenModeEnabled = false
    var backgroundStyle = LauncherBackgroundStyle.systemWallpaper
    var isWallpaperBlurred = true
    var glassMaterialStrength = 0.55
    var hotCorner = HotCorner.topRight
    var displayStrategy = LauncherDisplayStrategy.pointer

    init(
        isCommandShiftLHotkeyEnabled: Bool = true,
        isF4HotkeyEnabled: Bool = true,
        isHotCornerEnabled: Bool = false,
        isLaunchAtLoginEnabled: Bool = false,
        showsMenuBarIcon: Bool = true,
        isFullScreenModeEnabled: Bool = false,
        backgroundStyle: LauncherBackgroundStyle = .systemWallpaper,
        isWallpaperBlurred: Bool = true,
        glassMaterialStrength: Double = 0.55,
        hotCorner: HotCorner = .topRight,
        displayStrategy: LauncherDisplayStrategy = .pointer
    ) {
        self.isCommandShiftLHotkeyEnabled = isCommandShiftLHotkeyEnabled
        self.isF4HotkeyEnabled = isF4HotkeyEnabled
        self.isHotCornerEnabled = isHotCornerEnabled
        self.isLaunchAtLoginEnabled = isLaunchAtLoginEnabled
        self.showsMenuBarIcon = showsMenuBarIcon
        self.isFullScreenModeEnabled = isFullScreenModeEnabled
        self.backgroundStyle = backgroundStyle
        self.isWallpaperBlurred = isWallpaperBlurred
        self.glassMaterialStrength = glassMaterialStrength
        self.hotCorner = hotCorner
        self.displayStrategy = displayStrategy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        isCommandShiftLHotkeyEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .isCommandShiftLHotkeyEnabled
        ) ?? true
        isF4HotkeyEnabled = try container.decodeIfPresent(Bool.self, forKey: .isF4HotkeyEnabled) ?? true
        isHotCornerEnabled = try container.decodeIfPresent(Bool.self, forKey: .isHotCornerEnabled) ?? false
        isLaunchAtLoginEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .isLaunchAtLoginEnabled
        ) ?? false
        showsMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showsMenuBarIcon) ?? true
        isFullScreenModeEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .isFullScreenModeEnabled
        ) ?? false
        backgroundStyle = try container.decodeIfPresent(
            LauncherBackgroundStyle.self,
            forKey: .backgroundStyle
        ) ?? .systemWallpaper
        isWallpaperBlurred = try container.decodeIfPresent(Bool.self, forKey: .isWallpaperBlurred) ?? true
        glassMaterialStrength = try container.decodeIfPresent(
            Double.self,
            forKey: .glassMaterialStrength
        ) ?? 0.55
        hotCorner = try container.decodeIfPresent(HotCorner.self, forKey: .hotCorner) ?? .topRight
        displayStrategy = try container.decodeIfPresent(
            LauncherDisplayStrategy.self,
            forKey: .displayStrategy
        ) ?? .pointer
    }
}

enum LauncherBackgroundStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case systemWallpaper
    case frostedGlass

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .systemWallpaper:
            "系统壁纸"
        case .frostedGlass:
            "毛玻璃"
        }
    }
}

enum HotCorner: String, Codable, CaseIterable, Identifiable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .topLeft:
            String(localized: "Top Left")
        case .topRight:
            String(localized: "Top Right")
        case .bottomLeft:
            String(localized: "Bottom Left")
        case .bottomRight:
            String(localized: "Bottom Right")
        }
    }
}

enum LauncherDisplayStrategy: String, Codable, CaseIterable, Identifiable, Sendable {
    case pointer
    case main

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .pointer:
            String(localized: "Pointer Display")
        case .main:
            String(localized: "Main Display")
        }
    }

    var detail: String {
        switch self {
        case .pointer:
            String(localized: "Open LaunchOS on the display that currently contains the pointer.")
        case .main:
            String(localized: "Always open LaunchOS on the primary macOS display.")
        }
    }
}

enum HotCornerStatus: Equatable, Sendable {
    case disabled
    case monitoring

    var title: String {
        switch self {
        case .disabled:
            String(localized: "Disabled")
        case .monitoring:
            String(localized: "Active")
        }
    }

    var detail: String {
        switch self {
        case .disabled:
            String(localized: "Hot corner triggering is turned off.")
        case .monitoring:
            String(localized: "Move the pointer into the selected corner to toggle LaunchOS.")
        }
    }
}

enum HotkeyRegistrationState: Equatable, Sendable {
    case disabled
    case registered
    case conflict
    case failed(OSStatus)

    var title: String {
        switch self {
        case .disabled:
            String(localized: "Disabled")
        case .registered:
            String(localized: "Active")
        case .conflict:
            String(localized: "Conflict")
        case .failed:
            String(localized: "Unavailable")
        }
    }

    var detail: String {
        switch self {
        case .disabled:
            String(localized: "This shortcut is turned off.")
        case .registered:
            String(localized: "Ready to open or close LaunchOS.")
        case .conflict:
            String(localized: "Another app or system service is already using this shortcut.")
        case .failed(let status):
            String(localized: "Registration failed with status \(status).")
        }
    }
}
