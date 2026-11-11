import AppKit
import SwiftUI
import TaktCore

/// A snapshot in the system clipboard: pasting never moves the source or links a recurrence.
enum CalendarClipboard {
    static let type = NSPasteboard.PasteboardType("local.tolk.calendar-item")
    static func write(_ item: Item, to pasteboard: NSPasteboard = .general) {
        guard let data = try? JSONEncoder().encode(item) else { return }
        pasteboard.clearContents()
        pasteboard.setData(data, forType: type)
        pasteboard.setString(item.title, forType: .string)
    }
    static func read(from pasteboard: NSPasteboard = .general) -> Item? {
        guard let data = pasteboard.data(forType: type), data.count <= 8 * 1024 * 1024,
              let item = try? JSONDecoder().decode(Item.self, from: data), item.kind == .task,
              (1...10080).contains(item.duration), (0...3).contains(item.priority) else { return nil }
        return item
    }
    static func copy(of source: Item, at target: Schedule, in snapshot: Snapshot, now: Date = Date()) -> Item {
        var item = source
        item.id = UUID(); item.schedule = target; item.created = now; item.modified = now
        item.completed = false; item.deleted = false
        item.recurrence = .none; item.repeatEveryDays = nil; item.externalRecurrence = nil
        item.recurrenceSourceID = nil; item.repeatParentID = nil
        item.recurrenceOriginalDate = nil; item.recurrenceEndDate = nil
        item.stickyOpen = false; item.stickyFrame = nil
        item.checklist = source.checklist.map { CheckItem(title: $0.title) }
        item.allDayReminders = source.allDayReminders?.map { reminder in
            var value = reminder; value.id = UUID(); return value
        }
        let project = snapshot.projects.first { $0.id == source.projectID && !$0.archived }
        item.projectID = project?.id
        if project?.sections.contains(item.section) != true { item.section = "Без раздела" }
        item.tagIDs = item.tagIDs.filter { id in snapshot.tags.contains { $0.id == id } }
        return item
    }
    static func item(from event: ExternalEvent) -> Item {
        var item = Item(title: event.title)
        item.body = [event.notes, event.location, event.url?.absoluteString ?? ""].filter { !$0.isEmpty }.joined(separator: "\n\n")
        item.duration = max(1, min(10080, Int(ceil(event.end.timeIntervalSince(event.start) / 60))))
        item.schedule = event.allDay ? .day(event.start) : .timed(event.start)
        return item
    }
}
extension AppState {
    func copyCalendarItem(_ item: Item) {
        guard item.kind == .task, !item.deleted else { return }
        CalendarClipboard.write(item)
    }
    func copyCalendarEvent(_ event: ExternalEvent) { copyCalendarItem(CalendarClipboard.item(from: event)) }
    @discardableResult func pasteCalendarItem(at target: Schedule, from pasteboard: NSPasteboard = .general) -> Bool {
        guard let source = CalendarClipboard.read(from: pasteboard), target.date != nil else { return false }
        let copy = CalendarClipboard.copy(of: source, at: target, in: data)
        add(copy)
        return data.items.contains { $0.id == copy.id }
    }
}

/// Only handles calendar shortcuts outside editors; normal text copy/paste stays in the responder chain.
struct CalendarClipboardSurface: NSViewRepresentable {
    let state: AppState
    func makeNSView(context: Context) -> CalendarClipboardRegion { CalendarClipboardRegion() }
    func updateNSView(_ view: CalendarClipboardRegion, context: Context) { view.state = state }
    static func dismantleNSView(_ view: CalendarClipboardRegion, coordinator: ()) { view.stop() }
}
final class CalendarClipboardRegion: NSView {
    var state: AppState?
    private var monitor: Any?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop(); return }
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let state = self.state, event.window === self.window,
                  state.area == .calendar, self.window?.attachedSheet == nil,
                  !(self.window?.firstResponder is NSTextView), !(self.window?.firstResponder is NSTextField),
                  event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command else { return event }
            if event.charactersIgnoringModifiers == "c", let item = state.selectedID.flatMap(state.item), item.kind == .task, !item.deleted {
                state.copyCalendarItem(item); return nil
            }
            if event.charactersIgnoringModifiers == "c", let id = state.selectedID,
               let source = state.externalEvents.first(where: { $0.id == id }) {
                state.copyCalendarEvent(source); return nil
            }
            if event.charactersIgnoringModifiers == "v", let target = state.calendarPasteTarget,
               state.pasteCalendarItem(at: target) { return nil }
            return event
        }
    }
    func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
}

struct CalendarPasteMenu: View {
    let state: AppState
    let target: Schedule
    var body: some View {
        Button("Вставить событие") { state.pasteCalendarItem(at: target) }
            .disabled(CalendarClipboard.read() == nil)
    }
}
