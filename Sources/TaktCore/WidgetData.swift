import Darwin
import Foundation

public struct WidgetTask: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let date: Date?
    public let timed: Bool
    public let priority: Int
    public let revision: Date

    public init(id: UUID, title: String, date: Date?, timed: Bool, priority: Int, revision: Date) {
        self.id = id
        self.title = title
        self.date = date
        self.timed = timed
        self.priority = priority
        self.revision = revision
    }
}

public struct WidgetTaskList: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let tasks: [WidgetTask]

    public init(id: String, title: String, tasks: [WidgetTask]) {
        self.id = id
        self.title = title
        self.tasks = tasks
    }
}

public struct WidgetData: Codable, Equatable, Sendable {
    public var lists: [WidgetTaskList] = []
    public var completions: [UUID: Date] = [:]
    public var timeZone = "Europe/Moscow"

    public func tasks(in list: WidgetTaskList) -> [WidgetTask] {
        list.tasks.filter { completions[$0.id] != $0.revision }
    }
}

/// The widget queues versioned completion requests. Only the app edits its database.
public struct WidgetStore: Sendable {
    public static let appBundle = "local.takt.mac"
    public static let demoBundle = "local.takt.widgetdemo"
    private static let bundleID = Bundle.main.bundleIdentifier ?? ""
    private static let isDemo = bundleID == demoBundle || bundleID == demoBundle + ".tasks"
    public static let kind = (isDemo ? demoBundle : appBundle) + ".tasks"
    public static let scheme = isDemo ? "tolk-widget-demo" : "tolk-widget"
    public static let appName = isDemo ? "Толк Demo" : "Толк"
    public static let installed: Self? = {
        guard isDemo || bundleID == appBundle || bundleID == kind else { return nil }
        guard let home = getpwuid(getuid())?.pointee.pw_dir else { return nil }
        let directory = URL(fileURLWithPath: String(cString: home), isDirectory: true)
            .appendingPathComponent(isDemo ? "Library/Application Support/TolkWidgetDemo" : "Library/Application Support/TolkWidgets",
                                    isDirectory: true)
        return Self(directory: directory)
    }()

    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    private var dataURL: URL { directory.appendingPathComponent("widget.json") }

    public var modificationDate: Date? {
        (try? FileManager.default.attributesOfItem(atPath: dataURL.path))?[.modificationDate] as? Date
    }

    public func read() throws -> WidgetData {
        try access { $0 }
    }

    @discardableResult public func publish(_ lists: [WidgetTaskList], timeZone: String) throws -> Bool {
        try access { data in
            let changed = data.lists != lists || data.timeZone != timeZone
            guard changed else { return false }
            var revisions: [UUID: Date] = [:]
            for list in lists {
                for task in list.tasks { revisions[task.id] = task.revision }
            }
            data.lists = lists
            data.timeZone = timeZone
            data.completions = data.completions.filter { revisions[$0.key] == $0.value }
            return true
        }
    }

    @discardableResult public func complete(_ id: UUID, revision: Date) throws -> Bool {
        try access { data in
            guard data.lists.contains(where: { list in list.tasks.contains { $0.id == id && $0.revision == revision } }) else { return false }
            data.completions[id] = revision
            return true
        }
    }

    private func access<Value>(_ update: (inout WidgetData) throws -> Value) throws -> Value {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let directoryDescriptor = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directoryDescriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(directoryDescriptor) }
        var info = stat()
        guard fstat(directoryDescriptor, &info) == 0, info.st_uid == geteuid(), fchmod(directoryDescriptor, 0o700) == 0 else {
            throw POSIXError(.EACCES)
        }
        let lockURL = directory.appendingPathComponent("widget.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        guard fstat(descriptor, &info) == 0, info.st_uid == geteuid(), info.st_mode & S_IFMT == S_IFREG else {
            throw POSIXError(.EACCES)
        }
        while flock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        let previous = try readData(in: directoryDescriptor)
        var data = previous
        let result = try update(&data)
        if data != previous { try JSONEncoder().encode(data).write(to: dataURL, options: .atomic) }
        return result
    }

    private func readData(in directoryDescriptor: Int32) throws -> WidgetData {
        let descriptor = openat(directoryDescriptor, "widget.json", O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        if descriptor == -1 && errno == ENOENT { return WidgetData() }
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == geteuid(), info.st_mode & S_IFMT == S_IFREG else {
            throw POSIXError(.EACCES)
        }
        return try JSONDecoder().decode(WidgetData.self, from: file.readToEnd() ?? Data())
    }
}
