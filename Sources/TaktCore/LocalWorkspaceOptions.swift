import Foundation

public struct SavedQueueFilter: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var inboxOnly: Bool
    public var projectID: UUID?
    public var tagID: UUID?
    public var priority: Int?
    public var dateFilter: String
    public var search: String
    public var sorting: String

    public init(id: UUID = UUID(), name: String, inboxOnly: Bool, projectID: UUID?, tagID: UUID?, priority: Int?,
                dateFilter: String, search: String, sorting: String) {
        self.id = id
        self.name = name
        self.inboxOnly = inboxOnly
        self.projectID = projectID
        self.tagID = tagID
        self.priority = priority
        self.dateFilter = dateFilter
        self.search = search
        self.sorting = sorting
    }
}

public struct FocusCompletion: Codable, Equatable, Sendable {
    public let taskID: UUID
    public let finishedAt: Date

    public init(taskID: UUID, finishedAt: Date) {
        self.taskID = taskID
        self.finishedAt = finishedAt
    }
}

/// Per-Mac presentation preferences and focus history kept with local backups.
public struct LocalWorkspaceOptions: Codable, Equatable, Sendable {
    public var compactTaskLists = Set<String>()
    public var queueFilters: [SavedQueueFilter] = []
    public var completedFocus: [FocusCompletion] = []
    public init() {}
}
