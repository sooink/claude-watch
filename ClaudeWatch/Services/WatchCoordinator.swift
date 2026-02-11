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
    // Map session ID to project ID for consistent lookup across hook/file events
    private var sessionToProjectId: [String: String] = [:]

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
        sessionToProjectId.removeAll()
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

    private func normalizeProjectPath(_ path: String) -> String {
        let standardizedPath = (path as NSString).standardizingPath
        if standardizedPath == "/" {
            return "/"
        }
        return standardizedPath.hasSuffix("/") ? String(standardizedPath.dropLast()) : standardizedPath
    }

    private func makeProjectId(from path: String) -> String {
        let normalizedPath = normalizeProjectPath(path)
        if normalizedPath == "/" {
            return "-"
        }
        return normalizedPath.replacingOccurrences(of: "/", with: "-")
    }

    private func relativePathComponents(for path: String) -> [Substring] {
        path.replacingOccurrences(of: claudeProjectsPath, with: "").split(separator: "/")
    }

    private func isMainSessionFile(_ path: String) -> Bool {
        let components = relativePathComponents(for: path)
        return components.count == 2 && components[1].hasSuffix(".jsonl")
    }

    private func handleFileEvents(_ events: [FileEvent]) {
        // Separate remove and modify events
        let removedPaths = events
            .filter { $0.type == .removed && isMainSessionFile($0.path) }
            .map(\.path)
        let modifiedPaths = events
            .filter { $0.type == .modified && isMainSessionFile($0.path) }
            .map(\.path)

        // Handle deleted session files
        for path in removedPaths {
            handleSessionRemoved(path)
        }

        // Handle modified files
        handleFileChanges(modifiedPaths)
    }

    private func handleSessionRemoved(_ path: String) {
        let pathComponents = relativePathComponents(for: path)
        guard let projectHash = pathComponents.first else { return }
        let sessionId = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent

        // Remove file info from session parser
        sessionParser.removeFile(path)

        // Remove project by session mapping first
        if let mappedProjectId = sessionToProjectId.removeValue(forKey: sessionId),
           let projectIndex = projects.firstIndex(where: { $0.id == mappedProjectId }) {
            projects.remove(at: projectIndex)

            // Remove pending subagents associated with project
            pendingSubagents = pendingSubagents.filter { $0.value.projectId != mappedProjectId }
            sessionToProjectId = sessionToProjectId.filter { $0.value != mappedProjectId }
        } else {
            // Legacy fallback: remove by project hash ID
            let fallbackProjectId = String(projectHash)
            if let projectIndex = projects.firstIndex(where: { $0.id == fallbackProjectId }) {
                projects.remove(at: projectIndex)
                pendingSubagents = pendingSubagents.filter { $0.value.projectId != fallbackProjectId }
                sessionToProjectId = sessionToProjectId.filter { $0.value != fallbackProjectId }
            }
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
            let pathComponents = relativePathComponents(for: path)
            guard let projectHash = pathComponents.first else { continue }
            let sessionProjectHash = String(projectHash)

            // Extract cwd from JSONL (exact path)
            let fallbackPath = sessionProjectHash.replacingOccurrences(of: "-", with: "/")
            let originalPath = sessionParser.extractCwd(from: entries) ?? fallbackPath
            let normalizedPath = normalizeProjectPath(originalPath)
            let sessionId = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent

            // Process Tool Use (create project only when Task/TaskCreate exists)
            for toolUse in toolUses {
                switch toolUse.name {
                case "Task":
                    let actualProjectId = ensureProjectExists(projectHash: sessionProjectHash, path: normalizedPath, sessionId: sessionId)
                    handleSubagentCreation(toolUse, projectId: actualProjectId)
                case "TaskCreate":
                    let actualProjectId = ensureProjectExists(projectHash: sessionProjectHash, path: normalizedPath, sessionId: sessionId)
                    handleTaskCreation(toolUse, projectId: actualProjectId)
                case "TaskUpdate":
                    // Prefer session mapping to avoid path drift mismatch
                    if let mappedProjectId = sessionToProjectId[sessionId] {
                        handleTaskUpdate(toolUse, projectId: mappedProjectId)
                    } else if let existingProject = projects.first(where: { $0.path == normalizedPath }) {
                        sessionToProjectId[sessionId] = existingProject.id
                        handleTaskUpdate(toolUse, projectId: existingProject.id)
                    }
                default:
                    break
                }
            }

            // Process Tool Result (detect subagent completion)
            for result in toolResults {
                handleToolResult(result)
            }
        }

        // Switch to active state if there's activity
        if !projects.isEmpty && watchState != .active {
            watchState = .active
        }
    }

    /// Create project if not exists and return actual project ID (with duplicate check)
    @discardableResult
    private func ensureProjectExists(projectHash: String, path: String, sessionId: String) -> String {
        let normalizedPath = normalizeProjectPath(path)
        let normalizedProjectId = makeProjectId(from: normalizedPath)
        let existingByHash = projects.firstIndex(where: { $0.id == projectHash })
        let existingById = projects.firstIndex(where: { $0.id == normalizedProjectId })
        let existingByPath = projects.firstIndex(where: { $0.path == normalizedPath })

        // Resolve by existing session mapping first
        if let mappedProjectId = sessionToProjectId[sessionId] {
            if let mappedIndex = projects.firstIndex(where: { $0.id == mappedProjectId }) {
                if projects[mappedIndex].path != normalizedPath || projects[mappedIndex].sessionId != sessionId {
                    projects[mappedIndex] = Project(
                        id: projects[mappedIndex].id,
                        path: normalizedPath,
                        sessionId: sessionId,
                        subagents: projects[mappedIndex].subagents,
                        tasks: projects[mappedIndex].tasks,
                        isExpanded: projects[mappedIndex].isExpanded,
                        startTime: projects[mappedIndex].startTime,
                        sessionStatus: projects[mappedIndex].sessionStatus
                    )
                }
                return mappedProjectId
            }
            sessionToProjectId.removeValue(forKey: sessionId)
        }

        if existingByHash == nil && existingById == nil && existingByPath == nil {
            // Add new project
            // Apply pending session status if available
            let initialStatus = pendingSessionStatus[normalizedPath] ?? .unknown
            pendingSessionStatus.removeValue(forKey: normalizedPath)

            let project = Project(
                id: normalizedProjectId,
                path: normalizedPath,
                sessionId: sessionId,
                sessionStatus: initialStatus
            )
            projects.append(project)
            sessionToProjectId[sessionId] = normalizedProjectId
            return normalizedProjectId
        } else if let index = existingByPath {
            // Return existing project ID if same path exists
            if projects[index].sessionId != sessionId {
                projects[index] = Project(
                    id: projects[index].id,
                    path: projects[index].path,
                    sessionId: sessionId,
                    subagents: projects[index].subagents,
                    tasks: projects[index].tasks,
                    isExpanded: projects[index].isExpanded,
                    startTime: projects[index].startTime,
                    sessionStatus: projects[index].sessionStatus
                )
            }
            sessionToProjectId[sessionId] = projects[index].id
            return projects[index].id
        } else if let index = existingById {
            // Update path/session if found by normalized ID
            if projects[index].path != normalizedPath || projects[index].sessionId != sessionId {
                projects[index] = Project(
                    id: projects[index].id,
                    path: normalizedPath,
                    sessionId: sessionId,
                    subagents: projects[index].subagents,
                    tasks: projects[index].tasks,
                    isExpanded: projects[index].isExpanded,
                    startTime: projects[index].startTime,
                    sessionStatus: projects[index].sessionStatus
                )
            }
            sessionToProjectId[sessionId] = projects[index].id
            return projects[index].id
        } else if let index = existingByHash {
            // Legacy fallback for projects created with hash ID
            if projects[index].path != normalizedPath || projects[index].sessionId != sessionId {
                projects[index] = Project(
                    id: projects[index].id,
                    path: normalizedPath,
                    sessionId: sessionId,
                    subagents: projects[index].subagents,
                    tasks: projects[index].tasks,
                    isExpanded: projects[index].isExpanded,
                    startTime: projects[index].startTime,
                    sessionStatus: projects[index].sessionStatus
                )
            }
            sessionToProjectId[sessionId] = projects[index].id
            return projects[index].id
        }
        return normalizedProjectId
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

    private func handleToolResult(_ result: (toolUseId: String, content: String, timestamp: Date?)) {
        updateSubagentStatus(toolUseId: result.toolUseId, status: .completed, timestamp: result.timestamp)
    }

    private func updateSubagentStatus(toolUseId: String, status: SubagentStatus, timestamp: Date?) {
        let endTime = timestamp ?? Date()

        // Check subagent completion (use projectId stored in pendingSubagents)
        if let pending = pendingSubagents[toolUseId],
           let projectIndex = projects.firstIndex(where: { $0.id == pending.projectId }),
           let subagentIndex = projects[projectIndex].subagents.firstIndex(where: { $0.id == toolUseId }) {
            projects[projectIndex].subagents[subagentIndex].status = status
            projects[projectIndex].subagents[subagentIndex].endTime = endTime
            pendingSubagents.removeValue(forKey: toolUseId)
            return
        }

        // Fallback when pending mapping is unavailable
        for projectIndex in projects.indices {
            if let subagentIndex = projects[projectIndex].subagents.firstIndex(where: { $0.id == toolUseId }) {
                projects[projectIndex].subagents[subagentIndex].status = status
                projects[projectIndex].subagents[subagentIndex].endTime = endTime
                pendingSubagents.removeValue(forKey: toolUseId)
                return
            }
        }

        pendingSubagents.removeValue(forKey: toolUseId)
    }

    private func handleTaskToolStart(from event: HookEvent) {
        guard let toolUseId = event.toolUseId else { return }
        guard event.toolName == nil || event.toolName == "Task" else { return }

        let normalizedPath = normalizeProjectPath(event.cwd)
        let projectHash = makeProjectId(from: normalizedPath)
        let projectId = ensureProjectExists(projectHash: projectHash, path: normalizedPath, sessionId: event.sessionId)

        guard let projectIndex = projects.firstIndex(where: { $0.id == projectId }) else { return }

        // Hook integration means Claude is currently running.
        if projects[projectIndex].sessionStatus != .working {
            projects[projectIndex].sessionStatus = .working
        }

        if projects[projectIndex].subagents.contains(where: { $0.id == toolUseId }) {
            return
        }

        let name = event.taskDescription ?? event.subagentType ?? "Subagent"
        let startTime = Date()
        let subagent = Subagent(
            id: toolUseId,
            name: name,
            status: .running,
            startTime: startTime
        )

        projects[projectIndex].subagents.append(subagent)
        pendingSubagents[toolUseId] = (projectId: projects[projectIndex].id, name: name, startTime: startTime)

        if watchState != .active {
            watchState = .active
        }
    }

    private func handleTaskToolCompleted(from event: HookEvent) {
        guard let toolUseId = event.toolUseId else { return }
        guard event.toolName == nil || event.toolName == "Task" else { return }
        updateSubagentStatus(toolUseId: toolUseId, status: .completed, timestamp: Date())
    }

    private func handleTaskToolFailed(from event: HookEvent) {
        guard let toolUseId = event.toolUseId else { return }
        guard event.toolName == nil || event.toolName == "Task" else { return }
        updateSubagentStatus(toolUseId: toolUseId, status: .error, timestamp: Date())
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
        case .preToolUse:
            handleTaskToolStart(from: event)
        case .postToolUse:
            handleTaskToolCompleted(from: event)
        case .postToolUseFailure:
            handleTaskToolFailed(from: event)
        }
    }

    private func handleUserPromptSubmit(path: String, sessionId: String) {
        let normalizedPath = normalizeProjectPath(path)

        logger.info("UserPromptSubmit: Looking for path '\(normalizedPath)'")
        logger.info("UserPromptSubmit: Existing projects: \(self.projects.map { $0.path })")

        if let mappedProjectId = sessionToProjectId[sessionId],
           let index = projects.firstIndex(where: { $0.id == mappedProjectId }) {
            projects[index].sessionStatus = .working
            logger.info("UserPromptSubmit: Updated project '\(self.projects[index].displayName)' to working")
            return
        }

        let projectId = ensureProjectExists(projectHash: makeProjectId(from: normalizedPath), path: normalizedPath, sessionId: sessionId)
        if let index = projects.firstIndex(where: { $0.id == projectId }) {
            projects[index].sessionStatus = .working
            logger.info("UserPromptSubmit: Updated project '\(self.projects[index].displayName)' to working")
        }

        // Switch to active state
        if watchState != .active {
            watchState = .active
        }
    }

    private func handleSessionStop(path: String, sessionId: String) {
        let normalizedPath = normalizeProjectPath(path)

        logger.info("Stop: Looking for path '\(normalizedPath)'")
        logger.info("Stop: Existing projects: \(self.projects.map { $0.path })")

        let targetIndex: Int?
        if let mappedProjectId = sessionToProjectId[sessionId] {
            targetIndex = projects.firstIndex(where: { $0.id == mappedProjectId })
        } else {
            targetIndex = projects.firstIndex(where: { $0.path == normalizedPath })
        }

        if let index = targetIndex {
            projects[index].sessionStatus = .idle
            logger.info("Stop: Updated project '\(self.projects[index].displayName)' to idle")

            // Send notification if enabled
            if settings.notificationEnabled {
                notificationManager.sendSessionCompletedNotification(
                    projectName: projects[index].displayName,
                    path: projects[index].path
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
