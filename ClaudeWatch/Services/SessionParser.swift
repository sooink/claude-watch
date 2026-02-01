import Foundation

/// JSONL file parsing result entry
struct JSONLEntry {
    let type: String
    let timestamp: Date?
    let cwd: String?
    let message: MessageContent?

    struct MessageContent {
        let content: [ContentItem]
    }

    struct ContentItem {
        let type: String
        let id: String?
        let name: String?
        let input: [String: Any]?
        let toolUseId: String?
        let content: Any?  // String or Array
    }

    init?(json: [String: Any]) {
        guard let type = json["type"] as? String else { return nil }
        self.type = type

        // Parse cwd
        self.cwd = json["cwd"] as? String

        // Parse timestamp
        if let timestampString = json["timestamp"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            self.timestamp = formatter.date(from: timestampString)
        } else {
            self.timestamp = nil
        }

        // Parse message
        if let messageDict = json["message"] as? [String: Any],
           let contentArray = messageDict["content"] as? [[String: Any]] {
            let items = contentArray.compactMap { item -> ContentItem? in
                guard let itemType = item["type"] as? String else { return nil }
                return ContentItem(
                    type: itemType,
                    id: item["id"] as? String,
                    name: item["name"] as? String,
                    input: item["input"] as? [String: Any],
                    toolUseId: item["tool_use_id"] as? String,
                    content: item["content"] as? String
                )
            }
            self.message = MessageContent(content: items)
        } else {
            self.message = nil
        }
    }
}

/// Tool Use event
struct ToolUseEvent {
    let id: String
    let name: String
    let input: [String: Any]
    let timestamp: Date?
}

/// JSONL file incremental parsing
final class SessionParser {
    private var fileOffsets: [String: UInt64] = [:]

    /// Parse new entries
    func parseNewEntries(at path: String) -> [JSONLEntry] {
        let offset = fileOffsets[path] ?? 0

        guard FileManager.default.fileExists(atPath: path),
              let handle = FileHandle(forReadingAtPath: path) else {
            return []
        }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: offset)
            let data = handle.readDataToEndOfFile()
            fileOffsets[path] = try handle.offset()

            guard let content = String(data: data, encoding: .utf8), !content.isEmpty else {
                return []
            }

            return content
                .split(separator: "\n", omittingEmptySubsequences: true)
                .compactMap { line -> JSONLEntry? in
                    guard let lineData = String(line).data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
                    else { return nil }
                    return JSONLEntry(json: json)
                }
        } catch {
            return []
        }
    }

    /// Extract Tool Use events
    func extractToolUse(from entries: [JSONLEntry]) -> [ToolUseEvent] {
        entries.compactMap { entry -> [ToolUseEvent]? in
            guard entry.type == "assistant",
                  let content = entry.message?.content else { return nil }

            return content.compactMap { item -> ToolUseEvent? in
                guard item.type == "tool_use",
                      let id = item.id,
                      let name = item.name,
                      let input = item.input else { return nil }

                return ToolUseEvent(id: id, name: name, input: input, timestamp: entry.timestamp)
            }
        }.flatMap { $0 }
    }

    /// Extract Tool Result
    func extractToolResult(from entries: [JSONLEntry]) -> [(toolUseId: String, content: String, timestamp: Date?)] {
        entries.compactMap { entry -> [(toolUseId: String, content: String, timestamp: Date?)]? in
            guard entry.type == "user",
                  let content = entry.message?.content else { return nil }

            return content.compactMap { item -> (toolUseId: String, content: String, timestamp: Date?)? in
                guard item.type == "tool_result",
                      let toolUseId = item.toolUseId else { return nil }

                // content can be String or Array
                let resultContent: String
                if let stringContent = item.content as? String {
                    resultContent = stringContent
                } else if let arrayContent = item.content as? [[String: Any]] {
                    // Extract first text item if array
                    resultContent = arrayContent
                        .compactMap { $0["text"] as? String }
                        .joined(separator: "\n")
                } else {
                    resultContent = ""
                }

                return (toolUseId: toolUseId, content: resultContent, timestamp: entry.timestamp)
            }
        }.flatMap { $0 }
    }

    /// Move offset to end of file (without parsing)
    func skipToEnd(for path: String) {
        guard FileManager.default.fileExists(atPath: path),
              let handle = FileHandle(forReadingAtPath: path) else { return }
        defer { try? handle.close() }

        do {
            try handle.seekToEnd()
            fileOffsets[path] = try handle.offset()
        } catch {}
    }

    /// Reset file offset
    func reset(for path: String) {
        fileOffsets.removeValue(forKey: path)
    }

    /// Remove file info (deleted file)
    func removeFile(_ path: String) {
        fileOffsets.removeValue(forKey: path)
    }

    /// Reset all offsets
    func resetAll() {
        fileOffsets.removeAll()
    }

    /// Find subagent log files
    func findSubagentLogs(for sessionPath: String) -> [String] {
        let sessionDir = sessionPath.replacingOccurrences(of: ".jsonl", with: "")
        let subagentsDir = sessionDir + "/subagents/"

        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: subagentsDir) else {
            return []
        }

        return contents
            .filter { $0.hasPrefix("agent-") && $0.hasSuffix(".jsonl") }
            .map { subagentsDir + $0 }
    }

    /// Extract agent info (from Task tool input)
    func extractAgentInfo(from input: [String: Any]) -> (description: String, type: String)? {
        let description = input["description"] as? String ?? "Agent"
        let type = input["subagent_type"] as? String ?? "general-purpose"
        return (description, type)
    }

    /// Extract TaskItem info (from TaskCreate input)
    func extractTaskItemInfo(from input: [String: Any]) -> (subject: String, description: String, activeForm: String?)? {
        guard let subject = input["subject"] as? String else { return nil }
        let description = input["description"] as? String ?? ""
        let activeForm = input["activeForm"] as? String
        return (subject, description, activeForm)
    }

    /// Extract TaskUpdate info
    func extractTaskUpdateInfo(from input: [String: Any]) -> (taskId: String, status: String?)? {
        guard let taskId = input["taskId"] as? String else { return nil }
        let status = input["status"] as? String
        return (taskId, status)
    }

    /// Extract project path (cwd)
    func extractCwd(from entries: [JSONLEntry]) -> String? {
        for entry in entries {
            if let cwd = entry.cwd {
                return cwd
            }
        }
        return nil
    }
}
