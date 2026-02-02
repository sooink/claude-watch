import SwiftUI

extension Notification.Name {
    static let showHookSetup = Notification.Name("showHookSetup")
}

/// Settings panel view
struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var hookInstalled = false
    @State private var errorMessage: String?
    @State private var isProcessing = false
    @State private var notificationPermissionDenied = false

    private let installer = HookInstaller.shared
    private let notificationManager = NotificationManager.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { settings.hookEnabled },
                    set: { newValue in
                        handleHookToggle(newValue)
                    }
                )) {
                    HStack(spacing: 8) {
                        Text("Enable Hook Integration")
                        statusBadge
                    }
                }
                .disabled(isProcessing)

                if settings.hookEnabled {
                    Toggle("Show Session Indicator", isOn: $settings.indicatorEnabled)
                        .padding(.leading, 20)

                    Toggle(isOn: Binding(
                        get: { settings.notificationEnabled },
                        set: { newValue in
                            handleNotificationToggle(newValue)
                        }
                    )) {
                        Text("Send Notifications on Completion")
                    }
                    .padding(.leading, 20)

                    if settings.notificationEnabled && notificationPermissionDenied {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Notifications are disabled in System Settings.")
                                .font(.callout)
                            Spacer()
                            Button("Open Settings") {
                                notificationManager.openNotificationSettings()
                            }
                            .buttonStyle(.link)
                        }
                        .padding(.leading, 20)
                    }
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            } header: {
                Text("Hook Settings")
            } footer: {
                Text("Enabling hook integration automatically installs the hook script. Disabling removes it.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            Section {
                Button("View Hook Setup Guide") {
                    NotificationCenter.default.post(name: .showHookSetup, object: nil)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            hookInstalled = installer.isInstalled
            checkNotificationPermission()
        }
        .onChange(of: settings.notificationEnabled) { _, newValue in
            if newValue {
                checkNotificationPermission()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            checkNotificationPermission()
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 4) {
            if settings.hookEnabled {
                Image(systemName: hookInstalled ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundColor(hookInstalled ? .green : .orange)
                Text(hookInstalled ? "Installed" : "Not installed")
            } else {
                Image(systemName: "circle")
                    .foregroundColor(.secondary)
                Text("Uninstalled")
            }
        }
        .font(.callout)
        .foregroundColor(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.1))
        )
    }

    private func handleHookToggle(_ enabled: Bool) {
        isProcessing = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                if enabled {
                    // Install hook when enabling
                    try installer.install()
                } else {
                    // Uninstall hook when disabling
                    try installer.uninstall()
                }

                DispatchQueue.main.async {
                    settings.hookEnabled = enabled
                    hookInstalled = installer.isInstalled
                    isProcessing = false
                }
            } catch {
                DispatchQueue.main.async {
                    errorMessage = "Failed: \(error.localizedDescription)"
                    isProcessing = false
                }
            }
        }
    }

    private func handleNotificationToggle(_ enabled: Bool) {
        settings.notificationEnabled = enabled

        if enabled {
            // Request permission and check status
            notificationManager.requestAuthorization { granted in
                notificationPermissionDenied = !granted
            }
        } else {
            notificationPermissionDenied = false
        }
    }

    private func checkNotificationPermission() {
        guard settings.notificationEnabled else {
            notificationPermissionDenied = false
            return
        }

        notificationManager.isAuthorized { authorized in
            notificationPermissionDenied = !authorized
        }
    }
}

#Preview {
    SettingsView()
}
