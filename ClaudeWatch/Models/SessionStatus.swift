import Foundation

/// Hook-based session status
enum SessionStatus: String, Codable {
    case working   // Claude is working (UserPromptSubmit received)
    case idle      // Session is idle (Stop received)
    case unknown   // No hook event received yet
}
