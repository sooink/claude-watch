import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ClaudeWatch", category: "SocketServer")

/// Unix domain socket server for receiving Claude Code hook events
final class SocketServer {
    private let socketPath = "/tmp/claude-watch.sock"
    private var serverSocket: Int32 = -1
    private var isRunning = false
    private var acceptThread: Thread?

    /// Callback when a hook event is received
    var onEventReceived: ((HookEvent) -> Void)?

    func start() {
        guard !isRunning else { return }

        // Remove existing socket file
        unlink(socketPath)

        // Create socket
        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            logger.error("Failed to create socket: \(errno)")
            return
        }

        // Bind to socket path
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
            pathBytes.withUnsafeBufferPointer { srcPtr in
                let destPtr = UnsafeMutableRawPointer(pathPtr).assumingMemoryBound(to: CChar.self)
                for i in 0..<min(srcPtr.count, 104) {
                    destPtr[i] = srcPtr[i]
                }
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(serverSocket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            logger.error("Failed to bind socket: \(errno)")
            close(serverSocket)
            serverSocket = -1
            return
        }

        // Listen for connections
        guard listen(serverSocket, 5) == 0 else {
            logger.error("Failed to listen: \(errno)")
            close(serverSocket)
            serverSocket = -1
            return
        }

        // Set socket permissions (allow all users)
        chmod(socketPath, 0o777)

        isRunning = true
        logger.info("Started at \(self.socketPath)")

        // Start accept loop in background thread
        acceptThread = Thread { [weak self] in
            self?.acceptLoop()
        }
        acceptThread?.name = "SocketServer.acceptLoop"
        acceptThread?.start()
    }

    func stop() {
        guard isRunning else { return }

        isRunning = false

        // Close server socket to unblock accept()
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }

        // Remove socket file
        unlink(socketPath)

        logger.info("Stopped")
    }

    private func acceptLoop() {
        while isRunning && serverSocket >= 0 {
            var clientAddr = sockaddr_un()
            var clientAddrLen = socklen_t(MemoryLayout<sockaddr_un>.size)

            let clientSocket = withUnsafeMutablePointer(to: &clientAddr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    accept(serverSocket, sockaddrPtr, &clientAddrLen)
                }
            }

            guard clientSocket >= 0 else {
                if isRunning {
                    logger.error("Accept failed: \(errno)")
                }
                continue
            }

            // Handle client in separate thread
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.handleClient(clientSocket)
            }
        }
    }

    private func handleClient(_ clientSocket: Int32) {
        defer { close(clientSocket) }

        // Read data from client
        var buffer = [CChar](repeating: 0, count: 4096)
        let bytesRead = read(clientSocket, &buffer, buffer.count - 1)

        guard bytesRead > 0 else { return }

        buffer[bytesRead] = 0
        let data = String(cString: buffer)

        // Parse JSON
        guard let jsonData = data.data(using: .utf8) else { return }

        do {
            let event = try JSONDecoder().decode(HookEvent.self, from: jsonData)
            logger.info("Received event: \(event.event.rawValue) for session: \(event.sessionId)")

            // Dispatch to main thread for UI updates
            DispatchQueue.main.async { [weak self] in
                self?.onEventReceived?(event)
            }
        } catch {
            logger.error("Failed to parse event: \(error.localizedDescription), data: \(data)")
        }
    }

    deinit {
        stop()
    }
}
