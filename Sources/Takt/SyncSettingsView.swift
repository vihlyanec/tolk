import SwiftUI
import TaktCore

struct SyncSettingsSections: View {
    @Bindable var state: AppState
    @ViewState private var token = ""
    private func conflictDescription(key: String, connection: TickTickSyncState) -> String {
        let localTitle: String = state.data.items.first(where: { $0.id.uuidString == key })?.title ?? ""
        let remoteTitle: String = connection.conflicts[key]?.remote.title ?? ""
        return "В Толке: \(localTitle)\nВ TickTick: \(remoteTitle)"
    }
    var body: some View {
        if let sync = state.syncCoordinator {
            Section("Apple Календарь") {
                Text("События выбранных календарей появляются рядом с задачами. Изменения подхватываются автоматически; резервная проверка работает в фоне раз в минуту.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Text(sync.appleStatus).font(.system(size: 12)).textSelection(.enabled)
                if let connection = state.data.appleCalendar {
                    if sync.appleAccessRequired {
                        Button("Разрешить доступ к календарям…") { sync.connectApple() }.disabled(state.isDemo || sync.appleBusy)
                    }
                    ForEach(connection.calendars) { calendar in
                        Toggle(isOn: Binding(get: { state.data.appleCalendar?.selected.contains(calendar.id) ?? false }, set: { sync.selectCalendar(calendar.id, enabled: $0) })) {
                            HStack(spacing: 8) {
                                Circle().fill(Color(hex: calendar.color)).frame(width: 7, height: 7)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(calendar.name)
                                    Text(calendar.account).font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if connection.calendars.isEmpty { Text("Календари пока недоступны. Проверьте аккаунты Calendar на этом Mac.").foregroundStyle(.secondary) }
                    HStack {
                        Button("Проверить сейчас") { sync.refreshApple() }.disabled(sync.appleBusy)
                        Button("Отключить") { sync.disconnectApple() }
                        if sync.appleBusy { ProgressView().controlSize(.small) }
                    }
                    Text("Если TickTick уже добавлен как календарь-подписка, оставьте его выключенным здесь, чтобы избежать дублей.").font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    HStack {
                        Button("Подключить Apple Календарь") { sync.connectApple() }.disabled(state.isDemo || sync.appleBusy)
                        if sync.appleBusy { ProgressView().controlSize(.small) }
                    }
                }
                if state.isDemo { Text("В Demo доступны только вымышленные события, доступ macOS не запрашивается.").font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            Section("TickTick") {
                Text(sync.tickTickStatus).font(.system(size: 12)).textSelection(.enabled)
                if let connection = state.data.tickTick {
                    if let date = connection.lastSuccess { Text("Последний успешный обмен: \(date.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 11)).foregroundStyle(.secondary) }
                    Picker("Обновлять каждые", selection: Binding(get: { state.data.tickTick?.options.intervalMinutes ?? 5 }, set: { n in state.change(undo: false) { $0.tickTick?.options.intervalMinutes = n } })) {
                        Text("3 минуты").tag(3); Text("5 минут").tag(5)
                    }
                    Toggle("Отправлять новые задачи из Входящих", isOn: Binding(get: { state.data.tickTick?.options.sendNewTasks ?? false }, set: { enabled in state.change { $0.tickTick?.options.sendNewTasks = enabled } }))
                    Text("Новые задачи в связанных проектах отправляются в TickTick. Старые локальные задачи не выгружаются. Удаление в локальную корзину не удаляет задачу в TickTick.").font(.system(size: 11)).foregroundStyle(.secondary)
                    if !connection.conflicts.isEmpty {
                        ForEach(connection.conflicts.keys.sorted(), id: \.self) { key in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(state.data.items.first { $0.id.uuidString == key }?.title ?? "Задача").fontWeight(.medium)
                                Text(conflictDescription(key: key, connection: connection)).font(.system(size: 11)).foregroundStyle(.secondary)
                                HStack {
                                    Button("Оставить версию Толка") { state.change(undo: false) { SyncEngine.resolve(key: key, useLocal: true, in: &$0) }; sync.refreshTickTick(manual: true) }
                                    Button("Принять TickTick") { state.change(undo: false) { SyncEngine.resolve(key: key, useLocal: false, in: &$0) } }
                                }
                            }
                        }
                    }
                    DisclosureGroup("Продлить доступ без потери связей…") {
                        Text("Используйте токен того же аккаунта TickTick. Связи и несохранённые правки останутся. Для другого аккаунта сначала отключите текущее подключение.").font(.system(size: 11)).foregroundStyle(.secondary)
                        SecureField("Новый API-токен того же аккаунта", text: $token).textFieldStyle(.roundedBorder)
                        Button("Проверить и заменить доступ") { sync.reauthorizeTickTick(token: token); token = "" }.disabled(state.isDemo || token.isEmpty || sync.tickTickBusy)
                    }
                    let missing = connection.links.values.filter(\.missing).count
                    if missing > 0 { Text("Не удалось найти в источнике: \(missing). Локальные записи сохранены.").font(.system(size: 11)).foregroundStyle(.secondary) }
                    HStack {
                        Button("Обновить") { sync.refreshTickTick(manual: true) }.disabled(sync.tickTickBusy)
                        Button("Отключить, оставить задачи") { sync.disconnectTickTick() }
                        if sync.tickTickBusy { ProgressView().controlSize(.small) }
                    }
                } else {
                    Text("Персональный API-токен: TickTick в браузере → Settings → Account → API Token. Он хранится только в Связке ключей Mac.").font(.system(size: 12)).foregroundStyle(.secondary)
                    SecureField("API-токен TickTick", text: $token).textFieldStyle(.roundedBorder).disabled(state.isDemo || sync.tickTickBusy)
                    if let preview = sync.preview {
                        Text("Будет импортировано: \(preview.projects.count) проектов, \(preview.tasks.count) задач. Существующие локальные задачи останутся отдельно.").font(.system(size: 12))
                        Toggle("Входящие, включая задачи без даты", isOn: Binding(get: { sync.importInbox }, set: { sync.importInbox = $0 }))
                        ForEach(preview.projects) { project in
                            Toggle(project.name, isOn: Binding(get: { sync.importProjects.contains(project.id) }, set: { enabled in
                                if enabled { sync.importProjects.insert(project.id) } else { sync.importProjects.remove(project.id) }
                            }))
                        }
                        DisclosureGroup("Связать с существующими проектами…") {
                            ForEach(preview.projects) { remote in
                                Picker(remote.name, selection: Binding(get: { sync.importProjectMapping[remote.id] }, set: { sync.importProjectMapping[remote.id] = $0 })) {
                                    Text("Создать отдельный проект").tag(nil as UUID?)
                                    ForEach(state.data.projects.filter { $0.kind == .task }) { project in Text(project.name).tag(Optional(project.id)) }
                                }
                            }
                        }
                        DisclosureGroup("Связать с существующими задачами…") {
                            Text("При первом импорте связанные записи примут данные TickTick. Названия не сопоставляются автоматически.").font(.system(size: 11)).foregroundStyle(.secondary)
                            ScrollView {
                                LazyVStack(alignment: .leading) {
                                    ForEach(preview.tasks) { remote in
                                        Picker(remote.title, selection: Binding(get: { sync.importMapping[remote.id] }, set: { sync.importMapping[remote.id] = $0 })) {
                                            Text("Создать отдельную задачу").tag(nil as UUID?)
                                            ForEach(state.data.items.filter { $0.kind == .task && !$0.deleted }) { local in Text(local.title).tag(Optional(local.id)) }
                                        }
                                    }
                                }
                            }.frame(maxHeight: 180)
                        }
                        HStack {
                            Button("Импортировать и подключить") { sync.acceptPreview(); token = "" }
                            Button("Отмена") { sync.cancelPreview(); token = "" }
                        }
                    } else {
                        HStack {
                            Button("Проверить и показать импорт") { sync.previewTickTick(token: token); token = "" }.disabled(state.isDemo || token.isEmpty || sync.tickTickBusy)
                            if sync.tickTickBusy { ProgressView().controlSize(.small); Button("Отмена") { sync.cancelPreview() } }
                        }
                    }
                    if state.isDemo { Text("Demo не подключается к TickTick и не читает Связку ключей.").font(.system(size: 11)).foregroundStyle(.secondary) }
                }
            }
        }
    }
}

struct ExternalEventCard: View {
    let event: ExternalEvent
    let state: AppState
    var compact = false
    @ViewState private var showing = false
    private var source: ExternalCalendar? { state.data.appleCalendar?.calendars.first { $0.id == event.calendarID } }
    var body: some View {
        Button { showing = true } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "calendar").font(.system(size: compact ? 9 : 11))
                    Text(event.title).font(.system(size: compact ? 10 : 12, weight: .medium)).lineLimit(compact ? 1 : 3)
                }
                if !compact {
                    Text(event.allDay ? "Весь день" : state.time(event.start) + "–" + state.time(event.end)).font(.system(size: 11)).lineLimit(1)
                    Text(source?.name ?? "Apple Календарь").font(.system(size: 10)).lineLimit(1)
                    if event.tentative { Text("Предварительно").font(.system(size: 10)) }
                    Spacer(minLength: 0)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(compact ? 3 : 5)
                .foregroundStyle(.primary)
                .background(Color(hex: source?.color ?? "598BFF").opacity(0.30), in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle()).clipped()
        }.buttonStyle(.plain)
            .help(event.title + " · " + (source?.name ?? "Apple Календарь") + "\nТолько просмотр")
            .accessibilityLabel("Событие Apple Календаря: " + event.title)
            .popover(isPresented: $showing) { ExternalEventInspector(event: event, source: source, calendar: state.calendar).frame(width: 340) }
    }
}
struct ExternalEventInspector: View {
    let event: ExternalEvent
    let source: ExternalCalendar?
    let calendar: Calendar
    private func stamp(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ru_RU"); formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .medium; formatter.timeStyle = event.allDay ? .none : .short
        return formatter.string(from: date)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(event.title).font(.system(size: 19, weight: .semibold)).textSelection(.enabled)
                Label(source.map { $0.name + " · " + $0.account } ?? "Apple Календарь", systemImage: "calendar").font(.system(size: 12)).foregroundStyle(.secondary)
                let range = event.interval(in: calendar)
                Text(stamp(range.start) + " — " + stamp(range.end))
                    .font(.system(size: 12))
                if event.allDay { Text("Весь день · дата окончания не включается").font(.system(size: 11)).foregroundStyle(.secondary) }
                if !event.location.isEmpty { Label(event.location, systemImage: "mappin.and.ellipse").textSelection(.enabled) }
                if !event.notes.isEmpty { Text(event.notes).textSelection(.enabled) }
                if let url = event.url, ["https", "http"].contains(url.scheme?.lowercased() ?? "") { Link("Открыть ссылку события", destination: url) }
                Divider()
                Text("Изменения вносятся в Apple Календаре. Толк обновит событие после синхронизации macOS.").font(.system(size: 11)).foregroundStyle(.secondary)
                Button("Открыть Apple Календарь") {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") { NSWorkspace.shared.openApplication(at: url, configuration: .init()) }
                }.buttonStyle(.borderedProminent).tint(Palette.accent)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxHeight: 520).background(Palette.sidebar)
    }
}
