import Foundation
import TaktCore
import WidgetKit

@MainActor final class WidgetBridge {
    private let store: WidgetStore
    private let state: AppState
    private var needsPublish = true
    private var lastDay: Date?
    private var lastRead: Date?
    private var retryPending = false
    private var timer: Timer?

    init(store: WidgetStore, state: AppState) {
        self.store = store
        self.state = state
        state.widgetDataChanged = { [weak self] previous in self?.invalidateIfNeeded(previous) }
    }

    private func invalidateIfNeeded(_ previous: Snapshot) {
        guard !needsPublish else { return }
        let current = state.data
        needsPublish = previous.projects != current.projects || previous.tags != current.tags
            || previous.workspaceOptions?.queueFilters != current.workspaceOptions?.queueFilters
            || previous.preferences.timeZone != current.preferences.timeZone
            || !previous.items.lazy.filter { $0.kind == .task }.elementsEqual(current.items.lazy.filter { $0.kind == .task })
    }

    func start() {
        update()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func update() {
        guard state.widgetDataAvailable else { return }
        do {
            let modified = store.modificationDate
            if modified != lastRead || retryPending {
                let widget = try store.read()
                retryPending = false
                // Retries must never toggle a completed task back to open.
                for (id, revision) in widget.completions {
                    guard let task = state.item(id), task.isActiveTask, task.modified == revision else { continue }
                    state.complete(id)
                    if state.item(id)?.isActiveTask == true { retryPending = true }
                }
                lastRead = modified
            }
            try publish()
        } catch {
            let message = "Не удалось обновить данные виджета. \(error.localizedDescription)"
            if state.errorMessage != message { state.errorMessage = message }
        }
    }

    private func publish() throws {
        let day = state.calendar.startOfDay(for: .now)
        guard needsPublish || day != lastDay else { return }
        if try store.publish(state.widgetTaskLists(), timeZone: state.calendar.timeZone.identifier) {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetStore.kind)
        }
        needsPublish = false
        lastDay = day
    }
}

extension AppState {
    func openWidgetList(_ id: String) {
        let parts = id.split(separator: ":", maxSplits: 1)
        let identifier = parts.count == 2 ? UUID(uuidString: String(parts[1])) : nil
        search = ""
        selectedID = nil
        area = .tasks
        switch parts.first {
        case "today": scope = .today
        case "inbox": scope = .inbox
        case "week": scope = .week
        case "project": if let identifier { scope = .project(identifier) }
        case "tag": if let identifier { scope = .tag(identifier) }
        case "filter":
            if let filter = savedQueueFilters.first(where: { $0.id == identifier }), isQueueFilterAvailable(filter) {
                area = .calendar
                applyQueueFilter(filter)
            }
        default: break
        }
    }
}
