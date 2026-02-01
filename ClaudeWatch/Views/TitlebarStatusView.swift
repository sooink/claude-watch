import SwiftUI

/// Titlebar status indicator View
struct TitlebarStatusView: View {
    @Bindable var coordinator: WatchCoordinator
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIconName)
                .foregroundColor(statusColor)
                .font(.system(size: 12))
                .opacity(coordinator.watchState == .watching ? (isPulsing ? 0.2 : 1.0) : 1.0)
                .animation(
                    coordinator.watchState == .watching
                        ? .easeInOut(duration: 1.5).repeatForever(autoreverses: true)
                        : .default,
                    value: isPulsing
                )
                .onAppear {
                    if coordinator.watchState == .watching {
                        isPulsing = true
                    }
                }
                .onChange(of: coordinator.watchState) { _, newValue in
                    isPulsing = newValue == .watching
                }

            Text(coordinator.watchState.displayText)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(.trailing, 15)
    }

    private var statusIconName: String {
        switch coordinator.watchState {
        case .stopped:
            return "circle"
        case .watching, .active:
            return "circle.fill"
        }
    }

    private var statusColor: Color {
        switch coordinator.watchState {
        case .stopped, .watching:
            return Color(NSColor.tertiaryLabelColor)
        case .active:
            return Color(red: 0.0, green: 0.478, blue: 1.0)
        }
    }
}
