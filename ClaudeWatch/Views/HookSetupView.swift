import SwiftUI

/// Hook setup guide view
struct HookSetupView: View {
    @State private var copiedScript = false
    @State private var copiedSettings = false
    @State private var installStatus: InstallStatus = .notInstalled
    @State private var errorMessage: String?

    private let socketPath = "/tmp/claude-watch.sock"

    enum InstallStatus {
        case notInstalled
        case installing
        case installed
        case failed
    }

    private var hookScript: String {
        HookInstaller.shared.hookScriptTemplate
    }

    private var settingsJson: String {
        """
        {
          "hooks": {
            "UserPromptSubmit": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "~/.claude/hooks/claude-watch-hook.sh UserPromptSubmit"
                  }
                ]
              }
            ],
            "Stop": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "~/.claude/hooks/claude-watch-hook.sh Stop"
                  }
                ]
              }
            ]
          }
        }
        """
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Auto Install Section
                VStack(alignment: .leading, spacing: 14) {
                    Button(action: installHook) {
                        HStack(spacing: 8) {
                            if installStatus == .installing {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 16, height: 16)
                            } else {
                                Image(systemName: installStatus == .installed ? "checkmark.circle.fill" : "arrow.down.circle")
                            }
                            Text(installButtonTitle)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(installStatus == .installing)

                    if installStatus == .installed {
                        Text("Hook installed successfully!")
                            .font(.callout)
                            .foregroundColor(.green)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.callout)
                            .foregroundColor(.red)
                    }

                    Text("Automatically creates the hook script and updates Claude Code settings.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.1)))

                Divider()

                Text("Manual Installation")
                    .font(.headline)
                    .foregroundColor(.secondary)

                // Step 1
                stepView(number: 1, title: "Create Hook Script") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Save this script to `~/.claude/hooks/claude-watch-hook.sh`:")
                            .font(.callout)
                            .foregroundColor(.secondary)

                        codeBlock(hookScript, copied: copiedScript) {
                            copyToClipboard(hookScript)
                            copiedScript = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copiedScript = false
                            }
                        }

                        Text("Make it executable:")
                            .font(.callout)
                            .foregroundColor(.secondary)

                        codeBlock("chmod +x ~/.claude/hooks/claude-watch-hook.sh", copied: false) {
                            copyToClipboard("chmod +x ~/.claude/hooks/claude-watch-hook.sh")
                        }
                    }
                }

                // Step 2
                stepView(number: 2, title: "Configure Claude Code") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Add hooks to `~/.claude/settings.json`:")
                            .font(.callout)
                            .foregroundColor(.secondary)

                        codeBlock(settingsJson, copied: copiedSettings) {
                            copyToClipboard(settingsJson)
                            copiedSettings = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copiedSettings = false
                            }
                        }
                    }
                }

                // Step 3
                stepView(number: 3, title: "Enable in Claude Watch") {
                    Text("Toggle \"Enable Hook Integration\" in Settings to start receiving events.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }

                // Test section
                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Test Commands")
                        .font(.headline)

                    Text("You can test the hook manually:")
                        .font(.callout)
                        .foregroundColor(.secondary)

                    codeBlock(
                        "echo '{\"event\":\"UserPromptSubmit\",\"session_id\":\"test\",\"cwd\":\"/tmp\"}' | nc -U \(socketPath)",
                        copied: false
                    ) {
                        copyToClipboard("echo '{\"event\":\"UserPromptSubmit\",\"session_id\":\"test\",\"cwd\":\"/tmp\"}' | nc -U \(socketPath)")
                    }
                }
            }
            .padding(28)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.visible)
        .frame(width: 580, height: 620)
        .onAppear {
            checkInstallStatus()
        }
    }

    private func checkInstallStatus() {
        if HookInstaller.shared.isInstalled {
            installStatus = .installed
        }
    }

    @ViewBuilder
    private func stepView(number: Int, title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("\(number)")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.accentColor))

                Text(title)
                    .font(.headline)
            }

            content()
                .padding(.leading, 28)
        }
    }

    @ViewBuilder
    private func codeBlock(_ code: String, copied: Bool, onCopy: @escaping () -> Void) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack {
                Spacer()
                Button(action: onCopy) {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Copied!" : "Copy")
                    }
                    .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(NSColor.textBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private var installButtonTitle: String {
        switch installStatus {
        case .notInstalled, .failed:
            return "Install Hook Automatically"
        case .installing:
            return "Installing..."
        case .installed:
            return "Reinstall Hook"
        }
    }

    private func installHook() {
        installStatus = .installing
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try HookInstaller.shared.install()

                DispatchQueue.main.async {
                    installStatus = .installed
                }
            } catch {
                DispatchQueue.main.async {
                    installStatus = .failed
                    errorMessage = "Installation failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

#Preview {
    HookSetupView()
}
