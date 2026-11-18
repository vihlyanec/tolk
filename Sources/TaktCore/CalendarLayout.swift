import Foundation

public struct EventPlacement: Identifiable, Sendable {
    public let id: UUID
    public let startMinute: Double
    public let endMinute: Double
    public let lane: Int
    public let laneCount: Int
    public let isBackground: Bool
    public let overlapsBackground: Bool
    /// All tasks in one overlap group share a leading gutter so their lanes stay aligned.
    public let backgroundLaneCount: Int
}
public enum CalendarLayout {
    private typealias Segment = (id: UUID, start: Double, end: Double)
    public static func startHour(preferred: Int, days: [Date], items: [Item], calendar: Calendar, external: [ExternalEvent] = []) -> Int {
        days.flatMap { placements(items: items, day: $0, calendar: calendar, external: external) }
            .reduce(preferred) { min($0, Int($1.startMinute / 60)) }
    }
    public static func placements(items: [Item], day: Date, calendar: Calendar, external: [ExternalEvent] = []) -> [EventPlacement] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        func minute(_ date: Date) -> Double {
            if date <= start { return 0 }; if date >= end { return 1440 }
            let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
            return Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) + Double(parts.second ?? 0) / 60
        }
        func segment(_ id: UUID, _ from: Date, _ to: Date) -> Segment? {
            guard from < end, to > start, to > from else { return nil }
            let lower = minute(from), upper = minute(to)
            // An interval inside the repeated hour can end at an earlier wall-clock time.
            if upper <= lower {
                let elapsed = min(to, end).timeIntervalSince(max(from, start)) / 60
                return (id, lower, min(1440, lower + elapsed))
            }
            return (id, lower, upper)
        }
        let events = external.compactMap { event in
            event.allDay ? nil : segment(event.id, event.start, event.end)
        }
        let tasks = items.compactMap { item -> Segment? in
            guard item.kind == .task, !item.deleted, item.schedule.isTimed,
                  let from = item.schedule.date, let to = item.end else { return nil }
            return segment(item.id, from, to)
        }
        let backgrounds = assignLanes(events, isBackground: true)
        return backgrounds + assignLanes(tasks, isBackground: false, backgrounds: backgrounds)
    }

    private static func assignLanes(_ segments: [Segment], isBackground: Bool, backgrounds: [EventPlacement] = []) -> [EventPlacement] {
        let ordered = segments.sorted { a, b in
            if a.start != b.start { return a.start < b.start }
            if a.end != b.end { return a.end > b.end }
            return a.id.uuidString < b.id.uuidString
        }
        var output: [EventPlacement] = []
        var cluster: [(event: Segment, lane: Int)] = []
        var ends: [Double] = []
        var clusterEnd = -Double.infinity
        func flush() {
            guard let first = cluster.first else { return }
            let nearby = backgrounds.filter { $0.startMinute < clusterEnd && first.event.start < $0.endMinute }
            let railCount = nearby.map(\.laneCount).max() ?? 0
            for (event, lane) in cluster {
                let overlapsBackground = nearby.contains { $0.startMinute < event.end && event.start < $0.endMinute }
                output.append(EventPlacement(id: event.id, startMinute: event.start, endMinute: event.end,
                                             lane: lane, laneCount: ends.count, isBackground: isBackground,
                                             overlapsBackground: overlapsBackground, backgroundLaneCount: railCount))
            }
            cluster.removeAll(keepingCapacity: true)
            ends.removeAll(keepingCapacity: true)
        }
        for event in ordered {
            if event.start >= clusterEnd { flush() }
            let lane = ends.firstIndex(where: { $0 <= event.start }) ?? ends.count
            if lane == ends.count { ends.append(event.end) } else { ends[lane] = event.end }
            cluster.append((event, lane))
            clusterEnd = max(clusterEnd, event.end)
        }
        flush()
        return output
    }
}
