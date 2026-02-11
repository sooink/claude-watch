import Foundation

/// Hook event received via Unix socket
struct HookEvent: Codable {
    let event: HookEventType
    let sessionId: String
    let cwd: String
    let toolName: String?
    let toolUseId: String?
    let taskDescription: String?
    let subagentType: String?

    enum CodingKeys: String, CodingKey {
        case event
        case sessionId = "session_id"
        case cwd
        case toolName = "tool_name"
        case toolUseId = "tool_use_id"
        case taskDescription = "task_description"
        case subagentType = "subagent_type"
    }
}

/// Hook event types from Claude Code
enum HookEventType: String, Codable {
    case userPromptSubmit = "UserPromptSubmit"
    case stop = "Stop"
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case postToolUseFailure = "PostToolUseFailure"
}
