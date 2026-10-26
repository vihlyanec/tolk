import SwiftUI
import TaktCore

struct TimedReminderEditor: View {
    @Binding var values: [Int]
    @ViewState private var custom = false
    @ViewState private var minutes = 20
    private func title(_ value: Int) -> String {
        value == 0 ? "В начале" : value % 1440 == 0 ? "За \(value / 1440) дн." : value % 60 == 0 ? "За \(value / 60) ч" : "За \(value) мин"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MetadataFlow {
                ForEach(Array(Set(values)).sorted(), id: \.self) { value in
                    Button { values.removeAll { $0 == value } } label: { Label(title(value), systemImage: "xmark.circle.fill").font(.system(size: 11)) }
                        .buttonStyle(.bordered).help("Убрать уведомление: " + title(value))
                }
            }
            Menu("Добавить уведомление") {
                ForEach([0,5,10,15,30,60,120,1440,2880,10080], id: \.self) { value in
                    Toggle(title(value), isOn: Binding(get: { values.contains(value) }, set: { on in values = on ? Array(Set(values + [value])).sorted() : values.filter { $0 != value } }))
                }
                Divider(); Button("Другое время…") { custom = true }
            }.fixedSize()
            if values.isEmpty { Text("Без уведомлений").font(.system(size: 11)).foregroundStyle(.secondary) }
        }.popover(isPresented: $custom) {
            VStack(alignment: .leading, spacing: 12) {
                Text("За сколько минут до начала?")
                TextField("Минуты", value: $minutes, format: .number).frame(width: 110)
                Button("Добавить") { if (0...525600).contains(minutes) { values = Array(Set(values + [minutes])).sorted(); custom = false } }.disabled(!(0...525600).contains(minutes))
            }.padding(18)
        }
    }
}
struct AllDayReminderEditor: View {
    @Binding var values: [AllDayReminder]
    let calendar: Calendar
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(values) { rule in
                HStack(spacing: 8) {
                    Picker("День уведомления", selection: Binding(get: { values.first { $0.id == rule.id }?.daysBefore ?? 0 }, set: { day in if let i = values.firstIndex(where: { $0.id == rule.id }) { values[i].daysBefore = day } })) {
                        ForEach(Array(Set([0,1,2,7,rule.daysBefore])).sorted(), id: \.self) { day in Text(day == 0 ? "В день задачи" : "За \(day) дн.").tag(day) }
                    }.labelsHidden().frame(maxWidth: 150)
                    DatePicker("Время уведомления", selection: Binding(get: {
                        let minute = values.first { $0.id == rule.id }?.minuteOfDay ?? 540
                        return calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
                    }, set: { date in
                        if let i = values.firstIndex(where: { $0.id == rule.id }) { values[i].minuteOfDay = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date) }
                    }), displayedComponents: .hourAndMinute).labelsHidden().environment(\.timeZone, calendar.timeZone)
                    IconButton(symbol: "minus.circle", help: "Убрать это уведомление") { values.removeAll { $0.id == rule.id } }
                }
            }
            Button { values.append(AllDayReminder()) } label: { Label("Добавить уведомление", systemImage: "plus") }
            if values.isEmpty { Text("Без уведомлений").font(.system(size: 11)).foregroundStyle(.secondary) }
        }
    }
}
struct TaskReminderEditor: View {
    @Bindable var state: AppState
    let id: UUID
    var initiallyExpanded = false
    @ViewState private var expanded = false
    private var item: Item? { state.data.items.first { $0.id == id } }
    var body: some View {
        if let item, item.schedule.date != nil {
            DisclosureGroup("Напоминания", isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Как в настройках по умолчанию", isOn: Binding(get: {
                        item.schedule.isTimed ? item.timedReminderOffsets == nil && item.reminderMinutes == nil : item.allDayReminders == nil
                    }, set: { useDefault in
                        state.update(id) { value in
                            if value.schedule.isTimed { value.timedReminderOffsets = useDefault ? nil : NotificationPlan.timedOffsets(item: value, preferences: state.data.preferences); value.reminderMinutes = nil }
                            else { value.allDayReminders = useDefault ? nil : NotificationPlan.allDayRules(item: value, preferences: state.data.preferences) }
                        }
                    })).toggleStyle(.checkbox)
                    if item.schedule.isTimed {
                        TimedReminderEditor(values: Binding(get: { NotificationPlan.timedOffsets(item: self.item ?? item, preferences: state.data.preferences) }, set: { values in state.update(id) { $0.timedReminderOffsets = values; $0.reminderMinutes = nil } }))
                    } else {
                        AllDayReminderEditor(values: Binding(get: { NotificationPlan.allDayRules(item: self.item ?? item, preferences: state.data.preferences) }, set: { values in state.update(id) { $0.allDayReminders = values } }), calendar: state.calendar)
                    }
                }.padding(.top, 8)
            }.onAppear { expanded = initiallyExpanded }
        } else { Text("Назначьте дату для напоминаний").font(.system(size: 11)).foregroundStyle(.secondary) }
    }
}
