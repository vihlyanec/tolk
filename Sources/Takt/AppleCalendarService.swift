import AppKit
import EventKit
import TaktCore

// The store and all EK objects stay on this actor; only immutable values leave it.
actor AppleCalendarService {
    private var stored: EKEventStore?
    private var store: EKEventStore {
        if let stored { return stored }
        let value = EKEventStore(); stored = value; return value
    }
    func requestAccess() async throws -> Bool { try await store.requestFullAccessToEvents() }
    func authorized() -> Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    func calendars() throws -> [ExternalCalendar] {
        guard authorized() else { throw TaktError.invalid("Разрешите доступ в macOS: Конфиденциальность и безопасность → Календари.") }
        return store.calendars(for: .event).map { calendar in
            let color = NSColor(cgColor: calendar.cgColor)?.usingColorSpace(.sRGB)
            let hex = color.map { String(format: "%02X%02X%02X", Int($0.redComponent * 255), Int($0.greenComponent * 255), Int($0.blueComponent * 255)) } ?? "598BFF"
            return ExternalCalendar(id: calendar.calendarIdentifier, sourceID: calendar.source.sourceIdentifier,
                                    name: calendar.title, account: calendar.source.title, color: hex)
        }.sorted { ($0.account, $0.name, $0.id) < ($1.account, $1.name, $1.id) }
    }
    func events(from start: Date, to end: Date, selected: Set<String>) throws -> AppleCalendarWindow {
        guard authorized() else { throw TaktError.invalid("Доступ к Apple Календарю отозван. Проверьте разрешение в настройках macOS.") }
        let calendars = store.calendars(for: .event).filter { selected.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty || selected.isEmpty else { throw TaktError.invalid("Выбранные календари сейчас недоступны. Обновите список источников.") }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let events: [ExternalEvent] = selected.isEmpty ? [] : store.events(matching: predicate).compactMap { event in
            guard event.status != .canceled,
                  !(event.attendees ?? []).contains(where: { $0.isCurrentUser && $0.participantStatus == .declined }),
                  let startDate = event.startDate, let endDate = event.endDate, endDate > startDate,
                  let calendar = event.calendar, let identifier = event.eventIdentifier else { return nil }
            return ExternalEvent(calendarID: calendar.calendarIdentifier, sourceID: calendar.source.sourceIdentifier,
                                 eventID: identifier, externalID: event.calendarItemExternalIdentifier,
                                 occurrence: event.occurrenceDate, title: event.title ?? "Без названия",
                                 notes: event.notes ?? "", location: event.location ?? "", url: event.url,
                                 start: startDate, end: endDate, allDay: event.isAllDay,
                                 timeZone: event.isAllDay ? TimeZone.current.identifier : (event.timeZone?.identifier ?? TimeZone.current.identifier),
                                 tentative: event.status == .tentative)
        }
        guard authorized() else { throw TaktError.invalid("Доступ к календарям изменился во время чтения.") }
        return AppleCalendarWindow(start: start, end: end, events: events)
    }
}
