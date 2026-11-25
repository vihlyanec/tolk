import SwiftUI
import TaktCore

struct TaskDatePopover: View {
    @Binding var schedule: Schedule
    let calendar: Calendar
    let dismiss: () -> Void
    @ViewState private var selected: Date
    @ViewState private var month: Date
    @ViewState private var timed: Bool
    @ViewState private var hour: Int
    @ViewState private var minute: Int
    init(schedule: Binding<Schedule>, calendar: Calendar, dismiss: @escaping () -> Void) {
        _schedule = schedule; self.calendar = calendar; self.dismiss = dismiss
        let date = schedule.wrappedValue.date ?? Date()
        _selected = State(initialValue: date); _month = State(initialValue: date)
        _timed = State(initialValue: schedule.wrappedValue.isTimed)
        _hour = State(initialValue: calendar.component(.hour, from: date)); _minute = State(initialValue: calendar.component(.minute, from: date))
    }
    var body: some View {
        VStack(spacing: 12) {
            CalendarDayPicker(calendar: calendar, selected: selected, month: $month) { selected = $0 }
            HStack { Button("Сегодня") { selected = Date(); month = selected }; Spacer(); Button("Завтра") { selected = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date(); month = selected } }.buttonStyle(.plain).foregroundStyle(Palette.accent).font(.system(size: 12))
            Divider()
            Toggle("Весь день", isOn: Binding(get: { !timed }, set: { timed = !$0 })).toggleStyle(.switch).controlSize(.small)
            if timed {
                HStack(spacing: 6) {
                    Image(systemName: "clock").foregroundStyle(.secondary); Text("Время"); Spacer()
                    Picker("Часы", selection: $hour) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) } }.labelsHidden().frame(width: 65)
                    Text(":")
                    Picker("Минуты", selection: $minute) { ForEach(0..<60, id: \.self) { Text(String(format: "%02d", $0)).tag($0) } }.labelsHidden().frame(width: 65)
                }
                Text(calendar.timeZone.identifier).font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Без даты") { schedule = .unscheduled; dismiss() }.buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Button("Готово") {
                    let day = calendar.startOfDay(for: selected)
                    schedule = timed ? .timed(calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day) : .day(day)
                    dismiss()
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(16).frame(width: 300).background(Palette.sidebar)
    }
}
