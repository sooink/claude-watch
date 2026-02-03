import Foundation
import SwiftUI
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ClaudeWatch", category: "WatchCoordinator")

/// Overall monitoring coordination
@Observable
final class WatchCoordinator {
    var watchState: WatchState = .stopped
    var projects: [Project] = []
    var lastUpdate: Date = Date()

    private let processMonitor = ProcessMonitor()
    private var fileWatcher: FileWatcher?
    private let sessionParser = SessionParser()
    private let socketServer = SocketServer()
    private let notificationManager = NotificationManager.shared
    private let settings = AppSettings.shared

    private let claudeProjectsPath: String
    private var updateTimer: Timer?

    // Map subagent ID to tool_use ID
    private var pendingSubagents: [String: (projectId: String, name: String, startTime: Date)] = [:]
    // Map task ID to internally generated ID
    private var taskIdMap: [String: String] = [:]
    // Map path to pending session status (for projects not yet created)
    private var pendingSessionStatus: [String: SessionStatus] = [:]

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
        setupSocketServer()
        setupSettingsObserver()
    }

    private func setupProcessMonitor() {
        processMonitor.onClaudeDetected = { [weak self] in
            self?.onClaudeDetected()
        }
        processMonitor.onClaudeTerminated = { [weak self] in
            self?.onClaudeTerminated()
        }
    }

    private func setupSocketServer() {
        socketServer.onEventReceived = { [weak self] event in
            self?.handleHookEvent(event)
        }

        // Sync hook state on startup
        syncHookState()
    }

    private func syncHookState() {
        let installer = HookInstaller.shared

        if settings.hookEnabled {
            // Hook enabled: ensure installed and start socket
            if !installer.isInstalled {
                try? installer.install()
            }
            socketServer.start()
        } else {
            // Hook disabled: ensure uninstalled
            if installer.isInstalled {
                try? installer.uninstall()
            }
        }
    }

    private func setupSettingsObserver() {
        settings.onHookEnabledChanged = { [weak self] _ in
            self?.syncHookState()
        }

        settings.onNotificationEnabledChanged = { [weak self] enabled in
            if enabled {
                self?.notificationManager.requestAuthorization()
            }
        }

        // Request notification permission if already enabled on startup
        if settings.notificationEnabled {
            notificationManager.requestAuthorization()
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
        socketServer.stop()
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
        pendingSessionStatus.removeAll()
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

            // Skip to end of all .jsonl files to ignore existing content
            // Only new entries after app launch will be parsed
            for sessionFile in findAllSessionFiles(in: projectPath) {
                sessionParser.skipToEnd(for: sessionFile)
            }
        }
    }

    private func findAllSessionFiles(in directory: String) -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return []
        }

        return contents
            .filter { $0.hasSuffix(".jsonl") }
            .map { directory + "/" + $0 }
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
            // Apply pending session status if available
            let initialStatus = pendingSessionStatus[path] ?? .unknown
            pendingSessionStatus.removeValue(forKey: path)

            let project = Project(
                id: projectId,
                path: path,
                sessionId: sessionId,
                sessionStatus: initialStatus
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

    // MARK: - Hook Event Handling

    private func handleHookEvent(_ event: HookEvent) {
        let path = event.cwd

        logger.info("Hook event received: \(event.event.rawValue) for path: \(path)")
        logger.info("Current projects: \(self.projects.map { $0.path })")

        switch event.event {
        case .userPromptSubmit:
            handleUserPromptSubmit(path: path, sessionId: event.sessionId)
        case .stop:
            handleSessionStop(path: path, sessionId: event.sessionId)
        }
    }

    private func handleUserPromptSubmit(path: String, sessionId: String) {
        // Normalize path (remove trailing slash)
        let normalizedPath = path.hasSuffix("/") ? String(path.dropLast()) : path

        logger.info("UserPromptSubmit: Looking for path '\(normalizedPath)'")
        logger.info("UserPromptSubmit: Existing projects: \(self.projects.map { $0.path })")

        // Find project by path
        if let index = projects.firstIndex(where: { $0.path == normalizedPath }) {
            projects[index].sessionStatus = .working
            logger.info("UserPromptSubmit: Updated project '\(self.projects[index].displayName)' to working")
        } else {
            // Create new project for this session
            let projectId = normalizedPath.replacingOccurrences(of: "/", with: "-")
            let project = Project(
                id: projectId,
                path: normalizedPath,
                sessionId: sessionId,
                sessionStatus: .working
            )
            projects.append(project)
            logger.info("UserPromptSubmit: Created new project '\(project.displayName)' with working status")

            // Switch to active state
            if watchState != .active {
                watchState = .active
            }
        }
    }

    private func handleSessionStop(path: String, sessionId: String) {
        // Normalize path (remove trailing slash)
        let normalizedPath = path.hasSuffix("/") ? String(path.dropLast()) : path

        logger.info("Stop: Looking for path '\(normalizedPath)'")
        logger.info("Stop: Existing projects: \(self.projects.map { $0.path })")

        // Find project by path
        if let index = projects.firstIndex(where: { $0.path == normalizedPath }) {
            projects[index].sessionStatus = .idle
            logger.info("Stop: Updated project '\(self.projects[index].displayName)' to idle")

            // Send notification if enabled
            if settings.notificationEnabled {
                notificationManager.sendSessionCompletedNotification(
                    projectName: projects[index].displayName,
                    path: normalizedPath
                )
            }
        } else {
            logger.info("Stop: No matching project found for path: \(normalizedPath)")
        }

        // Clean up pending status
        pendingSessionStatus.removeValue(forKey: normalizedPath)
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
