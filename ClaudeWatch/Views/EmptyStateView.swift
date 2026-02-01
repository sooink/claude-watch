import SwiftUI

/// Empty state View
struct EmptyStateView: View {
    let watchState: WatchState
    @State private var isPulsing = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: iconName)
                .font(.system(size: 40))
                .foregroundColor(Color(red: 0.557, green: 0.557, blue: 0.576))
                .opacity(watchState == .watching ? (isPulsing ? 0.2 : 1.0) : 1.0)
                .animation(
                    watchState == .watching
                        ? .easeInOut(duration: 1.5).repeatForever(autoreverses: true)
                        : .default,
                    value: isPulsing
                )
                .onAppear {
                    if watchState == .watching {
                        isPulsing = true
                    }
                }
                .onChange(of: watchState) { _, newValue in
                    isPulsing = newValue == .watching
                }

            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var iconName: String {
        switch watchState {
        case .stopped:
            return "circle"
        case .watching:
            return "circle.fill"
        case .active:
            return "checkmark.circle"
        }
    }

    private var title: String {
        switch watchState {
        case .stopped:
            return "Claude Code is not running"
        case .watching:
            return "Watching"
        case .active:
            return "No active sessions"
        }
    }

    private var subtitle: String {
        switch watchState {
        case .stopped:
            return "Monitoring will start automatically\nwhen Claude Code launches"
        case .watching:
            return "Projects will appear automatically\nwhen Claude Code activity is detected"
        case .active:
            return "No active sessions at the moment"
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        EmptyStateView(watchState: .stopped)
        Divider()
        EmptyStateView(watchState: .watching)
    }
    .frame(width: 300)
    .padding()
}
