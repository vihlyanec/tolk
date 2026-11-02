import Foundation

/// Deadlines, rather than tick counts, preserve a session across sleep and relaunch.
public struct Pomodoro: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable { case focus, shortBreak, longBreak }
    public var taskID: UUID
    public var title: String
    public var phase: Phase = .focus
    public var completed = 0
    public var deadline: Date?
    public var remaining: TimeInterval = 25 * 60
    public init(taskID: UUID, title: String, now: Date = Date()) {
        self.taskID = taskID; self.title = title; deadline = now.addingTimeInterval(remaining)
    }
    public func seconds(at now: Date) -> Int { max(0, Int(ceil(deadline.map { $0.timeIntervalSince(now) } ?? remaining))) }
    public mutating func pause(at now: Date) {
        guard let deadline else { return }
        remaining = max(0, deadline.timeIntervalSince(now)); self.deadline = nil
    }
    public mutating func resume(at now: Date) {
        guard deadline == nil, remaining > 0 else { return }
        deadline = now.addingTimeInterval(remaining)
    }
    /// A finished phase waits for explicit consent before starting the next one.
    public mutating func next(at now: Date) {
        guard seconds(at: now) == 0 else { return }
        if phase == .focus {
            completed += 1; phase = completed.isMultiple(of: 4) ? .longBreak : .shortBreak
        } else { phase = .focus }
        remaining = phase == .focus ? 1500 : phase == .longBreak ? 900 : 300
        deadline = now.addingTimeInterval(remaining)
    }
}
