import Foundation

/// Hook installation and uninstallation service
final class HookInstaller {
    static let shared = HookInstaller()

    private let scriptPath = NSHomeDirectory() + "/.claude/hooks/claude-watch-hook.sh"
    private let settingsPath = NSHomeDirectory() + "/.claude/settings.json"
    private let socketPath = "/tmp/claude-watch.sock"

    private init() {}

    /// Check if hook is installed
    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: scriptPath)
    }

    /// Install hook script and update settings.json
    func install() throws {
        // 1. Create hooks directory
        let hooksDir = NSHomeDirectory() + "/.claude/hooks"
        try FileManager.default.createDirectory(atPath: hooksDir, withIntermediateDirectories: true)

        // 2. Write hook script
        try hookScript.write(toFile: scriptPath, atomically: true, encoding: .utf8)

        // 3. Make executable (chmod +x)
        let attrs: [FileAttributeKey: Any] = [.posixPermissions: 0o755]
        try FileManager.default.setAttributes(attrs, ofItemAtPath: scriptPath)

        // 4. Update settings.json
        try addHooksToSettings()
    }

    /// Uninstall hook script and remove from settings.json
    func uninstall() throws {
        // 1. Remove hook script
        if FileManager.default.fileExists(atPath: scriptPath) {
            try FileManager.default.removeItem(atPath: scriptPath)
        }

        // 2. Remove hooks from settings.json
        try removeHooksFromSettings()
    }

    // MARK: - Private

    private var hookScript: String {
        """
        #!/bin/bash
        # Claude Watch Hook Script

        EVENT_NAME="$1"

        # Only handle UserPromptSubmit and Stop events
        if [[ "$EVENT_NAME" != "UserPromptSubmit" && "$EVENT_NAME" != "Stop" ]]; then
            exit 0
        fi

        SOCKET_PATH="\(socketPath)"

        # Check if socket exists
        if [[ ! -S "$SOCKET_PATH" ]]; then
            exit 0
        fi

        # Get session_id from CLAUDE_SESSION_ID env var
        SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"

        # Send event to Claude Watch
        echo "{\\\"event\\\":\\\"$EVENT_NAME\\\",\\\"session_id\\\":\\\"$SESSION_ID\\\",\\\"cwd\\\":\\\"$PWD\\\"}" | nc -U "$SOCKET_PATH" 2>/dev/null

        exit 0
        """
    }

    private func addHooksToSettings() throws {
        var settings = try loadSettings()

        // New hook format requires matcher groups with nested hooks array
        // Format: { "matcher": "...", "hooks": [{ "type": "command", "command": "..." }] }
        let userPromptSubmitMatcherGroup: [String: Any] = [
            "hooks": [
                [
                    "type": "command",
                    "command": "~/.claude/hooks/claude-watch-hook.sh UserPromptSubmit"
                ]
            ]
        ]
        let stopMatcherGroup: [String: Any] = [
            "hooks": [
                [
                    "type": "command",
                    "command": "~/.claude/hooks/claude-watch-hook.sh Stop"
                ]
            ]
        ]

        // Get or create hooks dictionary
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        // Update UserPromptSubmit hooks
        var userPromptSubmitGroups = hooks["UserPromptSubmit"] as? [[String: Any]] ?? []
        if !userPromptSubmitGroups.contains(where: { isClaudeWatchMatcherGroup($0) }) {
            userPromptSubmitGroups.append(userPromptSubmitMatcherGroup)
        }
        hooks["UserPromptSubmit"] = userPromptSubmitGroups

        // Update Stop hooks
        var stopGroups = hooks["Stop"] as? [[String: Any]] ?? []
        if !stopGroups.contains(where: { isClaudeWatchMatcherGroup($0) }) {
            stopGroups.append(stopMatcherGroup)
        }
        hooks["Stop"] = stopGroups

        settings["hooks"] = hooks

        try saveSettings(settings)
    }

    private func removeHooksFromSettings() throws {
        var settings = try loadSettings()

        guard var hooks = settings["hooks"] as? [String: Any] else { return }

        // Remove Claude Watch matcher groups from UserPromptSubmit
        if var userPromptSubmitGroups = hooks["UserPromptSubmit"] as? [[String: Any]] {
            userPromptSubmitGroups.removeAll { isClaudeWatchMatcherGroup($0) }
            if userPromptSubmitGroups.isEmpty {
                hooks.removeValue(forKey: "UserPromptSubmit")
            } else {
                hooks["UserPromptSubmit"] = userPromptSubmitGroups
            }
        }

        // Remove Claude Watch matcher groups from Stop
        if var stopGroups = hooks["Stop"] as? [[String: Any]] {
            stopGroups.removeAll { isClaudeWatchMatcherGroup($0) }
            if stopGroups.isEmpty {
                hooks.removeValue(forKey: "Stop")
            } else {
                hooks["Stop"] = stopGroups
            }
        }

        // Remove hooks key if empty
        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }

        try saveSettings(settings)
    }

    /// Check if a matcher group or old-format hook contains Claude Watch hooks
    private func isClaudeWatchMatcherGroup(_ entry: [String: Any]) -> Bool {
        // New format: { "hooks": [{ "command": "..." }] }
        if let hooksArray = entry["hooks"] as? [[String: Any]] {
            return hooksArray.contains { hook in
                guard let command = hook["command"] as? String else { return false }
                return command.contains("claude-watch-hook.sh")
            }
        }

        // Old format: { "type": "command", "command": "..." }
        if let command = entry["command"] as? String {
            return command.contains("claude-watch-hook.sh")
        }

        return false
    }

    private func loadSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsPath) else {
            return [:]
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: settingsPath))
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    private func saveSettings(_ settings: [String: Any]) throws {
        let jsonData = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try jsonData.write(to: URL(fileURLWithPath: settingsPath))
    }
}
