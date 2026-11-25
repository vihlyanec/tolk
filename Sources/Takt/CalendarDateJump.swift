import SwiftUI

struct CalendarDateJump: View {
    let calendar: Calendar
    let jump: (Date) -> Void
    @ViewState private var selected: Date
    @ViewState private var month: Date
    @FocusState private var navigationFocused: Bool

    init(anchor: Date, calendar: Calendar, jump: @escaping (Date) -> Void) {
        self.calendar = calendar
        self.jump = jump
        _selected = State(initialValue: calendar.startOfDay(for: anchor))
        _month = State(initialValue: anchor)
    }

    var body: some View {
        VStack(spacing: 12) {
            CalendarDayPicker(calendar: calendar, selected: selected, month: $month, choose: jump)
            Divider()
            HStack {
                Button("Сегодня") { jump(Date()) }
                Spacer()
                Button("Перейти") { jump(selected) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(16).frame(width: 300).background(Palette.sidebar)
            .focusable().focused($navigationFocused).focusEffectDisabled()
            .onAppear { navigationFocused = true }
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { key in
                let offset = switch key.key {
                case .leftArrow: -1
                case .rightArrow: 1
                case .upArrow: -7
                default: 7
                }
                if let day = calendar.date(byAdding: .day, value: offset, to: selected) {
                    selected = day; month = day
                }
                return .handled
            }
    }

    static func periodTitle(for anchor: Date, mode: String, calendar: Calendar) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "ru_RU")
        format.timeZone = calendar.timeZone
        switch mode {
        case "День":
            format.dateFormat = "d MMMM"
            return format.string(from: anchor)
        case "Неделя":
            guard let start = calendar.dateInterval(of: .weekOfYear, for: anchor)?.start,
                  let end = calendar.date(byAdding: .day, value: 6, to: start) else { break }
            let sameMonth = calendar.isDate(start, equalTo: end, toGranularity: .month)
            let sameYear = calendar.isDate(start, equalTo: end, toGranularity: .year)
            format.dateFormat = sameMonth ? "d" : sameYear ? "d MMMM" : "d MMM yyyy"
            let first = format.string(from: start)
            format.dateFormat = sameYear ? "d MMMM" : "d MMM yyyy"
            return first + (sameMonth ? "–" : " — ") + format.string(from: end)
        default: break
        }
        format.dateFormat = "LLLL yyyy"
        return format.string(from: anchor).capitalized
    }
}

struct CalendarDayPicker: View {
    let calendar: Calendar
    let selected: Date
    @Binding var month: Date
    let choose: (Date) -> Void

    private var days: [Date] {
        let start = calendar.dateInterval(of: .month, for: month)?.start ?? month
        let offset = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0 - offset, to: start) }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(CalendarDateJump.periodTitle(for: month, mode: "Месяц", calendar: calendar))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                IconButton(symbol: "chevron.left", help: "Предыдущий месяц") { shift(-1) }
                IconButton(symbol: "chevron.right", help: "Следующий месяц") { shift(1) }
            }
            HStack(spacing: 0) {
                ForEach(["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"], id: \.self) { label in
                    Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 3) {
                ForEach(days, id: \.self) { date in
                    let chosen = calendar.isDate(date, inSameDayAs: selected)
                    let currentMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
                    Button { choose(date) } label: {
                        Text("\(calendar.component(.day, from: date))")
                            .font(.system(size: 12, weight: chosen ? .semibold : .regular))
                            .frame(maxWidth: .infinity).frame(height: 29)
                            .foregroundStyle(chosen ? Color.black : currentMonth ? Color.primary : Color.secondary)
                            .background(chosen ? Palette.accent : .clear, in: RoundedRectangle(cornerRadius: 7))
                            .overlay {
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(calendar.isDateInToday(date) && !chosen ? Palette.accent : .clear)
                            }
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(dateLabel(date)).accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
        }
    }

    private func dateLabel(_ date: Date) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "ru_RU")
        format.timeZone = calendar.timeZone
        format.dateStyle = .long
        return format.string(from: date)
    }
    private func shift(_ direction: Int) {
        month = calendar.date(byAdding: .month, value: direction, to: calendar.dateInterval(of: .month, for: month)?.start ?? month) ?? month
    }
}
