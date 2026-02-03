import Foundation
import AppKit

/// Supported terminal applications
enum TerminalApp: String, CaseIterable, Codable {
    case terminal = "Terminal"
    case iterm = "iTerm"
    case ghostty = "Ghostty"
    case warp = "Warp"
    case kitty = "Kitty"
    case alacritty = "Alacritty"

    var displayName: String {
        switch self {
        case .terminal: return "Terminal"
        case .iterm: return "iTerm2"
        case .ghostty: return "Ghostty"
        case .warp: return "Warp"
        case .kitty: return "Kitty"
        case .alacritty: return "Alacritty"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .terminal: return "com.apple.Terminal"
        case .iterm: return "com.googlecode.iterm2"
        case .ghostty: return "com.mitchellh.ghostty"
        case .warp: return "dev.warp.Warp-Stable"
        case .kitty: return "net.kovidgoyal.kitty"
        case .alacritty: return "io.alacritty"
        }
    }

    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    static var installedApps: [TerminalApp] {
        allCases.filter { $0.isInstalled }
    }
}

/// App settings with UserDefaults persistence
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let hookEnabled = "hookEnabled"
        static let indicatorEnabled = "indicatorEnabled"
        static let notificationEnabled = "notificationEnabled"
        static let preferredTerminal = "preferredTerminal"
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

    /// Preferred terminal application for "Open in Terminal"
    var preferredTerminal: TerminalApp {
        didSet {
            defaults.set(preferredTerminal.rawValue, forKey: Keys.preferredTerminal)
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

        // Load preferred terminal (default to first installed app, or Terminal)
        if let rawValue = defaults.string(forKey: Keys.preferredTerminal),
           let terminal = TerminalApp(rawValue: rawValue),
           terminal.isInstalled {
            self.preferredTerminal = terminal
        } else {
            self.preferredTerminal = TerminalApp.installedApps.first ?? .terminal
        }
    }
}
