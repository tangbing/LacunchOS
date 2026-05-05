import ServiceManagement

@MainActor
enum LoginItemService {
    static func configure(isEnabled: Bool) {
        do {
            if isEnabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // The setting remains saved; debug builds outside /Applications may not be eligible.
        }
    }
}
