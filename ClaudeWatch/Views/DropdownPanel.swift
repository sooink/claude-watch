import SwiftUI

/// Main dropdown panel View
struct DropdownPanel: View {
    @Bindable var coordinator: WatchCoordinator
    let onQuit: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if coordinator.projects.isEmpty {
                    EmptyStateView(watchState: coordinator.watchState)
                } else {
                    ForEach($coordinator.projects) { $project in
                        ProjectRow(project: $project)
                    }
                }
            }
            .padding(12)
        }
        .frame(minWidth: 320, minHeight: 300)
        .background(.ultraThinMaterial)
    }
}

#Preview {
    let coordinator = WatchCoordinator()

    return DropdownPanel(coordinator: coordinator) {
        print("Quit")
    }
}
