import SwiftUI

/// Task item row View
struct TaskItemRow: View {
    let taskItem: TaskItem

    var body: some View {
        HStack(spacing: 8) {
            // Status icon
            Image(systemName: taskItem.status.iconName)
                .foregroundColor(taskItem.status.color)
                .font(.system(size: 10))

            // Title (uses activeForm when in_progress)
            Text(taskItem.displayText)
                .font(.body)
                .foregroundColor(taskItem.status == .completed ? .secondary : .primary)
                .lineLimit(1)
                .strikethrough(taskItem.status == .completed, color: .secondary)

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }
}

#Preview {
    VStack(spacing: 0) {
        TaskItemRow(taskItem: TaskItem(
            id: "1",
            subject: "Create data models",
            status: .completed
        ))

        TaskItemRow(taskItem: TaskItem(
            id: "2",
            subject: "Implement services",
            status: .completed
        ))

        TaskItemRow(taskItem: TaskItem(
            id: "3",
            subject: "Implement UI views",
            status: .inProgress,
            activeForm: "Implementing UI views"
        ))

        TaskItemRow(taskItem: TaskItem(
            id: "4",
            subject: "Write tests",
            status: .pending
        ))
    }
    .frame(width: 280)
    .padding()
}
