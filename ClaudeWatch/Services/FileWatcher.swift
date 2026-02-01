import Foundation

/// File event type
enum FileEventType {
    case modified
    case removed
}

/// File event information
struct FileEvent {
    let path: String
    let type: FileEventType
}

/// File change monitoring with FSEvents API
final class FileWatcher {
    private var stream: FSEventStreamRef?
    private let paths: [String]
    private let callback: ([FileEvent]) -> Void
    private let latency: CFTimeInterval = 2.0

    init(paths: [String], callback: @escaping ([FileEvent]) -> Void) {
        self.paths = paths
        self.callback = callback
    }

    func start() {
        guard stream == nil else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer
        )

        stream = FSEventStreamCreate(
            nil,
            { (
                streamRef: ConstFSEventStreamRef,
                clientCallBackInfo: UnsafeMutableRawPointer?,
                numEvents: Int,
                eventPaths: UnsafeMutableRawPointer,
                eventFlags: UnsafePointer<FSEventStreamEventFlags>,
                eventIds: UnsafePointer<FSEventStreamEventId>
            ) in
                guard let info = clientCallBackInfo else { return }
                let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()

                let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]

                // Process paths and event flags together
                var events: [(path: String, flags: FSEventStreamEventFlags)] = []
                for i in 0..<numEvents {
                    events.append((paths[i], eventFlags[i]))
                }
                watcher.handleEvents(events: events)
            },
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        )

        guard let stream = stream else { return }

        FSEventStreamScheduleWithRunLoop(
            stream,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream = stream else { return }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func handleEvents(events: [(path: String, flags: FSEventStreamEventFlags)]) {
        // Filter JSONL files only and determine event type
        let fileEvents = events
            .filter { $0.path.hasSuffix(".jsonl") }
            .map { event -> FileEvent in
                // Detect deletion via kFSEventStreamEventFlagItemRemoved flag
                let isRemoved = (event.flags & UInt32(kFSEventStreamEventFlagItemRemoved)) != 0
                return FileEvent(
                    path: event.path,
                    type: isRemoved ? .removed : .modified
                )
            }

        if !fileEvents.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.callback(fileEvents)
            }
        }
    }

    deinit {
        stop()
    }
}
