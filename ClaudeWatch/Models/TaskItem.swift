import Foundation
import SwiftUI

/// Task item status
enum TaskStatus: String, Equatable {
    case pending = "pending"
    case inProgress = "in_progress"
    case completed = "completed"

    var color: Color {
        switch self {
        case .pending: return Color(red: 0.557, green: 0.557, blue: 0.576)   // #8E8E93 gray
        case .inProgress: return Color(red: 0.0, green: 0.478, blue: 1.0)     // #007AFF blue
        case .completed: return Color(red: 0.557, green: 0.557, blue: 0.576)  // #8E8E93 gray
        }
    }

    var iconName: String {
        switch self {
        case .pending: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .completed: return "checkmark.circle.fill"
        }
    }
}

/// Task item created by TaskCreate
struct TaskItem: Identifiable, Equatable {
    let id: String
    var subject: String
    var description: String
    var status: TaskStatus
    var activeForm: String?

    init(
        id: String,
        subject: String,
        description: String = "",
        status: TaskStatus = .pending,
        activeForm: String? = nil
    ) {
        self.id = id
        self.subject = subject
        self.description = description
        self.status = status
        self.activeForm = activeForm
    }

    /// Display text (uses activeForm when in_progress)
    var displayText: String {
        if status == .inProgress, let activeForm = activeForm, !activeForm.isEmpty {
            return activeForm
        }
        return subject
    }
}
