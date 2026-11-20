import Foundation

public struct TaskActivity: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var date: Date
    public var changes: [String]

    public static func label(_ key: String) -> String {
        switch key {
        case "completed": "Задача завершена"
        case "wontDo": "Решено не выполнять"
        case "reopened": "Возвращена в работу"
        case "deleted": "Перемещена в корзину"
        case "restored": "Восстановлена из корзины"
        case "title": "Изменено название"
        case "body": "Изменено описание"
        case "project": "Изменён проект"
        case "section": "Изменён этап"
        case "schedule": "Изменены дата или время"
        case "priority": "Изменён приоритет"
        case "tags": "Изменены теги"
        case "checklist": "Изменён чек-лист"
        case "recurrence": "Изменён повтор"
        case "reminders": "Изменены напоминания"
        default: "Задача изменена"
        }
    }

    static func changes(from old: Item, to item: Item) -> [String] {
        var result: [String] = []
        if old.completed != item.completed || (old.wontDoAt != nil) != (item.wontDoAt != nil) {
            result.append(item.completed ? "completed" : item.wontDoAt != nil ? "wontDo" : "reopened")
        }
        if old.deleted != item.deleted { result.append(item.deleted ? "deleted" : "restored") }
        if old.title != item.title { result.append("title") }
        if old.body != item.body { result.append("body") }
        if old.projectID != item.projectID { result.append("project") }
        if old.section != item.section { result.append("section") }
        if old.schedule != item.schedule || old.duration != item.duration { result.append("schedule") }
        if old.priority != item.priority { result.append("priority") }
        if Set(old.tagIDs) != Set(item.tagIDs) { result.append("tags") }
        if old.checklist != item.checklist { result.append("checklist") }
        if old.recurrence != item.recurrence || old.repeatEveryDays != item.repeatEveryDays { result.append("recurrence") }
        if old.reminderMinutes != item.reminderMinutes || old.timedReminderOffsets != item.timedReminderOffsets || old.allDayReminders != item.allDayReminders { result.append("reminders") }
        return result
    }
}

extension Snapshot {
    public mutating func recordTaskChanges(since previous: Snapshot, at date: Date = Date()) {
        guard items != previous.items else { return }
        let originals = Dictionary(previous.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for index in items.indices where items[index].kind == .task {
            guard let old = originals[items[index].id] else {
                if items[index].completedAt != nil || items[index].wontDoAt != nil, items[index].taskActivity == nil {
                    items[index].taskActivity = [TaskActivity(date: date, changes: [items[index].completed ? "completed" : "wontDo"])]
                }
                continue
            }
            let changes = TaskActivity.changes(from: old, to: items[index])
            // Undo and redo restore task fields while the activity remains a chronological journal.
            items[index].taskActivity = old.taskActivity
            guard !changes.isEmpty else { continue }
            var activity = old.taskActivity ?? []
            if changes == ["title"] || changes == ["body"], let last = activity.last,
               last.changes == changes, (0..<30).contains(date.timeIntervalSince(last.date)) {
                continue
            }
            activity.append(TaskActivity(date: date, changes: changes))
            items[index].taskActivity = Array(activity.suffix(100))
        }
    }
}
