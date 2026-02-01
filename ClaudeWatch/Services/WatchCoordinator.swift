import Foundation
import SwiftUI

/// Overall monitoring coordination
@Observable
final class WatchCoordinator {
    var watchState: WatchState = .stopped
    var projects: [Project] = []
    var lastUpdate: Date = Date()

    private let processMonitor = ProcessMonitor()
    private var fileWatcher: FileWatcher?
    private let sessionParser = SessionParser()

    private let claudeProjectsPath: String
    private var updateTimer: Timer?

    // Map subagent ID to tool_use ID
    private var pendingSubagents: [String: (projectId: String, name: String, startTime: Date)] = [:]
    // Map task ID to internally generated ID
    private var taskIdMap: [String: String] = [:]

    init() {
        // Use resolved path from symlink
        let claudeDir = NSHomeDirectory() + "/.claude"
        let resolvedPath = (try? FileManager.default.destinationOfSymbolicLink(atPath: claudeDir))
            .map { dest -> String in
                // Convert relative path to absolute
                if dest.hasPrefix("/") {
                    return dest
                } else {
                    return NSHomeDirectory() + "/" + dest
                }
            } ?? claudeDir
        claudeProjectsPath = resolvedPath + "/projects/"
        setupProcessMonitor()
    }

    private func setupProcessMonitor() {
        processMonitor.onClaudeDetected = { [weak self] in
            self?.onClaudeDetected()
        }
        processMonitor.onClaudeTerminated = { [weak self] in
            self?.onClaudeTerminated()
        }
    }

    func start() {
        processMonitor.start()
    }

    func stop() {
        processMonitor.stop()
        fileWatcher?.stop()
        fileWatcher = nil
        updateTimer?.invalidate()
        updateTimer = nil
        watchState = .stopped
    }

    private func onClaudeDetected() {
        watchState = .watching
        startFileWatching()
        startUpdateTimer()
        scanExistingProjects()
    }

    private func onClaudeTerminated() {
        fileWatcher?.stop()
        fileWatcher = nil
        updateTimer?.invalidate()
        updateTimer = nil
        sessionParser.resetAll()
        watchState = .stopped
        projects.removeAll()
        pendingSubagents.removeAll()
        taskIdMap.removeAll()
    }

    private func startFileWatching() {
        fileWatcher = FileWatcher(paths: [claudeProjectsPath]) { [weak self] events in
            self?.handleFileEvents(events)
        }
        fileWatcher?.start()
    }

    private func startUpdateTimer() {
        // Timer for UI updates (elapsed time display)
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            // Trigger UI refresh via @Observable property change
            self?.lastUpdate = Date()
        }
    }

    private func scanExistingProjects() {
        guard let projectDirs = try? FileManager.default.contentsOfDirectory(atPath: claudeProjectsPath) else {
            return
        }

        for dir in projectDirs {
            let projectPath = claudeProjectsPath + dir
            var isDirectory: ObjCBool = false

            guard FileManager.default.fileExists(atPath: projectPath, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }

            // Find most recently modified .jsonl file
            if let sessionFile = findLatestSessionFile(in: projectPath) {
                // On initial scan, only record file end position without parsing
                // → Only parse new entries on subsequent file changes
                sessionParser.skipToEnd(for: sessionFile)
            }
        }
    }

    private func findLatestSessionFile(in directory: String) -> String? {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return nil
        }

        let now = Date()
        let activeThreshold: TimeInterval = 60 // Only consider files modified within last minute as active

        let jsonlFiles = contents
            .filter { $0.hasSuffix(".jsonl") }
            .map { directory + "/" + $0 }
            .compactMap { path -> (path: String, date: Date)? in
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                      let modDate = attrs[.modificationDate] as? Date else { return nil }
                return (path, modDate)
            }
            .filter { now.timeIntervalSince($0.date) < activeThreshold } // Active sessions only
            .sorted { $0.date > $1.date }

        return jsonlFiles.first?.path
    }

    private func handleFileEvents(_ events: [FileEvent]) {
        // Separate remove and modify events
        let removedPaths = events.filter { $0.type == .removed }.map(\.path)
        let modifiedPaths = events.filter { $0.type == .modified }.map(\.path)

        // Handle deleted session files
        for path in removedPaths {
            handleSessionRemoved(path)
        }

        // Handle modified files
        handleFileChanges(modifiedPaths)
    }

    private func handleSessionRemoved(_ path: String) {
        let pathComponents = path.replacingOccurrences(of: claudeProjectsPath, with: "").split(separator: "/")
        guard let projectHash = pathComponents.first else { return }
        let projectId = String(projectHash)

        // If main session file is deleted (e.g., {sessionId}.jsonl)
        // Remove the project
        if let projectIndex = projects.firstIndex(where: { $0.id == projectId }) {
            // Remove file info from session parser
            sessionParser.removeFile(path)

            // Remove project
            projects.remove(at: projectIndex)

            // Remove pending subagents associated with project
            pendingSubagents = pendingSubagents.filter { $0.value.projectId != projectId }
        }

        // Change state if no active projects
        if projects.isEmpty && watchState == .active {
            watchState = .watching
        }
    }

    private func handleFileChanges(_ paths: [String]) {
        for path in paths {
            let entries = sessionParser.parseNewEntries(at: path)
            guard !entries.isEmpty else { continue }

            let toolUses = sessionParser.extractToolUse(from: entries)
            let toolResults = sessionParser.extractToolResult(from: entries)

            // Extract project info
            let pathComponents = path.replacingOccurrences(of: claudeProjectsPath, with: "").split(separator: "/")
            guard let projectHash = pathComponents.first else { continue }
            let projectId = String(projectHash)

            // Extract cwd from JSONL (exact path)
            let originalPath = sessionParser.extractCwd(from: entries) ?? projectId.replacingOccurrences(of: "-", with: "/")
            let sessionId = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent

            // Process Tool Use (create project only when Task/TaskCreate exists)
            for toolUse in toolUses {
                switch toolUse.name {
                case "Task":
                    let actualProjectId = ensureProjectExists(projectId: projectId, path: originalPath, sessionId: sessionId)
                    handleSubagentCreation(toolUse, projectId: actualProjectId)
                case "TaskCreate":
                    let actualProjectId = ensureProjectExists(projectId: projectId, path: originalPath, sessionId: sessionId)
                    handleTaskCreation(toolUse, projectId: actualProjectId)
                case "TaskUpdate":
                    // Find project by path (existing projects only)
                    if let existingProject = projects.first(where: { $0.path == originalPath }) {
                        handleTaskUpdate(toolUse, projectId: existingProject.id)
                    }
                default:
                    break
                }
            }

            // Process Tool Result (detect subagent completion)
            for result in toolResults {
                handleToolResult(result, projectId: projectId)
            }
        }

        // Switch to active state if there's activity
        if !projects.isEmpty && watchState != .active {
            watchState = .active
        }
    }

    /// Create project if not exists and return actual project ID (with duplicate check)
    @discardableResult
    private func ensureProjectExists(projectId: String, path: String, sessionId: String) -> String {
        // Check duplicates by id or path
        let existingById = projects.firstIndex(where: { $0.id == projectId })
        let existingByPath = projects.firstIndex(where: { $0.path == path })

        if existingById == nil && existingByPath == nil {
            // Add new project
            let project = Project(
                id: projectId,
                path: path,
                sessionId: sessionId
            )
            projects.append(project)
            return projectId
        } else if let index = existingByPath {
            // Return existing project ID if same path exists
            return projects[index].id
        } else if let index = existingById {
            // Update path if found by ID
            if projects[index].path != path {
                projects[index] = Project(
                    id: projects[index].id,
                    path: path,
                    sessionId: sessionId,
                    subagents: projects[index].subagents,
                    tasks: projects[index].tasks,
                    isExpanded: projects[index].isExpanded,
                    startTime: projects[index].startTime
                )
            }
            return projectId
        }
        return projectId
    }

    private func handleSubagentCreation(_ toolUse: ToolUseEvent, projectId: String) {
        guard let info = sessionParser.extractAgentInfo(from: toolUse.input),
              let projectIndex = projects.firstIndex(where: { $0.id == projectId }) else { return }

        let startTime = toolUse.timestamp ?? Date()
        let subagent = Subagent(
            id: toolUse.id,
            name: info.description,
            status: .running,
            startTime: startTime
        )

        // Skip if already exists
        if projects[projectIndex].subagents.contains(where: { $0.id == toolUse.id }) {
            return
        }

        projects[projectIndex].subagents.append(subagent)
        // Store actual project ID (for completion detection later)
        pendingSubagents[toolUse.id] = (projectId: projects[projectIndex].id, name: info.description, startTime: startTime)
    }

    private func handleTaskCreation(_ toolUse: ToolUseEvent, projectId: String) {
        guard let info = sessionParser.extractTaskItemInfo(from: toolUse.input),
              let projectIndex = projects.firstIndex(where: { $0.id == projectId }) else { return }

        // Should get actual ID from TaskCreate result, but here we generate temp ID based on order
        let taskCount = projects[projectIndex].tasks.count + 1
        let taskId = String(taskCount)

        let taskItem = TaskItem(
            id: taskId,
            subject: info.subject,
            description: info.description,
            status: .pending,
            activeForm: info.activeForm
        )

        // Skip if already exists
        if projects[projectIndex].tasks.contains(where: { $0.subject == info.subject }) {
            return
        }

        projects[projectIndex].tasks.append(taskItem)
        taskIdMap[toolUse.id] = taskId
    }

    private func handleTaskUpdate(_ toolUse: ToolUseEvent, projectId: String) {
        guard let updateInfo = sessionParser.extractTaskUpdateInfo(from: toolUse.input),
              let projectIndex = projects.firstIndex(where: { $0.id == projectId }) else { return }

        let taskId = updateInfo.taskId

        if let taskIndex = projects[projectIndex].tasks.firstIndex(where: { $0.id == taskId }) {
            if let statusString = updateInfo.status,
               let newStatus = TaskStatus(rawValue: statusString) {
                projects[projectIndex].tasks[taskIndex].status = newStatus
            }
        }
    }

    private func handleToolResult(_ result: (toolUseId: String, content: String, timestamp: Date?), projectId: String) {
        // Check subagent completion (use projectId stored in pendingSubagents)
        if let pending = pendingSubagents[result.toolUseId] {
            if let projectIndex = projects.firstIndex(where: { $0.id == pending.projectId }),
               let subagentIndex = projects[projectIndex].subagents.firstIndex(where: { $0.id == result.toolUseId }) {
                projects[projectIndex].subagents[subagentIndex].status = .completed
                projects[projectIndex].subagents[subagentIndex].endTime = result.timestamp ?? Date()
            }
            pendingSubagents.removeValue(forKey: result.toolUseId)
        }
    }

    // Computed properties for UI
    var totalActiveSubagents: Int {
        projects.reduce(0) { $0 + $1.activeSubagentCount }
    }

    var hasActiveSession: Bool {
        !projects.isEmpty
    }

    deinit {
        stop()
    }
}
