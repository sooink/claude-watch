import Foundation

/// App settings with UserDefaults persistence
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let hookEnabled = "hookEnabled"
        static let indicatorEnabled = "indicatorEnabled"
        static let notificationEnabled = "notificationEnabled"
    }

    /// Enable socket server for receiving hook events
    var hookEnabled: Bool {
        didSet {
            defaults.set(hookEnabled, forKey: Keys.hookEnabled)
            onHookEnabledChanged?(hookEnabled)
        }
    }

    /// Show session indicator in project row
    var indicatorEnabled: Bool {
        didSet {
            defaults.set(indicatorEnabled, forKey: Keys.indicatorEnabled)
        }
    }

    /// Send macOS notifications on session completion
    var notificationEnabled: Bool {
        didSet {
            defaults.set(notificationEnabled, forKey: Keys.notificationEnabled)
            onNotificationEnabledChanged?(notificationEnabled)
        }
    }

    /// Callback when hookEnabled changes (for WatchCoordinator to start/stop socket server)
    var onHookEnabledChanged: ((Bool) -> Void)?

    /// Callback when notificationEnabled changes (for requesting notification permission)
    var onNotificationEnabledChanged: ((Bool) -> Void)?

    private init() {
        // Load from UserDefaults with defaults
        self.hookEnabled = defaults.object(forKey: Keys.hookEnabled) as? Bool ?? false
        self.indicatorEnabled = defaults.object(forKey: Keys.indicatorEnabled) as? Bool ?? true
        self.notificationEnabled = defaults.object(forKey: Keys.notificationEnabled) as? Bool ?? false
    }
}
