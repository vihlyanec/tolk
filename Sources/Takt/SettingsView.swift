import SwiftUI
import TaktCore
import ServiceManagement
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var state: AppState
    let shortcutStatus: () -> String
    @ViewState private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @ViewState private var completionFeedback = CompletionFeedback()
    private func preference<T>(_ key: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(get: { state.data.preferences[keyPath: key] }, set: { value in state.change { $0.preferences[keyPath: key] = value } })
    }
    var body: some View {
        Form {
            Section("Внешний вид") {
                Picker("Тема", selection: preference(\.theme)) { Text("Тёмная").tag("dark"); Text("Светлая").tag("light"); Text("Системная").tag("system") }
                Toggle("Показывать завершённые задачи", isOn: preference(\.showCompleted))
            }
            Section("Календарь") {
                Stepper("Начало дня: \(state.data.preferences.startHour):00", value: Binding(get: { state.data.preferences.startHour }, set: { n in state.change { $0.preferences.startHour = min(n, $0.preferences.endHour - 1) } }), in: 0...23)
                Stepper("Конец дня: \(state.data.preferences.endHour):00", value: Binding(get: { state.data.preferences.endHour }, set: { n in state.change { $0.preferences.endHour = max(n, $0.preferences.startHour + 1) } }), in: 1...24)
                Slider(value: preference(\.hourHeight), in: 60...180, step: 6) { Text("Масштаб часа") }
                Picker("Часовой пояс", selection: Binding(get: { state.data.preferences.timeZone }, set: { state.setTimeZone($0) })) {
                    ForEach(Array(Set([state.data.preferences.timeZone,"Europe/Moscow","Europe/London","Europe/Berlin","Asia/Dubai","Asia/Yekaterinburg","Asia/Novosibirsk","Asia/Vladivostok","America/New_York"])).sorted(), id: \.self) { Text($0).tag($0) }
                }
                Text("При смене пояса задачи с временем сохраняют момент и отображаются в новом поясе. Неделя начинается с понедельника. Шаг переноса — 15 минут.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section("Выполнение задачи") {
                Toggle("Звук «дзинь»", isOn: Binding(get: { state.data.preferences.completionSoundEnabled ?? true }, set: { value in state.change { $0.preferences.completionSoundEnabled = value } }))
                Toggle("Тактильная отдача", isOn: Binding(get: { state.data.preferences.completionHapticsEnabled ?? true }, set: { value in state.change { $0.preferences.completionHapticsEnabled = value } }))
                HStack {
                    Text("Отдача работает на трекпадах с Force Touch.").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Попробовать") { completionFeedback.play(state.data.preferences) }
                }
            }
            Section("Напоминания по умолчанию") {
                Text("Для задач со временем").fontWeight(.medium)
                TimedReminderEditor(values: Binding(get: { state.data.preferences.defaultTimedReminderOffsets ?? [] }, set: { values in state.change { $0.preferences.defaultTimedReminderOffsets = values } }))
                Divider()
                Text("Для задач на весь день").fontWeight(.medium)
                AllDayReminderEditor(values: Binding(get: { state.data.preferences.defaultAllDayReminders ?? [] }, set: { values in state.change { $0.preferences.defaultAllDayReminders = values } }), calendar: state.calendar)
                Text("Можно добавить несколько уведомлений. Эти настройки используются задачами без собственных напоминаний.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section("Горячие клавиши и запуск") {
                Text(shortcutStatus()).font(.system(size: 12)).textSelection(.enabled)
                Toggle("Использовать Control-Shift-Q / D", isOn: preference(\.shiftedShortcuts))
                Text("Если Control-Q или Control-D заняты TickTick, временно используется вариант с Shift. Настройки TickTick не изменяются.").font(.system(size: 11)).foregroundStyle(.secondary)
                Toggle("Запускать при входе в macOS", isOn: $launchAtLogin).onChange(of: launchAtLogin) { _, enabled in
                    Task { @MainActor in
                        do { if enabled { try SMAppService.mainApp.register() } else { try await SMAppService.mainApp.unregister() } }
                        catch { state.errorMessage = "Автозапуск: \(error.localizedDescription)" }
                    }
                }
                Text("Закрытие главного окна оставляет приложение в строке меню. Команда «Завершить» останавливает глобальные сочетания и напоминания.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section("Данные на этом Mac") {
                Text(state.dataURL.path).font(.system(size: 10)).textSelection(.enabled).foregroundStyle(.secondary)
                HStack {
                    Button("Экспорт…") { exportData() }
                    Button("Восстановить из экспорта…") { importData() }
                    Button("Папка данных") { NSWorkspace.shared.open(state.dataURL.deletingLastPathComponent()) }
                }
                Text("Ежедневная резервная копия создаётся перед первым изменением дня. Экспорт содержит задачи, заметки, проекты, теги и настройки.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if !state.data.projects.filter(\.archived).isEmpty {
                Section("Архив проектов") {
                    ForEach(state.data.projects.filter(\.archived)) { project in
                        HStack { Text(project.name); Spacer(); Button("Вернуть") { state.change { s in if let i = s.projects.firstIndex(where: { $0.id == project.id }) { s.projects[i].archived = false } } } }
                    }
                }
            }
            Section("Обновления") {
                if let updater = state.appUpdater {
                    Text(updater.status).font(.system(size: 11)).foregroundStyle(.secondary)
                    if updater.configured {
                        Toggle("Проверять обновления автоматически", isOn: Binding(get: { updater.automaticChecks }, set: { updater.automaticChecks = $0 }))
                        Button("Проверить обновления…") { updater.check() }.disabled(!updater.canCheck)
                    }
                } else { Text("Обновления недоступны в Demo.").font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            Section("О Толке") {
                Text("Личный менеджер задач · версия \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "локальная сборка")\nЗадачи и заметки хранятся локально.").font(.system(size: 12))
                if let notice = state.notice { Text(notice).foregroundStyle(Palette.accent) }
            }
        }.formStyle(.grouped).frame(width: 580, height: 690)
            .preferredColorScheme(state.data.preferences.theme == "light" ? .light : state.data.preferences.theme == "dark" ? .dark : nil)
    }
    private func exportData() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Толк-\(Date().formatted(.iso8601.year().month().day())).json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Database.export(state.data, to: url); state.notice = "Экспорт сохранён" }
        catch { state.errorMessage = error.localizedDescription }
    }
    private func importData() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try Database.readExport(url)
            let alert = NSAlert(); alert.messageText = "Заменить данные Толка?"
            alert.informativeText = "Будет загружено записей: \(imported.items.count). Текущие данные сохранятся в отдельном экспорте перед заменой."
            alert.addButton(withTitle: "Заменить"); alert.addButton(withTitle: "Отмена")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let backup = state.dataURL.deletingLastPathComponent().appendingPathComponent("before-restore-\(UUID().uuidString).json")
            try Database.export(state.data, to: backup)
            state.change { $0 = imported }; state.selectedID = nil; state.scope = .all
            state.notice = "Данные восстановлены"
        } catch { state.errorMessage = "Не удалось восстановить: \(error.localizedDescription)" }
    }
}
