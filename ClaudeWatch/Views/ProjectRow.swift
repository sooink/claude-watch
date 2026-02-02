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
        let escapedPath = path.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        tell application "Terminal"
            activate
            do script "cd '\(escapedPath)'"
        end tell
        """
        NSAppleScript(source: script)?.executeAndReturnError(nil)
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
