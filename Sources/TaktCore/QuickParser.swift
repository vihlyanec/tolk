import Foundation

public enum QuickTokenKind: String, Sendable { case project, tag, priority, date, time, duration }

/// UTF-16 ranges refer to the original input, including emoji and quoted project names.
public struct QuickToken: Equatable, Sendable {
    public var range: NSRange
    public var kind: QuickTokenKind
    public var value: String
}

public struct ParsedTask: Sendable {
    public var title: String
    public var projectID: UUID?
    public var tagIDs: [UUID] = []
    public var priority = 0
    public var duration = 30
    public var hasExplicitDuration = false
    public var schedule: Schedule = .unscheduled
    public var warnings: [String] = []
    public var tokens: [QuickToken] = []
    public func item() -> Item {
        var item = Item(title: title, projectID: projectID)
        item.tagIDs = tagIDs; item.priority = priority; item.duration = duration; item.schedule = schedule
        return item
    }
}
public enum QuickParser {
    public static func parse(_ text: String, projects: [Project], tags: [Tag], now: Date = Date(), calendar: Calendar = Dates.calendar(), literalRanges: [NSRange] = []) -> ParsedTask {
        var source = text
        var result = ParsedTask(title: text)
        func consume(_ pattern: String, kind: QuickTokenKind = .date, tokenKind: (([String]) -> QuickTokenKind)? = nil, action: ([String]) -> Bool) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return }
            let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
            for match in matches.reversed() {
                guard !literalRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else { continue }
                let values = (0..<match.numberOfRanges).map { n -> String in
                    guard let range = Range(match.range(at: n), in: source) else { return "" }
                    return String(source[range])
                }
                if action(values), let range = Range(match.range, in: source) {
                    result.tokens.append(QuickToken(range: match.range, kind: tokenKind?(values) ?? kind, value: values[0]))
                    // Keep offsets stable for later matches and syntax highlighting.
                    source.replaceSubrange(range, with: String(repeating: " ", count: match.range.length))
                }
            }
        }
        consume(#"(?<!\S)/(?:"([^"]+)"|([^\s/]+))(?=\s|$)"#, kind: .project) { values in
            let name = values[1].isEmpty ? values[2] : values[1]
            guard let project = projects.first(where: { $0.kind == .task && !$0.archived && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
                result.warnings.append("Проект «\(name)» не найден — текст оставлен в названии"); return false
            }
            if result.projectID == nil { result.projectID = project.id; return true }
            return false
        }
        consume(#"(?<![\p{L}\p{N}_/])#(?:"([^"\n]+)"|([\p{L}\p{N}_-]+))"#, kind: .tag) { values in
            let name = values[1].isEmpty ? values[2] : values[1]
            guard let tag = tags.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
                result.warnings.append("Тег «\(name)» не найден — создайте его в боковой панели"); return false
            }
            if !result.tagIDs.contains(tag.id) { result.tagIDs.append(tag.id) }; return true
        }
        var priorityFound = false
        consume(#"(?<!\S)!([0-3])(?=\s|$)"#, kind: .priority) { values in
            guard !priorityFound else { return false }; priorityFound = true
            result.priority = Int(values[1]) ?? 0; return true
        }
        consume(#"(?<!\S)(важно|срочно|высокий приоритет|средний приоритет|низкий приоритет)(?=\s|$)"#, kind: .priority) { values in
            guard !priorityFound else { return false }; priorityFound = true
            let word = values[1].lowercased()
            result.priority = word.hasPrefix("средний") ? 2 : word.hasPrefix("низкий") ? 3 : 1
            return true
        }
        let quantity = #"(\d+|один|одну|одна|два|две|три|четыре|пять|шесть|семь|восемь|девять|десять|полтора|полторы)"#
        let clockUnits = #"(минут(?:у|ы)?|мин\.?|час(?:а|ов)?|ч)"#
        func amount(_ value: String) -> Double? {
            if value.isEmpty { return 1 }
            let words: [String: Double] = ["один":1, "одну":1, "одна":1, "два":2, "две":2, "три":3, "четыре":4, "пять":5, "шесть":6, "семь":7, "восемь":8, "девять":9, "десять":10, "полтора":1.5, "полторы":1.5]
            return words[value.lowercased()] ?? Double(value)
        }
        consume(#"(?<!\S)на\s+(?:(пол\s*часа)|(?:\#(quantity)\s*)?\#(clockUnits))(?=\s|$)"#, kind: .duration) { values in
            guard let count = amount(values[2]), count > 0, count <= 10080 else { return false }
            let minutes = values[1].isEmpty ? count * (values[3].lowercased().hasPrefix("ч") ? 60 : 1) : 30
            guard minutes >= 1, minutes <= 10080, minutes.rounded() == minutes else {
                result.warnings.append("Длительность: от 1 минуты до 7 дней"); return false
            }
            result.duration = Int(minutes); result.hasExplicitDuration = true; return true
        }
        var day: Date?, exactRelative: Date?
        consume(#"(?<!\S)(?:через\s+)?пол\s*часа(?=\s|$)"#, kind: .time) { _ in
            exactRelative = calendar.date(byAdding: .minute, value: 30, to: now)
            return exactRelative != nil
        }
        let relativeUnits = #"(минут(?:у|ы)?|мин\.?|час(?:а|ов)?|ч|день|дня|дней|сутки|недел(?:ю|и|ь)|месяц(?:а|ев)?|год(?:а)?|лет)"#
        consume(#"(?<!\S)через\s+(?:\#(quantity)\s*)?\#(relativeUnits)(?=\s|$)"#, tokenKind: { values in
            let unit = values[2].lowercased()
            return unit.hasPrefix("мин") || unit.hasPrefix("ч") ? .time : .date
        }) { values in
            guard let count = amount(values[1]), count > 0, count <= 10000 else { return false }
            let unit = values[2].lowercased()
            let component: Calendar.Component
            if unit.hasPrefix("мин") || unit.hasPrefix("ч") {
                let minutes = count * (unit.hasPrefix("ч") ? 60 : 1)
                guard minutes.rounded() == minutes, let date = calendar.date(byAdding: .minute, value: Int(minutes), to: now) else { return false }
                exactRelative = date; return true
            }
            if unit.hasPrefix("нед") { component = .weekOfYear }
            else if unit.hasPrefix("месяц") { component = .month }
            else if unit.hasPrefix("год") || unit == "лет" { component = .year }
            else { component = .day }
            guard count.rounded() == count, let date = calendar.date(byAdding: component, value: Int(count), to: now) else { return false }
            day = calendar.startOfDay(for: date); return true
        }
        consume(#"(?<!\S)(сегодня|завтра|послезавтра)(?=\s|$)"#) { values in
            let value = values[1].lowercased()
            let offset = value == "сегодня" ? 0 : (value == "завтра" ? 1 : 2)
            day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)); return true
        }
        consume(#"(?<!\S)(\d{1,2})\.(\d{1,2})(?:\.(\d{4}))?(?=\s|$)"#) { values in
            let year = values[3].isEmpty ? calendar.component(.year, from: now) : (Int(values[3]) ?? 0)
            let month = Int(values[2]) ?? 0, date = Int(values[1]) ?? 0
            let parts = DateComponents(year: year, month: month, day: date)
            guard let d = calendar.date(from: parts), calendar.component(.day, from: d) == date,
                  calendar.component(.month, from: d) == month, calendar.component(.year, from: d) == year else {
                result.warnings.append("Такой даты не существует"); return false
            }
            day = d; return true
        }
        let weekdays = ["воскресенье", "понедельник", "вторник", "среда", "четверг", "пятница", "суббота"]
        consume(#"(?<!\S)(?:в\s+)?(понедельник|вторник|среда|среду|четверг|пятница|пятницу|суббота|субботу|воскресенье)(?=\s|$)"#) { values in
            let name = ["среду":"среда", "пятницу":"пятница", "субботу":"суббота"][values[1].lowercased()] ?? values[1].lowercased()
            guard let index = weekdays.firstIndex(of: name) else { return false }
            let offset = (index + 1 - calendar.component(.weekday, from: now) + 7) % 7
            day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)); return true
        }
        var clock: (Int, Int)?
        consume(#"(?<!\S)(?:в\s+)?([01]?\d|2[0-3]):([0-5]\d)(?=\s|$)"#, kind: .time) { values in
            clock = (Int(values[1]) ?? 0, Int(values[2]) ?? 0); return true
        }
        if let clock, let start = calendar.date(bySettingHour: clock.0, minute: clock.1, second: 0, of: day ?? now) {
            result.schedule = .timed(start)
            if start < now { result.warnings.append("Распознанное время уже прошло — проверьте дату") }
        } else if let exactRelative { result.schedule = .timed(exactRelative) }
        else if let day { result.schedule = .day(day) }
        result.tokens.sort { $0.range.location < $1.range.location }
        result.title = source.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return result
    }
}
