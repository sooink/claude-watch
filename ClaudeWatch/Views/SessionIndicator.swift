import SwiftUI

/// Session status indicator with blinking animation for working sessions
struct SessionIndicator: View {
    let status: SessionStatus

    @State private var isBlinking = false

    var body: some View {
        Circle()
            .fill(indicatorColor)
            .frame(width: 8, height: 8)
            .opacity(status == .working ? (isBlinking ? 0.4 : 1.0) : 1.0)
            .animation(
                status == .working
                    ? Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                    : .default,
                value: isBlinking
            )
            .onAppear {
                if status == .working {
                    isBlinking = true
                }
            }
            .onChange(of: status) { _, newStatus in
                isBlinking = (newStatus == .working)
            }
    }

    private var indicatorColor: Color {
        switch status {
        case .working:
            return .green
        case .idle:
            return .gray
        case .unknown:
            return .clear
        }
    }
}

#Preview("Working") {
    HStack(spacing: 16) {
        SessionIndicator(status: .working)
        Text("Working Session")
    }
    .padding()
}

#Preview("Idle") {
    HStack(spacing: 16) {
        SessionIndicator(status: .idle)
        Text("Idle Session")
    }
    .padding()
}
