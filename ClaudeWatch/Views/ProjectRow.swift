import SwiftUI

/// Project row View
struct ProjectRow: View {
    @Binding var project: Project
    @State private var isHovered = false

    private let settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Project header (entire area clickable)
            Button(action: { project.isExpanded.toggle() }) {
                VStack(alignment: .leading, spacing: 6) {
                    // Project name with session indicator
                    HStack(spacing: 6) {
                        if settings.hookEnabled &&
                           settings.indicatorEnabled &&
                           project.sessionStatus != .unknown {
                            SessionIndicator(status: project.sessionStatus)
                        }
                        Text(project.displayName)
                            .font(.body.bold())
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }

                    // Summary info (collapsed state only)
                    if !project.isExpanded {
                        HStack(spacing: 8) {
                            // Running subagents
                            if project.activeSubagentCount > 0 {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(Color.green.opacity(0.8))
                                        .frame(width: 6, height: 6)
                                    Text("\(project.activeSubagentCount) running")
                                }
                            }
                            // Task progress
                            if !project.tasks.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "checklist")
                                    Text("\(project.taskProgress.completed)/\(project.taskProgress.total)")
                                }
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Open in Terminal") { openTerminal(at: project.path) }
                Button("Copy Path") { copyPath(project.path) }
            }

            // Expanded content
            if project.isExpanded {
                Divider()
                    .opacity(0.3)
                    .padding(.horizontal, 12)

                VStack(alignment: .leading, spacing: 12) {
                    // Subagents section
                    if !project.subagents.isEmpty {
                        SectionView(title: "Subagents", count: project.subagents.count) {
                            ForEach(project.subagents) { subagent in
                                SubagentRow(subagent: subagent)
                            }
                        }
                    }

                    // Tasks section
                    if !project.tasks.isEmpty {
                        SectionView(title: "Tasks", count: project.tasks.count) {
                            ForEach(project.tasks) { task in
                                TaskItemRow(taskItem: task)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .brightness(isHovered ? 0.05 : 0)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onHover { isHovered = $0 }
    }

    private func openTerminal(at path: String) {
        let terminal = settings.preferredTerminal

        // Fallback to Terminal.app if selected terminal is not installed
        guard terminal.isInstalled else {
            print("[ClaudeWatch] \(terminal.displayName) is not installed, falling back to Terminal.app")
            openWithTerminalApp(path)
            return
        }

        switch terminal {
        case .terminal:
            openWithTerminalApp(path)
        case .iterm:
            openWithITerm(path)
        case .ghostty:
            openWithGhostty(path)
        case .warp:
            openWithWarp(path)
        case .kitty:
            openWithKitty(path)
        case .alacritty:
            openWithAlacritty(path)
        }
    }

    private func openWithTerminalApp(_ path: String) {
        let escapedPath = path.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        tell application "Terminal"
            activate
            do script "cd '\(escapedPath)'"
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error = error {
            print("[ClaudeWatch] AppleScript error (Terminal): \(error)")
        }
    }

    private func openWithITerm(_ path: String) {
        let escapedPath = path.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        tell application "iTerm"
            activate
            set newWindow to (create window with default profile)
            tell current session of newWindow
                write text "cd '\(escapedPath)'"
            end tell
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error = error {
            print("[ClaudeWatch] AppleScript error (iTerm): \(error)")
        }
    }

    private func openWithGhostty(_ path: String) {
        // Ghostty supports --working-directory flag
        // Try to find ghostty CLI in common locations
        let ghosttyPaths = [
            "/Applications/Ghostty.app/Contents/MacOS/ghostty",
            "/opt/homebrew/bin/ghostty",
            "/usr/local/bin/ghostty"
        ]

        if let ghosttyPath = ghosttyPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: ghosttyPath)
            task.arguments = ["--working-directory=\(path)"]
            try? task.run()
        } else {
            // Fallback: open app and cd
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-a", "Ghostty"]
            try? task.run()
        }
    }

    private func openWithWarp(_ path: String) {
        // Warp supports URL scheme: warp://action/new_window?path=
        if let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "warp://action/new_window?path=\(encodedPath)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openWithKitty(_ path: String) {
        // Kitty supports --directory flag
        let kittyPaths = [
            "/Applications/kitty.app/Contents/MacOS/kitty",
            "/opt/homebrew/bin/kitty",
            "/usr/local/bin/kitty"
        ]

        if let kittyPath = kittyPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: kittyPath)
            task.arguments = ["--directory", path]
            try? task.run()
        }
    }

    private func openWithAlacritty(_ path: String) {
        // Alacritty supports --working-directory flag
        let alacrittyPaths = [
            "/Applications/Alacritty.app/Contents/MacOS/alacritty",
            "/opt/homebrew/bin/alacritty",
            "/usr/local/bin/alacritty"
        ]

        if let alacrittyPath = alacrittyPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: alacrittyPath)
            task.arguments = ["--working-directory", path]
            try? task.run()
        }
    }

    private func copyPath(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }
}

/// Section View (Subagents, Tasks, etc.)
private struct SectionView<Content: View>: View {
    let title: String
    let count: Int
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Section header
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Text("(\(count))")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
            }

            // Section content
            VStack(alignment: .leading, spacing: 0) {
                content
            }
        }
    }
}

#Preview {
    @Previewable @State var project = Project(
        id: "test-project",
        path: "/Users/test/project",
        sessionId: "abc123",
        subagents: [
            Subagent(id: "1", name: "Exploring codebase", status: .running),
            Subagent(id: "2", name: "Running tests", status: .completed)
        ],
        tasks: [
            TaskItem(id: "1", subject: "Create models", status: .completed),
            TaskItem(id: "2", subject: "Implement services", status: .inProgress, activeForm: "Implementing"),
            TaskItem(id: "3", subject: "Write tests", status: .pending)
        ]
    )

    return ProjectRow(project: $project)
        .frame(width: 300)
        .padding()
}
