import AppKit
import Observation
import Network
import TaktCore

@Observable final class SyncCoordinator {
    weak var state: AppState?
    var appleStatus = "Не подключён"
    var tickTickStatus = "Не подключён"
    var appleBusy = false
    var tickTickBusy = false
    var appleVisible = false
    var appleAccessRequired = false
    var preview: TickTickPull?
    var importProjects: Set<String> = []
    var importInbox = true
    var importMapping: [String: UUID] = [:]
    var importProjectMapping: [String: UUID] = [:]
    private var previewToken: String?
    private var previewGeneration = UUID()
    private let apple = AppleCalendarService()
    private var appleTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var localTask: Task<Void, Never>?
    private var appleNotificationTask: Task<Void, Never>?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var monitor: NWPathMonitor?
    private var lastAppleAttempt = Date.distantPast
    private var lastTickAttempt = Date.distantPast
    private var nextTickAttempt = Date.distantPast
    private var failures = 0
    private var appleRun = UUID()
    private var tickRun = UUID()
    private var appleNeedsRefresh = false
    init(state: AppState) { self.state = state }
    func start() {
        guard let state, !state.isDemo, timer == nil else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
        observers.append(center.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.appleStoreChanged() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
        let network = NWPathMonitor()
        network.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied { Task { @MainActor in self?.refresh() } }
        }
        network.start(queue: DispatchQueue(label: "local.tolk.sync-network")); monitor = network
        let pollTimer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let state = self.state else { return }
                if Date().timeIntervalSince(self.lastTickAttempt) >= Double(state.data.tickTick?.options.intervalMinutes ?? 5) * 60 { self.refreshTickTick() }
                if state.data.appleCalendar != nil, Date().timeIntervalSince(self.lastAppleAttempt) >= 60 { self.refreshApple() }
            }
        }
        timer = pollTimer
        RunLoop.main.add(pollTimer, forMode: .common)
        refresh()
    }
    func appleStoreChanged() {
        appleNotificationTask?.cancel()
        appleNotificationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.refreshApple()
        }
    }
    func stop() {
        timer?.invalidate(); timer = nil; monitor?.cancel(); monitor = nil
        appleTask?.cancel(); tickTask?.cancel(); localTask?.cancel(); appleNotificationTask?.cancel()
        for observer in observers { NotificationCenter.default.removeObserver(observer); NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }
    func refresh() { refreshApple(); refreshTickTick() }
    func localChanged() {
        guard let state, !state.isDemo, state.data.tickTick?.outbox.values.contains(where: { !$0.attempted }) == true else { return }
        localTask?.cancel()
        localTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2)); guard !Task.isCancelled else { return }
            if self?.state?.data.tickTick?.outbox.values.contains(where: { !$0.attempted }) == true { self?.refreshTickTick() }
        }
    }
    func connectApple() {
        guard let state, !state.isDemo, !appleBusy else { return }
        appleRun = UUID(); let run = appleRun
        appleBusy = true; appleStatus = "Ожидаем разрешение macOS…"
        appleTask = Task { [weak self] in
            guard let self else { return }
            var refreshAfterPermission = false
            defer {
                if self.appleRun == run {
                    self.appleBusy = false
                    if refreshAfterPermission { self.refreshApple() }
                }
            }
            do {
                guard try await self.apple.requestAccess() else { throw TaktError.invalid("Доступ запрещён. Разрешите Календари в настройках macOS.") }
                let calendars = try await self.apple.calendars()
                guard !Task.isCancelled, self.appleRun == run else { return }
                self.state?.change(undo: false) { s in
                    var connection = s.appleCalendar ?? AppleCalendarState()
                    connection.calendars = calendars; connection.generation = UUID()
                    s.appleCalendar = connection
                }
                self.appleStatus = "Выберите календари для отображения"
                self.appleVisible = true; self.appleAccessRequired = false
                refreshAfterPermission = true
            } catch { self.appleStatus = error.localizedDescription }
        }
    }
    func selectCalendar(_ id: String, enabled: Bool) {
        guard let state else { return }
        appleRun = UUID(); appleTask?.cancel()
        state.change(undo: false) { snapshot in
            guard var connection = snapshot.appleCalendar else { return }
            if enabled { connection.selected.insert(id) } else { connection.selected.remove(id) }
            connection.generation = UUID(); connection.windows = []; snapshot.appleCalendar = connection
        }
        appleBusy = false; appleStatus = "Выбор сохранён"; refreshApple()
    }
    func disconnectApple() {
        appleRun = UUID(); appleTask?.cancel(); appleTask = nil; appleBusy = false; appleVisible = false
        state?.change(undo: false) { $0.appleCalendar = nil }
        appleNotificationTask?.cancel(); appleNeedsRefresh = false; appleAccessRequired = false
        state?.externalEventID = nil; appleStatus = "Не подключён"
    }
    func refreshApple() {
        guard let state, !state.isDemo, let connection = state.data.appleCalendar else { return }
        if appleBusy { appleNeedsRefresh = true; return }
        let generation = connection.generation, zone = state.calendar
        let month = zone.dateInterval(of: .month, for: state.anchor)!
        let lower = zone.date(byAdding: .month, value: -1, to: month.start)!, upper = zone.date(byAdding: .month, value: 2, to: month.start)!
        appleRun = UUID(); let run = appleRun
        appleBusy = true; lastAppleAttempt = Date(); appleStatus = "Обновляем выбранный период…"
        appleTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.appleRun == run { self.appleBusy = false }
                if self.appleRun == run, self.appleNeedsRefresh { self.appleNeedsRefresh = false; self.refreshApple() }
            }
            do {
                let available = try await self.apple.calendars()
                guard !Task.isCancelled, self.state?.data.appleCalendar?.generation == generation else { return }
                self.appleVisible = true; self.appleAccessRequired = false
                self.state?.change(undo: false) { $0.appleCalendar?.calendars = available }
                let missing = connection.selected.subtracting(Set(available.map(\.id)))
                guard missing.isEmpty else { throw TaktError.invalid("Некоторые выбранные календари недоступны. Проверьте выбор источников.") }
                var cursor = lower
                while cursor < upper {
                    let end = zone.date(byAdding: .month, value: 1, to: cursor)!
                    let window = try await self.apple.events(from: cursor, to: end, selected: connection.selected)
                    guard !Task.isCancelled, self.state?.data.appleCalendar?.generation == generation else { return }
                    self.state?.change(undo: false) { $0.appleCalendar?.replace(window) }
                    cursor = end
                }
                self.appleStatus = connection.selected.isEmpty ? "Выберите календари для отображения" : "Обновлено в \(Date().formatted(date: .omitted, time: .shortened))"
            } catch {
                guard !Task.isCancelled, self.state?.data.appleCalendar?.generation == generation else { return }
                let authorized = await self.apple.authorized()
                guard !Task.isCancelled, self.state?.data.appleCalendar?.generation == generation else { return }
                self.appleAccessRequired = !authorized
                if !authorized { self.appleVisible = false; self.state?.externalEventID = nil }
                self.appleStatus = "События не обновлены: " + error.localizedDescription
            }
        }
    }
    func previewTickTick(token: String) {
        guard let state, !state.isDemo, !tickTickBusy, state.data.tickTick == nil else { return }
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { tickTickStatus = "Введите персональный API-токен"; return }
        cancelPreview(); let generation = previewGeneration
        tickRun = UUID(); let run = tickRun
        tickTickBusy = true; tickTickStatus = "Читаем проекты и входящие…"
        tickTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.tickRun == run { self.tickTickBusy = false } }
            do {
                let result = try await TickTickAPI(token: token).pull()
                guard !Task.isCancelled, self.previewGeneration == generation, self.state?.data.tickTick == nil else { return }
                self.preview = result; self.previewToken = token
                self.importProjects = Set(result.projects.map(\.id)); self.importInbox = true; self.importMapping = [:]; self.importProjectMapping = [:]
                self.tickTickStatus = "Проверьте импорт перед подключением"
            } catch { if !Task.isCancelled { self.tickTickStatus = error.localizedDescription } }
        }
    }
    func cancelPreview() {
        tickRun = UUID(); tickTask?.cancel(); preview = nil; previewToken = nil; previewGeneration = UUID(); tickTickBusy = false
    }
    func acceptPreview() {
        guard let state, !state.isDemo, let preview, let token = previewToken, state.data.tickTick == nil else { return }
        let id = UUID()
        let projects = preview.projects.filter { importProjects.contains($0.id) }
        let tasks = preview.tasks.filter { importProjects.contains($0.projectID) || (importInbox && preview.inboxIDs.contains($0.projectID)) }
        guard Set(importProjectMapping.values).count == importProjectMapping.values.count else { tickTickStatus = "Локальный проект можно связать только с одним проектом TickTick"; return }
        guard Set(importMapping.values).count == importMapping.values.count else { tickTickStatus = "Одну локальную задачу можно связать только с одной задачей TickTick"; return }
        do {
            try TickTickKeychain.save(token, id: id)
            state.change(undo: false) { snapshot in
                var sync = TickTickSyncState(connectionID: id); sync.options.enabled = true; snapshot.tickTick = sync
                for remote in projects {
                    if let localID = self.importProjectMapping[remote.id], let project = snapshot.projects.first(where: { $0.id == localID && $0.kind == .task }) {
                        snapshot.tickTick?.projects[localID.uuidString] = TickTickProjectLink(remote: remote, local: project)
                    }
                }
                for remote in tasks {
                    if let localID = self.importMapping[remote.id], let item = snapshot.items.first(where: { $0.id == localID && $0.kind == .task && !$0.deleted }) {
                        let baseline = TickTickCodec.localFields(item, in: snapshot, remoteProjectID: remote.projectID)
                        snapshot.tickTick?.links[localID.uuidString] = TickTickLink(remote: remote, local: baseline)
                    }
                }
                SyncEngine.ingest(projects: projects, tasks: tasks, inboxIDs: preview.inboxIDs, columns: preview.columns, into: &snapshot)
                snapshot.tickTick?.selectedProjects = Set(projects.map(\.id)); snapshot.tickTick?.includeInbox = self.importInbox
                snapshot.tickTick?.lastSuccess = Date()
            }
            guard state.data.tickTick?.connectionID == id else { try? TickTickKeychain.remove(id); return }
            self.preview = nil; previewToken = nil; tickTickStatus = "Подключено. Импортировано задач: \(tasks.count)"
        } catch { tickTickStatus = error.localizedDescription }
    }
    func reauthorizeTickTick(token: String) {
        guard let state, !state.isDemo, let connection = state.data.tickTick, !tickTickBusy else { return }
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        let id = connection.connectionID
        tickRun = UUID(); let run = tickRun; tickTickBusy = true
        tickTickStatus = "Проверяем новый доступ…"
        tickTask = Task { [weak self] in
            guard let self else { return }
            var succeeded = false
            defer {
                if self.tickRun == run {
                    self.tickTickBusy = false
                    if succeeded { self.refreshTickTick(manual: true) }
                }
            }
            do {
                let pull = try await TickTickAPI(token: token).pull()
                guard !Task.isCancelled, self.state?.data.tickTick?.connectionID == id else { return }
                let knownInbox = Set(connection.links.values.map(\.remote.projectID)).subtracting(Set(connection.projects.values.map(\.remote.id))).subtracting(["inbox"])
                if !knownInbox.isEmpty && knownInbox.isDisjoint(with: pull.inboxIDs) {
                    throw TaktError.invalid("У нового токена другой аккаунт TickTick. Текущие связи и локальные правки сохранены.")
                }
                try TickTickKeychain.replace(token, id: id)
                self.failures = 0; self.nextTickAttempt = .distantPast
                self.tickTickStatus = "Доступ заменён. Синхронизация продолжается автоматически."
                succeeded = true
            } catch { if !Task.isCancelled { self.tickTickStatus = error.localizedDescription } }
        }
    }
    func disconnectTickTick() {
        cancelPreview(); localTask?.cancel()
        guard let state, let sync = state.data.tickTick else { tickTickStatus = "Не подключён"; return }
        do {
            if !state.isDemo { try TickTickKeychain.remove(sync.connectionID) }
            state.change(undo: false) { s in
                s.tickTick = nil
                for i in s.items.indices { s.items[i].externalRecurrence = nil }
            }
            tickTickStatus = "Отключено. Задачи оставлены на Mac"; failures = 0; nextTickAttempt = .distantPast
        } catch { tickTickStatus = error.localizedDescription }
    }
    func refreshTickTick(manual: Bool = false) {
        guard let state, !state.isDemo, let sync = state.data.tickTick, sync.options.enabled, !tickTickBusy,
              manual || Date() >= nextTickAttempt else { return }
        let id = sync.connectionID
        tickRun = UUID(); let run = tickRun
        tickTickBusy = true; lastTickAttempt = Date(); tickTickStatus = "Синхронизация…"
        tickTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.tickRun == run { self.tickTickBusy = false } }
            @MainActor func active() -> Bool { !Task.isCancelled && self.state?.data.tickTick?.connectionID == id }
            var attemptedKey: String?
            do {
                let api = TickTickAPI(token: try TickTickKeychain.read(id))
                var pull = try await api.pull()
                guard active() else { return }
                if let selected = sync.selectedProjects {
                    pull.projects = pull.projects.filter { selected.contains($0.id) }
                    pull.tasks = pull.tasks.filter { selected.contains($0.projectID) || (sync.includeInbox && pull.inboxIDs.contains($0.projectID)) }
                }
                // Direct reads detect completion without treating missing open tasks as deleted.
                for (key, link) in self.state?.data.tickTick?.links ?? [:] where !pull.tasks.contains(where: { $0.id == link.remote.id }) && !link.pendingCreate {
                    let remote = try await api.task(projectID: link.remote.projectID, id: link.remote.id)
                    guard active() else { return }
                    if let remote { pull.tasks.append(remote) }
                    else { self.state?.change(undo: false) { $0.tickTick?.links[key]?.missing = true } }
                }
                guard active() else { return }
                self.state?.change(undo: false) { snapshot in
                    SyncEngine.ingest(projects: pull.projects, tasks: pull.tasks, inboxIDs: pull.inboxIDs, columns: pull.columns, into: &snapshot)
                }
                let queued = self.state?.data.tickTick?.outbox ?? [:]
                for (key, pending) in queued {
                    guard active(), let current = self.state?.data.tickTick?.outbox[key], current == pending else { continue }
                    if pending.attempted {
                        self.tickTickStatus = "Есть неподтверждённая отправка. Повторное создание приостановлено, чтобы избежать дублей."
                        continue
                    }
                    // Re-read immediately before writing; a newer server value is merged
                    // in another pass instead of being overwritten with a stale payload.
                    if let link = self.state?.data.tickTick?.links[key], !pending.creating {
                        guard let fresh = try await api.task(projectID: link.remote.projectID, id: link.remote.id) else {
                            guard active() else { return }
                            self.state?.change(undo: false) { $0.tickTick?.links[key]?.missing = true; $0.tickTick?.outbox[key] = nil }
                            continue
                        }
                        guard active() else { return }
                        if fresh.raw != link.remote.raw {
                            self.state?.change(undo: false) { SyncEngine.ingest(projects: [], tasks: [fresh], inboxIDs: pull.inboxIDs, into: &$0) }
                            continue
                        }
                    }
                    attemptedKey = key
                    self.state?.change(undo: false) { $0.tickTick?.outbox[key]?.attempted = true }
                    guard self.state?.data.tickTick?.outbox[key]?.attempted == true, active() else { return }
                    var task = pending.task
                    if let link = self.state?.data.tickTick?.links[key], !pending.creating, link.remote.projectID != task.projectID {
                        task = try await api.move(link.remote, to: task.projectID)
                        guard active() else { return }
                        task = TickTickCodec.patch(task, with: pending.task.raw, keys: Set(pending.task.fields.keys))
                    }
                    let completes = task.completed && self.state?.data.tickTick?.links[key]?.remote.completed != true
                    if completes { task.raw["status"] = .number(0) }
                    var saved = try await api.save(task, creating: pending.creating)
                    guard active() else { return }
                    if completes { saved = try await api.complete(saved) }
                    guard active() else { return }
                    let oldFields = pending.creating ? [:] : (self.state?.data.tickTick?.links[key]?.remote.fields ?? [:])
                    let expected = pending.task.fields
                    let changed = Set(expected.keys.filter { expected[$0] != oldFields[$0] })
                    guard changed.allSatisfy({ saved.fields[$0] == expected[$0] }) else {
                        throw TickTickAPIError.incomplete("Отправка не подтверждена чтением TickTick. Локальная версия и очередь сохранены; проверьте конфликт в настройках.")
                    }
                    self.state?.change(undo: false) { SyncEngine.confirm(key: key, sent: pending, remote: saved, in: &$0) }
                    attemptedKey = nil
                }
                guard active() else { return }
                self.failures = 0; self.nextTickAttempt = .distantPast
                self.state?.change(undo: false) { $0.tickTick?.lastSuccess = Date() }
                let conflicts = self.state?.data.tickTick?.conflicts.count ?? 0
                let uncertain = self.state?.data.tickTick?.outbox.values.contains { $0.attempted } ?? false
                self.tickTickStatus = conflicts > 0 ? "Нужно разрешить конфликтов: \(conflicts)" : uncertain ? "Есть неподтверждённая отправка; автоматический повтор остановлен" : "Обновлено в \(Date().formatted(date: .omitted, time: .shortened))"
            } catch {
                guard active() else { return }
                if let rejected = error as? TickTickAPIError, rejected.definitelyRejected, let key = attemptedKey {
                    self.state?.change(undo: false) { $0.tickTick?.outbox[key]?.attempted = false }
                }
                self.failures += 1
                self.nextTickAttempt = Date().addingTimeInterval(min(1800, pow(2, Double(min(self.failures, 6))) * 30))
                self.tickTickStatus = error.localizedDescription
            }
        }
    }
}
import EventKit
