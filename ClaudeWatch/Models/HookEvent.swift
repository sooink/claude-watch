import Foundation

/// Hook event received via Unix socket
struct HookEvent: Codable {
    let event: HookEventType
    let sessionId: String
    let cwd: String

    enum CodingKeys: String, CodingKey {
        case event
        case sessionId = "session_id"
        case cwd
    }
}

/// Hook event types from Claude Code
enum HookEventType: String, Codable {
    case userPromptSubmit = "UserPromptSubmit"
    case stop = "Stop"
}
