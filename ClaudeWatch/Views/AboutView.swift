import SwiftUI

/// About window View
struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            // App icon
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            // App name
            Text("Claude Watch")
                .font(.title2.bold())

            // Version
            Text("Version \(appVersion)")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
                .frame(height: 8)

            // Copyright
            Text("© 2026 sooink")
                .font(.caption2)
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
        }
        .padding(24)
        .frame(width: 240, height: 200)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }
}

#Preview {
    AboutView()
}
