import Foundation

public struct EventPlacement: Identifiable, Sendable {
    public let id: UUID
    public let startMinute: Double
    public let endMinute: Double
    public let lane: Int
    public let laneCount: Int
}
public enum CalendarLayout {
    public static func startHour(preferred: Int, days: [Date], items: [Item], calendar: Calendar, external: [ExternalEvent] = []) -> Int {
        days.flatMap { placements(items: items, day: $0, calendar: calendar, external: external) }
            .reduce(preferred) { min($0, Int($1.startMinute / 60)) }
    }
    public static func placements(items: [Item], day: Date, calendar: Calendar, external: [ExternalEvent] = []) -> [EventPlacement] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let tasks: [(UUID, Date, Date)] = items.compactMap { item in
            guard item.kind == .task, !item.deleted, item.schedule.isTimed,
                  let s = item.schedule.date, let e = item.end, s < end, e > start else { return nil }
            return (item.id, s, e)
        }
        let events = external.filter { !$0.allDay }.map { ($0.id, $0.start, $0.end) }
        func minute(_ date: Date) -> Double {
            if date <= start { return 0 }; if date >= end { return 1440 }
            let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
            return Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) + Double(parts.second ?? 0) / 60
        }
        let segments: [(UUID, Double, Double)] = (tasks + events).compactMap { id, s, e in
            guard s < end, e > start else { return nil }
            return (id, minute(max(s, start)), minute(min(e, end)))
        }.sorted { $0.1 == $1.1 ? ($0.2 == $1.2 ? $0.0.uuidString < $1.0.uuidString : $0.2 > $1.2) : $0.1 < $1.1 }
        var output: [EventPlacement] = [], cluster: [(UUID, Double, Double)] = [], clusterEnd = -1.0
        func flush(_ group: [(UUID, Double, Double)]) -> [EventPlacement] {
            var ends: [Double] = [], assigned: [(UUID, Double, Double, Int)] = []
            for event in group {
                let lane = ends.firstIndex(where: { $0 <= event.1 }) ?? ends.count
                if lane == ends.count { ends.append(event.2) } else { ends[lane] = event.2 }
                assigned.append((event.0, event.1, event.2, lane))
            }
            return assigned.map { EventPlacement(id: $0.0, startMinute: $0.1, endMinute: $0.2, lane: $0.3, laneCount: ends.count) }
        }
        for event in segments {
            if event.1 >= clusterEnd, !cluster.isEmpty { output += flush(cluster); cluster = [] }
            cluster.append(event); clusterEnd = max(event.2, cluster.isEmpty ? -1 : clusterEnd)
        }
        return output + flush(cluster)
    }
}
