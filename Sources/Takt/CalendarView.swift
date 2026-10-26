import SwiftUI
import TaktCore
import UniformTypeIdentifiers

struct CalendarView: View {
    @Bindable var state: AppState
    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { periodControls; Spacer(minLength: 8); viewControls }.frame(minWidth: 740, minHeight: 40)
                    VStack(spacing: 4) {
                        HStack(spacing: 8) { periodControls; Spacer(minLength: 0) }
                        HStack(spacing: 8) { viewControls; Spacer(minLength: 0) }
                    }
                }.padding(.horizontal, 18).padding(.vertical, 12)

                Divider()
                if state.calendarMode == "Месяц" { MonthGrid(state: state) }
                else { timeline }
            }.frame(minWidth: 620, maxWidth: .infinity)
                .background(CalendarSwipeSurface(advance: advance))
            PlanningQueue(state: state).frame(minWidth: 280, idealWidth: 310, maxWidth: 330)
        }
        .onReceive(Timer.publish(every: 0.12, on: .main, in: .common).autoconnect()) { _ in
            if state.draggingID != nil && NSEvent.pressedMouseButtons == 0 { state.endDrag() }
        }
        .onChange(of: state.calendarMode) { _, _ in state.endDrag(); state.calendarEditingID = nil }
        .onChange(of: state.anchor) { _, _ in state.endDrag(); state.calendarEditingID = nil }
    }
    private var periodControls: some View {
        HStack(spacing: 8) {
            Text(monthTitle).font(.system(size: 21, weight: .semibold)).lineLimit(1).fixedSize(horizontal: true, vertical: false)
            IconButton(symbol: "chevron.left", help: "Предыдущий период") { advance(-1) }
            IconButton(symbol: "chevron.right", help: "Следующий период") { advance(1) }
            Button("Сегодня") { state.anchor = Date() }.buttonStyle(.bordered)
        }
    }
    private var viewControls: some View {
        HStack(spacing: 8) {
            Picker("Вид календаря", selection: $state.calendarMode) {
                ForEach(["День", "Неделя", "Месяц"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().frame(width: 190)
            IconButton(symbol: "minus.magnifyingglass", help: "Уменьшить масштаб времени") { state.change(undo: false) { $0.preferences.hourHeight = max(60, $0.preferences.hourHeight - 12) } }
            IconButton(symbol: "plus.magnifyingglass", help: "Увеличить масштаб времени") { state.change(undo: false) { $0.preferences.hourHeight = min(180, $0.preferences.hourHeight + 12) } }
            IconButton(symbol: "slider.horizontal.3", help: "Настройки календаря") { state.showSettings() }
        }
    }
    private var monthTitle: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.timeZone = state.calendar.timeZone; f.dateFormat = "LLLL yyyy"
        return f.string(from: state.anchor).capitalized
    }
    private var days: [Date] {
        let start = state.calendarMode == "День" ? state.calendar.startOfDay(for: state.anchor) : state.calendar.dateInterval(of: .weekOfYear, for: state.anchor)?.start ?? state.anchor
        return (0..<(state.calendarMode == "День" ? 1 : 7)).compactMap { state.calendar.date(byAdding: .day, value: $0, to: start) }
    }
    private func advance(_ direction: Int) {
        state.anchor = state.calendar.date(byAdding: state.calendarMode == "Месяц" ? .month : .day, value: direction * (state.calendarMode == "Неделя" ? 7 : 1), to: state.anchor) ?? state.anchor
    }
    private var timeline: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 800
            let timeAxis: CGFloat = compact ? 44 : 54
            let headerHeight: CGFloat = compact ? 60 : 70
            let dayWidth = max(0, (geometry.size.width - timeAxis) / CGFloat(days.count))
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Color.clear.frame(width: timeAxis)
                    ForEach(days, id: \.self) { day in
                        VStack(spacing: 5) {
                            Text(weekday(day)).font(.system(size: compact ? 10 : 11)).foregroundStyle(.secondary)
                            Text("\(state.calendar.component(.day, from: day))").font(.system(size: 19, weight: .medium))
                                .frame(width: 30, height: 30).background(state.calendar.isDateInToday(day) ? Palette.accent : .clear, in: Circle())
                                .foregroundStyle(state.calendar.isDateInToday(day) ? .white : .primary)
                        }.frame(width: dayWidth, height: headerHeight)
                    }
                }.frame(height: headerHeight)
                HStack(alignment: .top, spacing: 0) {
                    Text("Весь\nдень").font(.system(size: 10)).foregroundStyle(.secondary).frame(width: timeAxis, height: 38)
                    ScrollView(.vertical) {
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(days, id: \.self) { day in
                                let items = allDayItems(on: day)
                                VStack(spacing: 3) {
                                    ForEach(items) { item in
                                        HStack(spacing: 2) {
                                            CompleteButton(item: item) { state.complete(item.id) }
                                            Text(item.title).font(.system(size: compact ? 11 : 12)).strikethrough(item.completed).foregroundStyle(item.completed ? .secondary : .primary).lineLimit(1)
                                        }.padding(.horizontal, 3).frame(height: 26).frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color(hex: state.color(item)).opacity(item.completed ? 0.18 : 0.40), in: RoundedRectangle(cornerRadius: 3))
                                            .contentShape(Rectangle())
                                            .onTapGesture { state.selectCalendar(item.id) }.onDrag { state.beginDrag(item) }
                                            .popover(isPresented: editorBinding(item.id)) { ItemInspector(state: state, id: item.id).frame(width: 340, height: 620) }
                                    }
                                }.padding(3).frame(width: dayWidth, alignment: .top).frame(minHeight: 38)
                                    .contentShape(Rectangle())
                                    .dropDestination(for: String.self) { strings, _ in
                                        guard let id = strings.first.flatMap(UUID.init(uuidString:)), state.item(id).map({ $0.kind == .task && !$0.deleted }) == true else { return false }
                                        state.update(id) { $0.schedule = .day(day) }; state.endDrag(); return true
                                    }
                            }
                        }
                    }.scrollIndicators(.visible).accessibilityLabel("Задачи на весь день")
                }.frame(height: min(allDayHeight, max(64, min(220, geometry.size.height * 0.32))))
                Divider()
                ScrollViewReader { reader in
                    ScrollView(.vertical) {
                        HStack(alignment: .top, spacing: 0) {
                            VStack(spacing: 0) {
                                ForEach(state.data.preferences.startHour..<state.data.preferences.endHour, id: \.self) { hour in
                                    Text(String(format: "%02d:00", hour)).font(.system(size: compact ? 10 : 11)).monospacedDigit().foregroundStyle(.secondary)
                                        .frame(width: timeAxis, height: state.data.preferences.hourHeight, alignment: .top).id(hour)
                                }
                            }
                            ForEach(days, id: \.self) { day in
                                DayColumn(state: state, day: day).frame(width: dayWidth)
                            }
                        }.padding(.top, 7)
                    }.onAppear { reader.scrollTo(max(state.data.preferences.startHour, 8), anchor: .top) }
                }
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
    private func editorBinding(_ id: UUID) -> Binding<Bool> {
        Binding(get: { state.calendarEditingID == id }, set: { if !$0 { state.calendarEditingID = nil } })
    }
    private func allDayItems(on day: Date) -> [Item] {
        state.calendarItems.filter { !$0.schedule.isTimed && $0.schedule.date.map { state.calendar.isDate($0, inSameDayAs: day) } == true }
    }
    private var allDayHeight: Double {
        let count = days.map { allDayItems(on: $0).count }.max() ?? 0
        return max(38, Double(count) * 29 + 6)
    }
    private func weekday(_ day: Date) -> String { let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.timeZone = state.calendar.timeZone; f.dateFormat = "EE"; return f.string(from: day).capitalized }
}

struct DayColumn: View {
    @Bindable var state: AppState
    let day: Date
    @ViewState private var hoverMinute: Int?
    @GestureState private var creationRange: [Double] = []
    private var startMinute: Double { Double(state.data.preferences.startHour * 60) }
    private var height: Double { Double(state.data.preferences.endHour - state.data.preferences.startHour) * state.data.preferences.hourHeight }
    private var pixels: Double { state.data.preferences.hourHeight / 60 }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Rectangle().fill(state.calendar.isDateInToday(day) ? Palette.accent.opacity(0.025) : .clear)
                Path { path in
                    path.move(to: .zero); path.addLine(to: CGPoint(x: 0, y: height))
                    for half in 0...((state.data.preferences.endHour - state.data.preferences.startHour) * 2) {
                        let y = Double(half) * state.data.preferences.hourHeight / 2
                        path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                }.stroke(Palette.line, lineWidth: 0.5)
                Color.clear.contentShape(Rectangle()).onTapGesture(count: 2) { point in
                    let minutes = snapped(point.y)
                    if let date = date(minutes) { state.showQuick(date) }
                }
                .gesture(DragGesture(minimumDistance: 6)
                    .updating($creationRange) { value, range, _ in range = [value.startLocation.y, value.location.y] }
                    .onEnded { value in
                        let a = snapped(min(value.startLocation.y, value.location.y))
                        let b = snapped(max(value.startLocation.y, value.location.y))
                        if let start = date(a) { state.showRangeQuick(start, max(15, b - a)) }
                    })
                if creationRange.count == 2 {
                    let a = snapped(creationRange.min() ?? 0), b = snapped(creationRange.max() ?? 0)
                    RoundedRectangle(cornerRadius: 5).fill(Palette.accent.opacity(0.18))
                        .overlay { RoundedRectangle(cornerRadius: 5).stroke(Palette.accent, lineWidth: 1) }
                        .frame(width: geometry.size.width - 6, height: Double(max(15, b - a)) * pixels)
                        .overlay(alignment: .topLeading) { Text("\(date(a).map(state.time) ?? "") · \(max(15, b - a)) мин").font(.system(size: 11)).padding(5) }
                        .offset(x: 3, y: Double(a - Int(startMinute)) * pixels).allowsHitTesting(false)
                }
                let placements = CalendarLayout.placements(items: state.calendarItems, day: day, calendar: state.calendar)
                ForEach(placements) { placement in
                    if let item = state.calendarItems.first(where: { $0.id == placement.id }) {
                        let clippedStart = max(startMinute, placement.startMinute)
                        let clippedEnd = min(Double(state.data.preferences.endHour * 60), placement.endMinute)
                        if clippedEnd > clippedStart {
                            let width = max(15, (geometry.size.width - 5) / Double(placement.laneCount) - 3)
                            CalendarEvent(state: state, item: item, width: width, height: max(18, (clippedEnd - clippedStart) * pixels), pixelsPerMinute: pixels)
                                .offset(x: 3 + Double(placement.lane) * (width + 3), y: (clippedStart - startMinute) * pixels)
                        }
                    }
                }
                if let minute = hoverMinute, state.draggingID != nil {
                    RoundedRectangle(cornerRadius: 4).fill(Palette.accent.opacity(0.18)).overlay { RoundedRectangle(cornerRadius: 4).stroke(Palette.accent, style: StrokeStyle(lineWidth: 1, dash: [4])) }
                        .frame(width: geometry.size.width - 6, height: Double(state.draggingItem?.duration ?? 30) * pixels).overlay(alignment: .topLeading) { Text(date(minute).map(state.time) ?? "").font(.system(size: 11)).padding(4) }
                        .offset(x: 3, y: Double(minute - Int(startMinute)) * pixels).allowsHitTesting(false)
                }
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    if state.calendar.isDate(context.date, inSameDayAs: day) {
                        let parts = state.calendar.dateComponents([.hour, .minute], from: context.date)
                        let minute = Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
                        if minute >= startMinute && minute < Double(state.data.preferences.endHour * 60) {
                            Rectangle().fill(Palette.accent).frame(height: 1).overlay(alignment: .leading) { Circle().fill(Palette.accent).frame(width: 5, height: 5) }.offset(y: (minute - startMinute) * pixels)
                        }
                    }
                }.allowsHitTesting(false)
            }.frame(height: height).clipped()
                .onDrop(of: [.text], delegate: CalendarDropDelegate(state: state, day: day, hover: $hoverMinute, minuteAt: snapped))
                .onChange(of: state.dragSessionID) { _, _ in hoverMinute = nil }
        }.frame(height: height)
    }
    private func snapped(_ y: Double) -> Int { min(state.data.preferences.endHour * 60 - 15, max(Int(startMinute), Int((y / pixels / 15).rounded()) * 15 + Int(startMinute))) }
    private func date(_ minute: Int) -> Date? { state.calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day) }
}

struct CalendarDropDelegate: DropDelegate {
    let state: AppState
    let day: Date
    @Binding var hover: Int?
    let minuteAt: (Double) -> Int
    func dropUpdated(info: DropInfo) -> DropProposal? {
        hover = max(state.data.preferences.startHour * 60, minuteAt(info.location.y) - state.dragOffsetMinutes)
        return DropProposal(operation: .move)
    }
    func dropExited(info: DropInfo) { hover = nil }
    func performDrop(info: DropInfo) -> Bool {
        let minute = max(state.data.preferences.startHour * 60, minuteAt(info.location.y) - state.dragOffsetMinutes)
        hover = nil; state.endDrag()
        guard let provider = info.itemProviders(for: [.text]).first,
              let date = state.calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day) else { return false }
        _ = provider.loadObject(ofClass: String.self) { string, _ in
            guard let string, let id = UUID(uuidString: string) else { return }
            Task { @MainActor in
                guard state.item(id).map({ $0.kind == .task && !$0.deleted }) == true else { return }
                state.schedule(id, at: date)
            }
        }
        return true
    }
}

struct CalendarEvent: View {
    @Bindable var state: AppState
    let item: Item
    let width: Double
    let height: Double
    let pixelsPerMinute: Double
    @ViewState private var resizeDelta = 0.0
    @ViewState private var resizeEdge: Int?
    private var constrainedDelta: Double { CalendarResizeMath.clampedDelta(resizeDelta, top: resizeEdge == 1, duration: item.duration, pixels: pixelsPerMinute) }
    private var topDrag: Double { resizeEdge == 1 ? constrainedDelta : 0 }
    private var bottomDrag: Double { resizeEdge == 0 ? constrainedDelta : 0 }
    private var previewItem: Item {
        var preview = item
        guard resizeEdge != nil else { return preview }
        let shift = Int((constrainedDelta / pixelsPerMinute).rounded())
        if resizeEdge == 1, let start = item.schedule.date { preview.schedule = .timed(start.addingTimeInterval(Double(shift) * 60)); preview.duration = max(1, item.duration - shift) }
        else { preview.duration = max(1, item.duration + shift) }
        return preview
    }
    @ViewState private var hovered = false
    @ViewState private var pointerY = 0.0
    private var emphasized: Bool { hovered || resizeEdge != nil || state.selectedID == item.id || state.calendarEditingID == item.id }
    private var emphasizedText: Color {
        let raw = UInt64(SemanticTint.vibrantHex(state.color(item)), radix: 16) ?? 0x4F8CFF
        let rgb = [Double((raw >> 16) & 255), Double((raw >> 8) & 255), Double(raw & 255)].map { value -> Double in
            let c = value / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722 > 0.179 ? .black : .white
    }
    var body: some View {
        let item = previewItem
        VStack(alignment: .leading, spacing: 3) {
            if width < 62 && height >= 46 {
                HStack(spacing: 0) { checkbox; Spacer(minLength: 0) }
                Text(item.title).font(.system(size: 10, weight: .medium)).strikethrough(item.completed)
                    .lineLimit(max(1, Int((height - 56) / 12))).frame(maxWidth: .infinity, alignment: .leading)
                if height >= 70, let start = item.schedule.date {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(state.time(start))
                        if let end = item.end { Text("–" + state.time(end)) }
                    }.font(.system(size: 9)).lineLimit(1).minimumScaleFactor(0.8)
                }
            } else if width < 100 && height >= 46 {
                HStack(alignment: .top, spacing: 3) {
                    checkbox
                    if let start = item.schedule.date {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(state.time(start))
                            if height >= 75, let end = item.end { Text("–" + state.time(end)) }
                        }.font(.system(size: 11)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                Text(item.title).font(.system(size: 12, weight: .medium)).strikethrough(item.completed)
                    .lineLimit(max(1, Int((height - (height >= 75 ? 36 : 28)) / 14)))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: 3) {
                    checkbox
                    Text(item.title).font(.system(size: 12, weight: .medium)).strikethrough(item.completed).lineLimit(height < 65 ? 1 : 3).frame(maxWidth: .infinity, alignment: .leading)
                }
                if height > 40, let start = item.schedule.date {
                    Text(state.time(start) + "–" + (item.end.map(state.time) ?? "")).font(.system(size: 11)).lineLimit(1)
                    if height > 80 { Text(state.durationLabel(item.duration)).font(.system(size: 11)).lineLimit(1) }
                }
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, width < 62 ? 2 : 4).padding(.vertical, height < 30 ? 1 : 5)
            .frame(width: width, height: max(18, height + bottomDrag - topDrag), alignment: .topLeading)
            .foregroundStyle(emphasized ? emphasizedText : item.completed ? Color.secondary : Color.primary)
            .background(Color(hex: state.color(item)).opacity(emphasized ? 1 : item.completed ? 0.18 : 0.44), in: RoundedRectangle(cornerRadius: 4))
            .overlay { RoundedRectangle(cornerRadius: 4).stroke(Color(hex: state.color(item)).opacity(state.selectedID == item.id ? 1 : 0.6), lineWidth: 1) }
            .contentShape(Rectangle()).onTapGesture { state.selectCalendar(item.id) }
            .onDrag { state.beginDrag(item, offset: Int((pointerY / pixelsPerMinute / 15).rounded(.down)) * 15) }
            .popover(isPresented: Binding(get: { state.calendarEditingID == item.id }, set: { if !$0 { state.calendarEditingID = nil } })) {
                ItemInspector(state: state, id: item.id).frame(width: 340, height: 620)
            }
            .overlay(alignment: .bottom) { resizeHandle(top: false) }
            .overlay(alignment: .top) { resizeHandle(top: true) }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .offset(y: topDrag)
            .zIndex(resizeEdge == nil ? 0 : 20)
            .onHover { hovered = $0 }
            .onContinuousHover { phase in if case .active(let point) = phase { pointerY = point.y } }
            .help("\(item.title) · \(state.durationLabel(item.duration))\nПотяните край для изменения длительности")
            .contextMenu { ItemContextMenu(state: state, item: item) }
    }
    private var checkbox: some View {
        Button { state.complete(item.id) } label: {
            Image(systemName: item.completed ? "checkmark.circle.fill" : "circle").font(.system(size: 14)).frame(width: 16, height: 18)
        }.buttonStyle(.plain).help((item.completed ? "Вернуть в работу: " : "Выполнить: ") + item.title).accessibilityLabel((item.completed ? "Вернуть в работу: " : "Выполнить: ") + item.title)
    }
    private func resizeHandle(top: Bool) -> some View {
        CalendarResizeHandle(label: top ? "Изменить начало задачи" : "Изменить окончание задачи", step: pixelsPerMinute * 15, began: {
            state.calendarEditingID = nil; resizeEdge = top ? 1 : 0; resizeDelta = 0
        }, changed: { delta in
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { resizeDelta = delta }
        }, ended: { delta in
            let constrained = CalendarResizeMath.clampedDelta(delta, top: top, duration: item.duration, pixels: pixelsPerMinute)
            let minutes = CalendarResizeMath.snappedMinutes(constrained, pixels: pixelsPerMinute)
            state.update(item.id) { value in
                if top, let start = item.schedule.date {
                    let shift = max(item.duration - 10080, min(item.duration - min(15, item.duration), minutes))
                    value.schedule = .timed(start.addingTimeInterval(Double(shift) * 60)); value.duration = item.duration - shift
                } else { value.duration = min(10080, max(min(15, item.duration), item.duration + minutes)) }
            }
            resizeEdge = nil; resizeDelta = 0
        }).frame(height: 8)
            .accessibilityLabel(top ? "Изменить начало задачи" : "Изменить окончание задачи")
    }
}

struct PlanningQueue: View {
    @Bindable var state: AppState
    @ViewState private var receivingDrop = false
    @ViewState private var editingID: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Распределить задачи").font(.system(size: 15, weight: .semibold)); Spacer()
                Text("\(state.queue.count)").font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                IconButton(symbol: "plus", help: "Добавить задачу") { state.showQuick(nil) }
            }
            Picker("Очередь", selection: $state.queueInboxOnly) { Text("Все").tag(false); Text("Входящие").tag(true) }.pickerStyle(.segmented).labelsHidden()
            HStack(spacing: 6) {
                HStack(spacing: 5) { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("Поиск в очереди", text: $state.queueSearch).textFieldStyle(.plain) }.font(.system(size: 11)).padding(7).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                Menu {
                    Picker("Проект", selection: $state.queueProjectID) {
                        Text("Все проекты").tag(nil as UUID?)
                        ForEach(state.activeProjects.filter { $0.kind == .task }) { Text($0.name).tag(Optional($0.id)) }
                    }.disabled(state.queueInboxOnly)
                    Picker("Тег", selection: $state.queueTagID) { Text("Все теги").tag(nil as UUID?); ForEach(state.data.tags) { Text($0.name).tag(Optional($0.id)) } }
                    Picker("Приоритет", selection: $state.queuePriority) { Text("Любой приоритет").tag(nil as Int?); ForEach(0...3, id: \.self) { Text(AppState.priorityTitle($0)).tag(Optional($0)) } }
                    Picker("Дата", selection: $state.queueDateFilter) { ForEach(["Без времени", "Без даты", "С датой", "Просрочено"], id: \.self) { Text($0).tag($0) } }
                    Divider()
                    Button("Сбросить фильтры") { state.resetQueueFilters() }.disabled(!state.queueHasFilters)
                } label: { Image(systemName: state.queueHasFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle").font(.system(size: 17)).foregroundStyle(state.queueHasFilters ? Palette.accent : .secondary) }.menuStyle(.borderlessButton).fixedSize().help("Фильтры очереди")
                Menu {
                    Picker("Сортировка", selection: $state.queueSorting) { ForEach(Sorting.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                } label: { Image(systemName: "arrow.up.arrow.down").font(.system(size: 14)) }.menuStyle(.borderlessButton).fixedSize().help("Сортировка: " + state.queueSorting.rawValue)
            }
            HStack {
                Text(state.queueSorting == .manual ? "Перетащите блок на время" : "По порядку: " + state.queueSorting.rawValue.lowercased()).font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                if state.queueHasFilters { Button("Сбросить") { state.resetQueueFilters() }.buttonStyle(.plain).foregroundStyle(Palette.accent).font(.system(size: 10)) }
            }
            Divider()
            if state.queue.isEmpty { EmptyState(symbol: "tray", title: state.queueHasFilters ? "Нет совпадений" : "Всё распределено", detail: state.queueHasFilters ? "Измените или сбросьте фильтры." : "Перетащите сюда задачу из календаря, чтобы снять время. Дата сохранится.") }
            else { ScrollView { LazyVStack(spacing: 6) { ForEach(state.queue) { item in queueCard(item) } }.padding(.vertical, 2) } }
        }.padding(14).background(Palette.sidebar)
            .onChange(of: state.queueInboxOnly) { _, value in if value { state.queueProjectID = nil } }
            .overlay { RoundedRectangle(cornerRadius: 8).stroke(receivingDrop ? Palette.accent.opacity(0.8) : .clear, style: StrokeStyle(lineWidth: 2, dash: [5])).padding(3).allowsHitTesting(false) }
            .onDrop(of: [.text], isTargeted: $receivingDrop) { providers in
                guard let provider = providers.first(where: { $0.canLoadObject(ofClass: String.self) }) else { return false }
                _ = provider.loadObject(ofClass: String.self) { string, _ in
                    guard let string, let id = UUID(uuidString: string) else { return }
                    Task { @MainActor in state.returnToQueue(id) }
                }
                return true
            }
    }
    private func queueHelp(_ item: Item) -> String {
        let project = state.projectName(item.projectID)
        let priority = AppState.priorityTitle(item.priority)
        let tags: [String] = item.tagIDs.compactMap { id in
            guard let tag = state.data.tags.first(where: { $0.id == id }) else { return nil }
            return "#" + tag.name
        }
        return "\(item.title)\n\(project) · \(priority) · \(item.duration) мин\n" + tags.joined(separator: " ")
    }
    private func queueCard(_ item: Item) -> some View {
        HStack(spacing: 5) {
            CompleteButton(item: item) { state.complete(item.id) }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    if item.priority != 0 { Image(systemName: "flag.fill").font(.system(size: 9)).foregroundStyle(Color(nsColor: SemanticTint.priority(item.priority, dark: NSApp.effectiveAppearance.bestMatch(from: [.aqua,.darkAqua]) == .darkAqua))) }
                    Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                }
                HStack(spacing: 5) {
                    Circle().fill(Color(hex: state.color(item))).frame(width: 5, height: 5)
                    Text(state.projectName(item.projectID)).lineLimit(1)
                    if let date = item.schedule.date { Text(state.dayLabel(date)).lineLimit(1) }
                    if let tag = item.tagIDs.first.flatMap({ id in state.data.tags.first { $0.id == id } }) {
                        Text("#" + tag.name).foregroundStyle(Color(hex: tag.color)).lineLimit(1)
                        if item.tagIDs.count > 1 { Text("+\(item.tagIDs.count - 1)") }
                    }
                }.font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).contentShape(Rectangle())
            Text(item.duration % 60 == 0 ? "\(item.duration / 60) ч" : "\(item.duration) м").font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary).frame(width: 35)
        }.frame(height: 40).padding(.horizontal, 8).padding(.vertical, 6)
            .background(Color(hex: state.color(item)).opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).stroke(Color(hex: state.color(item)).opacity(0.30), lineWidth: 0.5) }
            .contentShape(Rectangle())
            .onTapGesture { state.selectedID = item.id; editingID = item.id }
            .onDrag { state.beginDrag(item) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Открыть: " + item.title)
            .accessibilityAction { state.selectedID = item.id; editingID = item.id }
            .focusable().focusEffectDisabled()
            .onKeyPress(.return) { state.selectedID = item.id; editingID = item.id; return .handled }
            .help(queueHelp(item))
            .popover(isPresented: Binding(get: { editingID == item.id }, set: { if !$0 { editingID = nil } })) {
                ItemInspector(state: state, id: item.id).frame(width: 340, height: 620)
            }
            .contextMenu { ItemContextMenu(state: state, item: item) }
    }
}

struct MonthGrid: View {
    @Bindable var state: AppState
    private var dates: [Date] {
        let c = state.calendar, month = c.dateInterval(of: .month, for: state.anchor)?.start ?? state.anchor
        let start = c.dateInterval(of: .weekOfYear, for: month)?.start ?? month
        return (0..<42).compactMap { c.date(byAdding: .day, value: $0, to: start) }
    }
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack { ForEach(["Пн","Вт","Ср","Чт","Пт","Сб","Вс"], id: \.self) { Text($0).font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity) } }.frame(height: 28)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                    ForEach(dates, id: \.self) { day in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(state.calendar.component(.day, from: day))").font(.system(size: 12, weight: .medium)).foregroundStyle(state.calendar.isDateInToday(day) ? Palette.accent : .secondary)
                            let items = state.calendarItems.filter { $0.schedule.date.map { state.calendar.isDate($0, inSameDayAs: day) } ?? false }
                            ForEach(items.prefix(3)) { item in
                                HStack(spacing: 1) { CompleteButton(item: item) { state.complete(item.id) }; Text(item.title).font(.system(size: 10)).strikethrough(item.completed).foregroundStyle(item.completed ? .secondary : .primary).lineLimit(1) }
                                    .background(Color(hex: state.color(item)).opacity(item.completed ? 0.18 : 0.40), in: RoundedRectangle(cornerRadius: 3))
                                    .onTapGesture { state.selectCalendar(item.id) }.onDrag { state.beginDrag(item) }
                                    .popover(isPresented: Binding(get: { state.calendarEditingID == item.id }, set: { if !$0 { state.calendarEditingID = nil } })) {
                                        ItemInspector(state: state, id: item.id).frame(width: 340, height: 620)
                                    }
                            }
                            if items.count > 3 { Button("Ещё \(items.count - 3)") { state.anchor = day; state.calendarMode = "День" }.buttonStyle(.plain).font(.system(size: 10)) }
                            Spacer(minLength: 0)
                        }.padding(6).frame(maxWidth: .infinity, alignment: .leading).frame(height: max(80, (geometry.size.height - 28) / 6)).border(Palette.line, width: 0.5)
                            .contentShape(Rectangle()).onTapGesture(count: 2) { state.showQuick(day) }
                            .dropDestination(for: String.self) { strings, _ in
                                guard let id = strings.first.flatMap(UUID.init(uuidString:)), state.item(id).map({ $0.kind == .task && !$0.deleted }) == true else { return false }
                                state.update(id) { item in
                                    if item.schedule.isTimed, let previous = item.schedule.date {
                                        let p = state.calendar.dateComponents([.hour,.minute], from: previous)
                                        item.schedule = .timed(state.calendar.date(bySettingHour: p.hour ?? 9, minute: p.minute ?? 0, second: 0, of: day) ?? day)
                                    } else { item.schedule = .day(day) }
                                }; state.endDrag(); return true
                            }
                    }
                }
            }
        }
    }
}
