import Foundation

/// Project/session information
struct Project: Identifiable, Equatable {
    let id: String
    let path: String
    var sessionId: String
    var subagents: [Subagent]
    var tasks: [TaskItem]
    var isExpanded: Bool
    var startTime: Date

    init(
        id: String,
        path: String,
        sessionId: String,
        subagents: [Subagent] = [],
        tasks: [TaskItem] = [],
        isExpanded: Bool = true,
        startTime: Date = Date()
    ) {
        self.id = id
        self.path = path
        self.sessionId = sessionId
        self.subagents = subagents
        self.tasks = tasks
        self.isExpanded = isExpanded
        self.startTime = startTime
    }

    /// Display name (extracted from path)
    var displayName: String {
        // Handle root directory (path is "/" or id is "-")
        if path == "/" || id == "-" {
            return "/"
        }
        // Extract last component from path
        let components = path.split(separator: "/")
        if let last = components.last {
            return String(last)
        }
        return id
    }

    /// Elapsed time
    var elapsedTime: TimeInterval {
        Date().timeIntervalSince(startTime)
    }

    /// Formatted elapsed time
    var formattedElapsedTime: String {
        let elapsed = elapsedTime
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Number of running subagents
    var activeSubagentCount: Int {
        subagents.filter { $0.status == .running }.count
    }

    /// Task progress
    var taskProgress: (completed: Int, total: Int) {
        let completed = tasks.filter { $0.status == .completed }.count
        return (completed, tasks.count)
    }

    static func == (lhs: Project, rhs: Project) -> Bool {
        lhs.id == rhs.id &&
        lhs.path == rhs.path &&
        lhs.sessionId == rhs.sessionId &&
        lhs.subagents == rhs.subagents &&
        lhs.tasks == rhs.tasks &&
        lhs.isExpanded == rhs.isExpanded
    }
}
