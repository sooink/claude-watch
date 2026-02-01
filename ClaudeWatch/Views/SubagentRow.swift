import SwiftUI

/// Subagent row View
struct SubagentRow: View {
    let subagent: Subagent

    var body: some View {
        HStack(spacing: 8) {
            // Status indicator
            Image(systemName: subagent.status.iconName)
                .foregroundColor(subagent.status.color)
                .font(.system(size: 10))

            // Name
            Text(subagent.name)
                .font(.body)
                .lineLimit(1)

            Spacer()

            // Elapsed time (real-time update when running)
            ElapsedTimeView(
                startTime: subagent.startTime,
                endTime: subagent.endTime,
                isRunning: subagent.status == .running
            )
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }
}

/// Real-time elapsed time View
private struct ElapsedTimeView: View {
    let startTime: Date
    let endTime: Date?
    let isRunning: Bool

    var body: some View {
        if isRunning {
            // Running: TimelineView updates every second
            TimelineView(.periodic(from: .now, by: 1.0)) { context in
                Text(formattedTime(at: context.date))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        } else {
            // Completed: fixed time
            Text(formattedTime(at: nil))
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
        }
    }

    private func formattedTime(at currentDate: Date?) -> String {
        let end = endTime ?? currentDate ?? Date()
        let elapsed = Int(end.timeIntervalSince(startTime))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        SubagentRow(subagent: Subagent(
            id: "1",
            name: "Exploring codebase structure",
            status: .running
        ))

        SubagentRow(subagent: Subagent(
            id: "2",
            name: "Running tests",
            status: .waiting
        ))

        SubagentRow(subagent: Subagent(
            id: "3",
            name: "Code review",
            status: .completed,
            endTime: Date()
        ))

        SubagentRow(subagent: Subagent(
            id: "4",
            name: "Failed task",
            status: .error
        ))
    }
    .frame(width: 280)
    .padding()
}
