import SwiftUI
import Observation
import UserNotifications
import TaktCore

@Observable final class PomodoroController {
    private(set) var session: Pomodoro?
    var pausePrompt = false
    var pauseDraft = ""
    var error: String?
    @ObservationIgnored var didChange: (String) -> Void = { _ in }
    private let url: URL?
    private let notificationsEnabled: Bool
    @ObservationIgnored private let startFeedback = FocusStartFeedback()
    @ObservationIgnored var playStartSound: () -> Void = { }
    @ObservationIgnored private var notificationTask: Task<Void, Never>?
    init(url: URL?, notificationsEnabled: Bool = true) {
        self.url = url; self.notificationsEnabled = notificationsEnabled
        if url != nil, notificationsEnabled { playStartSound = { [startFeedback] in startFeedback.play() } }
        if let url, FileManager.default.fileExists(atPath: url.path) {
            do { session = try JSONDecoder().decode(Pomodoro.self, from: Data(contentsOf: url)) }
            catch { self.error = "Не удалось прочитать таймер. Начните новый сеанс." }
        }
    }
    func start(_ item: Item, now: Date = Date()) {
        session = Pomodoro(taskID: item.id, title: item.title, now: now); pausePrompt = false; save()
        playStartSound()
    }
    func pause(now: Date = Date()) {
        guard let current = session, current.deadline != nil, current.seconds(at: now) > 0 else { return }
        session?.pause(at: now); save()
        pauseDraft = current.resumeNote ?? ""; pausePrompt = true
    }
    func saveResumeNote(_ text: String) {
        let value = String(text.prefix(2000)).trimmingCharacters(in: .whitespacesAndNewlines)
        session?.resumeNote = value.isEmpty ? nil : value
        save(); pausePrompt = false
    }
    func skipResumeNote() { pausePrompt = false }

    func resume(now: Date = Date()) {
        let startsFocus = session?.phase == .focus && session?.deadline == nil && (session?.remaining ?? 0) > 0
        pausePrompt = false; session?.resume(at: now); save()
        if startsFocus { playStartSound() }
    }
    func next(now: Date = Date()) {
        let finishedBreak = session.map { $0.phase != .focus && $0.seconds(at: now) == 0 } ?? false
        session?.next(at: now); save()
        if finishedBreak { playStartSound() }
    }
    func stop() { session = nil; pausePrompt = false; save() }
    var sharedSession: String {
        guard let session else { return "" }
        let value: [String: SyncJSON] = ["taskID":.string(session.taskID.uuidString.lowercased()),"title":.string(session.title),
            "phase":.string(session.phase.rawValue),"completed":.number(Double(session.completed)),"remaining":.number(session.remaining),
            "deadline":session.deadline.map { .number($0.timeIntervalSince1970 * 1000) } ?? .null,"resumeNote":.string(session.resumeNote ?? "")]
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return (try? String(data:encoder.encode(value),encoding:.utf8)) ?? ""
    }
    func acceptSharedSession(_ encoded: String) throws {
        guard !encoded.isEmpty else { session = nil; pausePrompt = false; save(notify:false); return }
        let fields = try JSONDecoder().decode(SyncFields.self,from:Data(encoded.utf8))
        guard let id = fields["taskID"]?.string.flatMap(UUID.init(uuidString:)), let title = fields["title"]?.string,
              let phase = fields["phase"]?.string.flatMap(Pomodoro.Phase.init(rawValue:)),
              let completed = fields["completed"]?.int, completed >= 0,
              case .number(let remaining) = fields["remaining"], remaining.isFinite, (0...1500).contains(remaining) else { throw TaktError.invalid("Не удалось прочитать сеанс аккаунта") }
        var value = Pomodoro(taskID:id,title:title); value.phase = phase; value.completed = completed; value.remaining = remaining
        if case .number(let deadline) = fields["deadline"], deadline.isFinite { value.deadline = Date(timeIntervalSince1970:deadline/1000) } else { value.deadline = nil }
        value.resumeNote = fields["resumeNote"]?.string
        session = value; pausePrompt = false; save(notify:false)
    }
    private func save(notify: Bool = true) {
        do {
            if let url {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if let session { try JSONEncoder().encode(session).write(to: url, options: .atomic); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
                else if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            }
            error = nil
        } catch { self.error = "Таймер работает, но не сохранён: \(error.localizedDescription)" }
        if notify { didChange(sharedSession) }
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
                content.body = current.title; content.sound = NotificationAudio.phaseEnd(current.phase).notificationSound
                try await center.add(UNNotificationRequest(identifier: "tolk-pomodoro", content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, deadline.timeIntervalSinceNow), repeats: false)))
            } catch { if !Task.isCancelled { self.error = "Не удалось включить сигнал таймера." } }
        }
    }
}

struct PomodoroPauseNote: View {
    let state: AppState
    var body: some View {
        @Bindable var focus = state.pomodoro
        VStack(alignment: .leading, spacing: 16) {
            Text("С чего продолжить?").font(.title2.bold())
            Text("Таймер на паузе. Оставьте себе следующий шаг — или пропустите.").foregroundStyle(.secondary)
            TextField("Например, начать с третьего пункта", text: $focus.pauseDraft, axis: .vertical)
                .lineLimit(4...8).textFieldStyle(.roundedBorder).accessibilityLabel("С чего продолжить, необязательно")
            HStack { Button("Пропустить") { focus.skipResumeNote() }.keyboardShortcut(.cancelAction); Spacer()
                Button("Сохранить") { focus.saveResumeNote(focus.pauseDraft) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 430)
    }
}

struct PomodoroWorkspace: View {
    @Bindable var state: AppState
    private var focus: PomodoroController { state.pomodoro }
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ScrollView { VStack(spacing: 0) {
                    HStack { Text("Помодоро").font(.system(size: 24, weight: .bold)); Spacer()
                        Menu { taskChoices } label: { Label(focus.session == nil ? "Выбрать задачу" : "Сменить задачу", systemImage: "plus") }.fixedSize()
                    }.padding(24)
                    Spacer(minLength: 12)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let session = focus.session
                        let seconds = session?.seconds(at: context.date) ?? 1500
                        VStack(spacing: 24) {
                            Text(session.map { $0.phase == .focus ? "Фокус" : $0.phase == .longBreak ? "Длинный перерыв" : "Перерыв" } ?? "Фокус").foregroundStyle(.secondary)
                            Text(session.flatMap { state.item($0.taskID)?.title ?? $0.title } ?? "Выберите задачу для фокуса").font(.title3.weight(.medium)).multilineTextAlignment(.center).lineLimit(3)
                            ZStack {
                                Circle().stroke(Palette.line, lineWidth: 4)
                                Text(String(format: "%02d:%02d", seconds / 60, seconds % 60)).font(.system(size: 60, weight: .regular)).monospacedDigit()
                            }.frame(width: 250, height: 250).accessibilityElement(children: .combine)
                            if let session {
                                HStack {
                                    if seconds == 0 { Button(session.phase == .focus ? "Начать перерыв" : "Начать фокус") { focus.next() }.buttonStyle(.borderedProminent) }
                                    else if session.deadline == nil { Button("Продолжить") { focus.resume() }.buttonStyle(.borderedProminent) }
                                    else { Button("Пауза") { focus.pause() }.buttonStyle(.borderedProminent) }
                                    Button("Завершить сеанс") { focus.stop() }
                                }.controlSize(.large)
                            } else { Menu("Начать") { taskChoices }.menuStyle(.borderlessButton).fixedSize().padding(12).background(Palette.accent.opacity(0.15), in: Capsule()) }
                        }.padding(.horizontal, 24)
                    }
                    Spacer(minLength: 20)
                    if geometry.size.width < 800 { overview.padding(24) }
                    Text("25 минут фокуса · 5 минут отдыха · 15 после четырёх подходов").font(.caption).foregroundStyle(.secondary).padding(20)
                    if let error = focus.error { Text(error).foregroundStyle(.red).font(.caption).padding() }
                }.frame(maxWidth: .infinity, minHeight: geometry.size.height) }
                if geometry.size.width >= 800 { Divider(); ScrollView { overview.padding(28) }.frame(width: min(380, geometry.size.width * 0.4)).background(Palette.sidebar) }
            }
        }
    }
    @ViewBuilder private var taskChoices: some View {
        let tasks = state.data.items.filter { $0.kind == .task && !$0.deleted && !$0.completed }
        if tasks.isEmpty { Text("Сначала добавьте задачу") }
        ForEach(tasks) { item in Button(item.title) { state.startFocus(item) } }
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Обзор сеанса").font(.title2.bold())
            HStack { Text("Завершено подходов"); Spacer(); Text("\(focus.session?.completed ?? 0)").font(.title2).monospacedDigit() }
            Divider()
            Text("С чего продолжить").font(.title3.bold())
            if let note = focus.session?.resumeNote, !note.isEmpty { Text(note).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
            else { Text("При паузе можно записать следующий шаг. Это необязательно.").foregroundStyle(.secondary) }
            if let session = focus.session, session.deadline == nil {
                Button("Изменить заметку") { focus.pauseDraft = session.resumeNote ?? ""; focus.pausePrompt = true }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PomodoroBar: View {
    let state: AppState
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack {
                Button { state.area = .focus } label: {
                    Label("Помодоро", systemImage: "timer")
                }.buttonStyle(.plain)
                if let session = state.pomodoro.session {
                    let seconds = session.seconds(at: context.date)
                    Text(session.phase == .focus ? "Фокус" : "Перерыв").foregroundStyle(.secondary)
                    Text(String(format: "%02d:%02d", seconds / 60, seconds % 60)).monospacedDigit().fontWeight(.semibold)
                    Text(state.item(session.taskID)?.title ?? session.title).lineLimit(1).foregroundStyle(.secondary)
                    Spacer()
                    if seconds == 0 { Button("Открыть таймер") { state.area = .focus } }
                    else if session.deadline == nil { Button("Продолжить") { state.pomodoro.resume() } }
                    else { Button("Пауза") { state.pomodoro.pause() } }
                } else { Spacer(); Text("25 минут на одну задачу").foregroundStyle(.secondary) }
            }.font(.system(size: 12)).padding(.horizontal, 14).padding(.vertical, 7).background(Palette.sidebar)
        }
    }
}
