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
    private var dates: [Date] {
        let start = calendar.dateInterval(of: .month, for: month)?.start ?? month
        let offset = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0 - offset, to: start) }
    }
    private var title: String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ru_RU"); formatter.timeZone = calendar.timeZone; formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: month).capitalized
    }
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(title).font(.system(size: 14, weight: .semibold)); Spacer()
                IconButton(symbol: "chevron.left", help: "Предыдущий месяц") { shift(-1) }
                IconButton(symbol: "chevron.right", help: "Следующий месяц") { shift(1) }
            }
            HStack(spacing: 0) { ForEach(["Пн","Вт","Ср","Чт","Пт","Сб","Вс"], id: \.self) { Text($0).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).frame(maxWidth: .infinity) } }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 3) {
                ForEach(dates, id: \.self) { date in
                    let chosen = calendar.isDate(date, inSameDayAs: selected)
                    let currentMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
                    Button { selected = date } label: {
                        Text("\(calendar.component(.day, from: date))").font(.system(size: 12, weight: chosen ? .semibold : .regular))
                            .frame(maxWidth: .infinity).frame(height: 29)
                            .foregroundStyle(chosen ? Color.white : currentMonth ? Color.primary : Color.secondary.opacity(0.5))
                            .background(chosen ? Palette.accent : .clear, in: RoundedRectangle(cornerRadius: 7))
                            .overlay { RoundedRectangle(cornerRadius: 7).stroke(calendar.isDateInToday(date) && !chosen ? Palette.accent : .clear, lineWidth: 1) }
                    }.buttonStyle(.plain).accessibilityLabel(dateLabel(date)).accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
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
    private func dateLabel(_ date: Date) -> String { let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.timeZone = calendar.timeZone; f.dateStyle = .long; return f.string(from: date) }
    private func shift(_ direction: Int) { month = calendar.date(byAdding: .month, value: direction, to: calendar.dateInterval(of: .month, for: month)?.start ?? month) ?? month }
}
