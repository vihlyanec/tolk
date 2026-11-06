import SwiftUI
import TaktCore

struct AccountSettingsSection: View {
    @Bindable var state: AppState
    private func label(_ field: String) -> String {
        ["title":"Название","body":"Описание","schedule":"Дата и время","completed":"Выполнение","deleted":"Удаление","projectID":"Проект","tagIDs":"Метки","duration":"Длительность","theme":"Тема","timeZone":"Часовой пояс","focusSession":"Помодоро","checklist":"Чек-лист","order":"Порядок" ][field] ?? "Свойство записи"
    }
    private func display(_ value: SyncJSON?, field: String) -> String {
        guard let value, value != .null else { return "Не задано" }
        switch value {
        case .string(let text):
            if field == "projectID", let id = UUID(uuidString:text) { return state.data.projects.first { $0.id == id }?.name ?? "Проект" }
            if field == "focusSession" { return text.isEmpty ? "Нет сеанса" : "Сеанс фокуса" }
            return text.isEmpty ? "Не задано" : text
        case .bool(let b): return b ? "Да" : "Нет"
        case .number(let n): return n.formatted()
        case .array(let values): return "Элементов: \(values.count)"
        case .object(let data):
            if field == "schedule" {
                if let day = data["day"]?.string { return day }
                if case .number(let instant) = data["instant"] { return Date(timeIntervalSince1970:instant).formatted(date:.abbreviated,time:.shortened) }
                return "Без даты"
            }
            return "Настройки изменены"
        case .null: return "Не задано"
        }
    }
    var body: some View {
        Section("Аккаунт · Mac и iPhone") {
            if let service = state.accountService {
                if let account = state.data.accountSync {
                    Text(account.name).fontWeight(.medium)
                    Text(service.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    if service.accessRequired {
                        Button(service.connecting ? "Ожидаем подтверждение…" : "Подтвердить доступ заново") { service.connect(reauthorizing:true) }.disabled(service.connecting || service.busy)
                    }
                    if service.recoveryRequired {
                        Text("Сначала будет сохранена копия данных Mac. Затем вы сможете выбрать версии несохранённых изменений.").font(.caption).foregroundStyle(.secondary)
                        Button("Сверить версии после восстановления") { service.recover() }.disabled(service.busy)
                    }
                    if !account.pending.isEmpty { Text("Ожидают отправки: \(account.pending.count)").font(.caption) }
                    HStack {
                        Button("Синхронизировать") { service.sync() }.disabled(service.busy)
                        Button("Открыть веб-версию") { if let url = URL(string:account.origin) { NSWorkspace.shared.open(url) } }
                        Button("Отключить") { service.disconnect() }.disabled(service.busy || !account.pending.isEmpty || !account.conflicts.isEmpty)
                    }
                    ForEach(account.conflicts) { conflict in
                        VStack(alignment:.leading,spacing:8) {
                            Text(conflict.remote.data["title"]?.string ?? "Настройки аккаунта").fontWeight(.medium)
                            ForEach(conflict.operation.patch.keys.sorted(),id:\.self) { field in
                                VStack(alignment:.leading,spacing:3) {
                                    Text(label(field)).font(.caption.weight(.medium))
                                    Text("Mac: " + display(conflict.operation.patch[field],field:field)).font(.caption).lineLimit(4).textSelection(.enabled)
                                    Text("Аккаунт: " + display(conflict.remote.data[field],field:field)).font(.caption).lineLimit(4).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                            }
                            HStack { Button("Оставить с Mac") { service.resolve(conflict.id,local:true) }; Button("Взять из аккаунта") { service.resolve(conflict.id,local:false) } }.disabled(service.busy)
                        }.padding(.vertical,8)
                    }
                } else {
                    Text("Общие задачи, заметки, проекты, метки и настройки на Mac и iPhone.").font(.caption).foregroundStyle(.secondary)
                    TextField("Адрес веб-версии",text:Binding(get:{service.origin},set:{service.origin=$0})).disabled(service.connecting)
                    if service.connecting { Button("Отменить подключение") { service.cancelConnection() } }
                    else { Button("Подключить и объединить данные") { service.connect() }.buttonStyle(.borderedProminent).disabled(state.isDemo) }
                    Text(service.status).font(.caption).foregroundStyle(.secondary)
                    Text("Откроется ваш сайт. Войдите в свой аккаунт и подтвердите этот Mac. Существующие записи на обоих устройствах сохранятся; одновременные правки потребуют выбора версии.").font(.caption).foregroundStyle(.secondary)
                }
            } else { Text("Подключение аккаунта недоступно в этой проверке.").font(.caption) }
        }
    }
}
