import Foundation

/// App monitoring state
enum WatchState: Equatable {
    /// Claude process not detected
    case stopped
    /// Claude detected, waiting for activity
    case watching
    /// Active session exists
    case active

    var displayText: String {
        switch self {
        case .stopped: return "Stopped"
        case .watching: return "Watching"
        case .active: return "Active"
        }
    }

    var isMonitoring: Bool {
        self != .stopped
    }
}
