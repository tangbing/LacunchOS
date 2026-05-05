import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    var settings: LauncherSettings {
        didSet {
            save()
        }
    }

    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private let key = "launcherSettings"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        settings = Self.load(from: userDefaults, key: key)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }

        userDefaults.set(data, forKey: key)
    }

    private static func load(from userDefaults: UserDefaults, key: String) -> LauncherSettings {
        guard
            let data = userDefaults.data(forKey: key),
            let settings = try? JSONDecoder().decode(LauncherSettings.self, from: data)
        else {
            return LauncherSettings()
        }

        return settings
    }
}
