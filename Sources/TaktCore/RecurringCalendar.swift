import Foundation
import CryptoKit

/// Future occurrences are values, not records. Viewing a week never changes the database.
public enum RecurringCalendar {
    public static func identifier(source: UUID, date: Date) -> UUID {
        let digest = SHA256.hash(data: Data("\(source.uuidString):\(Int(date.timeIntervalSince1970))".utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
    public static func sourceID(for item: Item, in items: [Item]) -> UUID {
        var current = item, seen: Set<UUID> = [item.id]
        while let parent = current.recurrenceSourceID ?? current.repeatParentID {
            guard seen.insert(parent).inserted else { break }
            guard let previous = items.first(where: { $0.id == parent }) else { return parent }
            current = previous
        }
        return current.id
    }
    public static func next(_ item: Item, in items: [Item], calendar: Calendar) -> Item? {
        var base = item
        if let date = item.recurrenceOriginalDate { base.schedule = item.schedule.isTimed ? .timed(date) : .day(date) }
        guard var next = Dates.nextOccurrence(base, calendar: calendar), let date = next.schedule.date else { return nil }
        let source = sourceID(for: item, in: items)
        next.id = identifier(source: source, date: date)
        next.recurrenceSourceID = source; next.recurrenceOriginalDate = date; next.repeatParentID = item.id
        next.created = item.created; next.modified = item.modified; next.deleted = false
        return next
    }
    public static func occurrences(items: [Item], from lower: Date, to upper: Date, calendar: Calendar) -> [Item] {
        func intersects(_ item: Item) -> Bool {
            guard let date = item.schedule.date else { return false }
            return date < upper && (item.end ?? calendar.date(byAdding: .day, value: 1, to: date) ?? date) > lower
        }
        var result = items.filter { $0.kind == .task && !$0.deleted && intersects($0) }
        let roots = items.filter { item in
            item.kind == .task && !item.deleted && item.recurrence != .none && item.recurrenceSourceID == nil &&
            (item.repeatParentID == nil || !items.contains(where: { $0.id == item.repeatParentID }))
        }
        for source in roots {
            let stored = items.filter { sourceID(for: $0, in: items) == source.id }
            let occupied = Set(stored.compactMap { $0.recurrenceOriginalDate ?? $0.schedule.date })
            var cursor = source
            for _ in 0..<200_000 {
                guard let next = next(cursor, in: items, calendar: calendar), let date = next.schedule.date, (date < upper),
                      date > (cursor.schedule.date ?? .distantPast) else { break }
                if !occupied.contains(date), intersects(next) { result.append(next) }
                cursor = next
            }
        }
        return result
    }
}
