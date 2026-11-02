import SwiftUI
import Observation
import UserNotifications
import TaktCore

@Observable final class PomodoroController {
    private(set) var session: Pomodoro?
    var presented = false
    var error: String?
    private let url: URL?
    private let notificationsEnabled: Bool
    @ObservationIgnored private var notificationTask: Task<Void, Never>?
    init(url: URL?, notificationsEnabled: Bool = true) {
        self.url = url; self.notificationsEnabled = notificationsEnabled
        if let url, FileManager.default.fileExists(atPath: url.path) {
            do { session = try JSONDecoder().decode(Pomodoro.self, from: Data(contentsOf: url)) }
            catch { self.error = "Не удалось прочитать таймер. Начните новый сеанс." }
        }
    }
    func start(_ item: Item, now: Date = Date()) {
        session = Pomodoro(taskID: item.id, title: item.title, now: now); presented = true; save()
    }
    func pause(now: Date = Date()) { session?.pause(at: now); save() }
    func resume(now: Date = Date()) { session?.resume(at: now); save() }
    func next(now: Date = Date()) { session?.next(at: now); save() }
    func stop() { session = nil; save() }
    private func save() {
        do {
            if let url {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if let session { try JSONEncoder().encode(session).write(to: url, options: .atomic); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
                else if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            }
            error = nil
        } catch { self.error = "Таймер работает, но не сохранён: \(error.localizedDescription)" }
        // Demo and unit tests never request permission or schedule system notifications.
        guard url != nil, notificationsEnabled else { return }
        let previous = notificationTask
        previous?.cancel()
        let current = session
        notificationTask = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: ["tolk-pomodoro"])
            guard let current, let deadline = current.deadline, deadline > Date() else { return }
            do {
                let allowed = try await center.requestAuthorization(options: [.alert, .sound])
                guard !Task.isCancelled else { return }
                guard allowed else { self.error = "Сигнал таймера отключён. Разрешите уведомления Толка в настройках macOS."; return }
                let content = UNMutableNotificationContent()
                content.title = current.phase == .focus ? "Фокус завершён" : "Перерыв завершён"
                content.body = current.title; content.sound = .default
                try await center.add(UNNotificationRequest(identifier: "tolk-pomodoro", content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, deadline.timeIntervalSinceNow), repeats: false)))
            } catch { if !Task.isCancelled { self.error = "Не удалось включить сигнал таймера." } }
        }
    }
}

struct PomodoroPanel: View {
    @Bindable var state: AppState
    private var focus: PomodoroController { state.pomodoro }
    var body: some View {
        VStack(spacing: 20) {
            HStack { Text("Помодоро").font(.title2.bold()); Spacer(); Button("Закрыть") { focus.presented = false } }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let session = focus.session {
                    let seconds = session.seconds(at: context.date)
                    Text(session.phase == .focus ? "Фокус" : session.phase == .longBreak ? "Длинный перерыв" : "Перерыв").foregroundStyle(.secondary)
                    Text(state.item(session.taskID)?.title ?? session.title).font(.headline).multilineTextAlignment(.center).lineLimit(3)
                    Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                        .font(.system(size: 64, weight: .medium, design: .rounded)).monospacedDigit().accessibilityLabel("Осталось \(seconds / 60) минут \(seconds % 60) секунд")
                    Text("Завершено подходов: \(session.completed)").foregroundStyle(.secondary)
                    HStack {
                        if seconds == 0 {
                            Button(session.phase == .focus ? "Начать перерыв" : "Начать фокус") { focus.next() }.buttonStyle(.borderedProminent)
                        } else if session.deadline == nil {
                            Button("Продолжить") { focus.resume() }.buttonStyle(.borderedProminent)
                        } else {
                            Button("Пауза") { focus.pause() }.buttonStyle(.borderedProminent)
                        }
                        Button("Завершить сеанс") { focus.stop() }
                    }
                } else {
                    Image(systemName: "timer").font(.system(size: 36)).foregroundStyle(Palette.accent)
                    Text("Выберите задачу для фокуса").font(.headline)
                    Text("25 минут работы · 5 минут отдыха\nПосле четырёх подходов — 15 минут отдыха").foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if let item = state.selected, item.kind == .task, !item.deleted, !item.completed {
                        Button("Начать фокус по выбранной задаче") { state.startFocus(item) }.buttonStyle(.borderedProminent)
                    } else { Text("Откройте задачу и нажмите «Начать фокус».").foregroundStyle(.secondary) }
                }
            }
            if let error = focus.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
        }.padding(24).frame(width: 420).fixedSize(horizontal: false, vertical: true)
    }
}

struct PomodoroBar: View {
    let state: AppState
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack {
                Button { state.pomodoro.presented = true } label: {
                    Label("Помодоро", systemImage: "timer")
                }.buttonStyle(.plain)
                if let session = state.pomodoro.session {
                    let seconds = session.seconds(at: context.date)
                    Text(session.phase == .focus ? "Фокус" : "Перерыв").foregroundStyle(.secondary)
                    Text(String(format: "%02d:%02d", seconds / 60, seconds % 60)).monospacedDigit().fontWeight(.semibold)
                    Text(state.item(session.taskID)?.title ?? session.title).lineLimit(1).foregroundStyle(.secondary)
                    Spacer()
                    if seconds == 0 { Button("Открыть таймер") { state.pomodoro.presented = true } }
                    else if session.deadline == nil { Button("Продолжить") { state.pomodoro.resume() } }
                    else { Button("Пауза") { state.pomodoro.pause() } }
                } else { Spacer(); Text("25 минут на одну задачу").foregroundStyle(.secondary) }
            }.font(.system(size: 12)).padding(.horizontal, 14).padding(.vertical, 7).background(Palette.sidebar)
        }
    }
}
