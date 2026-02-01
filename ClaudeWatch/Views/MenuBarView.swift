import SwiftUI

/// Menu bar icon View
struct MenuBarView: View {
    let watchState: WatchState
    let activeAgentCount: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: iconName)
                .foregroundColor(iconColor)
                .font(.system(size: 12))

            if activeAgentCount > 0 {
                Text("\(activeAgentCount)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(iconColor)
            }
        }
    }

    private var iconName: String {
        switch watchState {
        case .stopped:
            return "circle"
        case .watching, .active:
            return "circle.fill"
        }
    }

    private var iconColor: Color {
        switch watchState {
        case .stopped, .watching:
            return Color(red: 0.557, green: 0.557, blue: 0.576) // #8E8E93
        case .active:
            return Color(red: 0.0, green: 0.478, blue: 1.0)     // #007AFF
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        MenuBarView(watchState: .stopped, activeAgentCount: 0)
        MenuBarView(watchState: .watching, activeAgentCount: 0)
        MenuBarView(watchState: .active, activeAgentCount: 0)
        MenuBarView(watchState: .active, activeAgentCount: 3)
    }
    .padding()
}
