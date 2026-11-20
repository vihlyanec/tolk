import Charts
import SwiftUI
import TaktCore

struct TaskAnalyticsView: View {
    let state: AppState
    @ViewState private var days = 30
    @ViewState private var tagID: UUID?

    private var calendar: Calendar { state.calendar }
    private var tagFamily: Set<UUID>? { tagID.map(state.tagFamily) }
    private var tasks: [Item] {
        let family = tagFamily
        return state.data.items.filter { item in
            item.kind == .task && !item.deleted && (family.map { !state.tagIDs(for: item).isDisjoint(with: $0) } ?? true)
        }
    }

    var body: some View {
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: 1 - days, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? Date.distantFuture
        let period = start..<end
        let records = tasks
        let completed = records.filter { $0.completed && $0.completedAt.map(period.contains) == true }
        let wontDo = records.filter { $0.wontDoAt.map(period.contains) == true }
        let completedByDay = Dictionary(grouping: completed.compactMap(\.completedAt), by: calendar.startOfDay)
        let wontDoByDay = Dictionary(grouping: wontDo.compactMap(\.wontDoAt), by: calendar.startOfDay)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Аналитика").font(.system(size: 24, weight: .semibold))
                HStack(spacing: 18) {
                    Picker("Период", selection: $days) {
                        ForEach([7, 30, 90], id: \.self) { Text("\($0) дней").tag($0) }
                    }.fixedSize()
                    Picker("Тег", selection: $tagID) {
                        Text("Все теги").tag(nil as UUID?)
                        ForEach(state.data.tags) { Text("#" + $0.name).tag(Optional($0.id)) }
                    }.frame(maxWidth: 270)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 30) {
                    metric("Создано", records.filter { period.contains($0.created) }.count)
                    metric("Завершено", completed.count)
                    metric("Не буду выполнять", wontDo.count)
                    metric("Сейчас в работе", records.filter(\.isActiveTask).count)
                }
                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    Text("Результаты по дням").font(.headline)
                    if completed.isEmpty && wontDo.isEmpty {
                        Text("За этот период нет завершённых задач или решений не выполнять.")
                            .foregroundStyle(.secondary).padding(.vertical, 18)
                    } else {
                        Chart {
                            ForEach(completedByDay.keys.sorted(), id: \.self) { day in
                                BarMark(x: .value("Дата", day, unit: .day), y: .value("Задачи", completedByDay[day]?.count ?? 0))
                                    .foregroundStyle(by: .value("Результат", "Завершено"))
                            }
                            ForEach(wontDoByDay.keys.sorted(), id: \.self) { day in
                                BarMark(x: .value("Дата", day, unit: .day), y: .value("Задачи", wontDoByDay[day]?.count ?? 0))
                                    .foregroundStyle(by: .value("Результат", "Не буду выполнять"))
                            }
                        }
                        .chartXScale(domain: start...end)
                        .chartForegroundStyleScale(["Завершено": Palette.accent, "Не буду выполнять": Color(nsColor: .secondaryLabelColor)])
                        .environment(\.calendar, calendar)
                        .environment(\.timeZone, calendar.timeZone)
                        .frame(height: 210)
                        .accessibilityLabel("Завершённые задачи и решения не выполнять по дням")
                    }
                    if records.contains(where: { $0.completed && $0.completedAt == nil }) {
                        Text("Для старых завершённых задач без даты завершения доступен список «Завершённые».")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !completed.isEmpty || !wontDo.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Задачи за период").font(.headline).padding(.bottom, 8)
                        ForEach((completed + wontDo).sorted { ($0.completedAt ?? $0.wontDoAt ?? .distantPast) > ($1.completedAt ?? $1.wontDoAt ?? .distantPast) }) { item in
                            Button {
                                state.area = .tasks
                                state.scope = item.completed ? .completed : .wontDo
                                state.inspectorVisible = true
                                state.select(item.id)
                            } label: {
                                HStack {
                                    Image(systemName: item.completed ? "checkmark.circle" : "minus.circle").foregroundStyle(.secondary)
                                    Text(item.title).lineLimit(1)
                                    Spacer()
                                    if let date = item.completedAt ?? item.wontDoAt { Text(date, format: .dateTime.day().month()).foregroundStyle(.secondary) }
                                }.padding(.vertical, 10).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }.frame(maxWidth: 900, alignment: .leading).padding(28).frame(maxWidth: .infinity, alignment: .leading)
        }.environment(\.timeZone, calendar.timeZone)
    }

    private func metric(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value.formatted()).font(.system(size: 26, weight: .semibold)).monospacedDigit()
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
}

struct TaskActivityView: View {
    let item: Item
    let calendar: Calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Активность").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach((item.taskActivity ?? []).reversed()) { event in
                        entry(event.changes.map(TaskActivity.label), date: event.date)
                    }
                    entry(["Задача создана"], date: item.created)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(idealHeight: 260, maxHeight: 360)
        }.padding(16).frame(width: 320).environment(\.timeZone, calendar.timeZone)
    }

    private func entry(_ labels: [String], date: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(date, format: .dateTime.day().month().year().hour().minute())
                .font(.caption).foregroundStyle(.secondary)
            ForEach(labels, id: \.self) { Text($0) }
        }.accessibilityElement(children: .combine)
    }
}
