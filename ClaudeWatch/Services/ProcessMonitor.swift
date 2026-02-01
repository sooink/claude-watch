import Foundation

/// Claude process detection
@Observable
final class ProcessMonitor {
    var isClaudeRunning: Bool = false

    private var timer: Timer?
    private let checkInterval: TimeInterval = 5.0

    var onClaudeDetected: (() -> Void)?
    var onClaudeTerminated: (() -> Void)?

    func start() {
        // Run immediately once
        checkProcess()

        // Start timer
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.checkProcess()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkProcess() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", "claude"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            let wasRunning = isClaudeRunning
            isClaudeRunning = task.terminationStatus == 0

            // State change callback
            if isClaudeRunning && !wasRunning {
                DispatchQueue.main.async { [weak self] in
                    self?.onClaudeDetected?()
                }
            } else if !isClaudeRunning && wasRunning {
                DispatchQueue.main.async { [weak self] in
                    self?.onClaudeTerminated?()
                }
            }
        } catch {
            isClaudeRunning = false
        }
    }

    deinit {
        stop()
    }
}
