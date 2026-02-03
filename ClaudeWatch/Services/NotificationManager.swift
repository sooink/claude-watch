import Foundation
import UserNotifications
import AppKit
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ClaudeWatch", category: "NotificationManager")

/// Manager for macOS notifications
final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        center.delegate = self
    }

    /// Request notification permission
    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                logger.error("Authorization error: \(error.localizedDescription)")
            } else {
                logger.info("Authorization granted: \(granted)")
            }
            DispatchQueue.main.async {
                completion?(granted)
            }
        }
    }

    /// Check if notifications are authorized
    func isAuthorized(completion: @escaping (Bool) -> Void) {
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings.authorizationStatus == .authorized)
            }
        }
    }

    /// Open System Settings > Notifications
    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Send session completed notification
    func sendSessionCompletedNotification(projectName: String, path: String) {
        logger.info("Sending notification for project: \(projectName)")

        // Check current authorization status first
        center.getNotificationSettings { [weak self] settings in
            logger.info("Notification authorization status: \(settings.authorizationStatus.rawValue)")
            logger.info("Alert setting: \(settings.alertSetting.rawValue)")

            guard settings.authorizationStatus == .authorized else {
                logger.warning("Notifications not authorized. Requesting permission...")
                self?.requestAuthorization()
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "Session Completed"
            content.body = "\(projectName) session has finished"
            content.sound = .default
            content.userInfo = ["path": path]

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil  // Deliver immediately
            )

            self?.center.add(request) { error in
                if let error = error {
                    logger.error("Failed to send notification: \(error.localizedDescription)")
                } else {
                    logger.info("Notification added to center successfully")
                }
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationManager: UNUserNotificationCenterDelegate {
    /// Show notification even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        // Open project path in terminal if tapped
        if let path = userInfo["path"] as? String {
            openTerminal(at: path)
        }

        completionHandler()
    }

    private func openTerminal(at path: String) {
        let escapedPath = path.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        tell application "Terminal"
            activate
            do script "cd '\(escapedPath)'"
        end tell
        """
        DispatchQueue.main.async {
            NSAppleScript(source: script)?.executeAndReturnError(nil)
        }
    }
}
