import Foundation
import SwiftUI

/// Subagent execution status
enum SubagentStatus: Equatable {
    /// Running
    case running
    /// Waiting
    case waiting
    /// Completed
    case completed
    /// Error
    case error

    var color: Color {
        switch self {
        case .running: return Color(red: 0.204, green: 0.780, blue: 0.349).opacity(0.8)  // #34C759 muted
        case .waiting: return Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.8)        // #FFCC00 muted
        case .completed: return Color(red: 0.557, green: 0.557, blue: 0.576)             // #8E8E93
        case .error: return Color(red: 1.0, green: 0.231, blue: 0.188)                   // #FF3B30
        }
    }

    var iconName: String {
        switch self {
        case .running: return "circle.fill"
        case .waiting: return "circle.dotted"
        case .completed: return "checkmark.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        }
    }
}

/// Parallel execution subagent created by Task tool
struct Subagent: Identifiable, Equatable {
    let id: String
    let name: String
    var status: SubagentStatus
    let startTime: Date
    var endTime: Date?

    init(
        id: String,
        name: String,
        status: SubagentStatus = .running,
        startTime: Date = Date(),
        endTime: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.startTime = startTime
        self.endTime = endTime
    }

    /// Elapsed time
    var elapsedTime: TimeInterval {
        let end = endTime ?? Date()
        return end.timeIntervalSince(startTime)
    }

    /// Formatted elapsed time
    var formattedElapsedTime: String {
        let elapsed = Int(elapsedTime)
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    static func == (lhs: Subagent, rhs: Subagent) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.status == rhs.status &&
        lhs.startTime == rhs.startTime &&
        lhs.endTime == rhs.endTime
    }
}
