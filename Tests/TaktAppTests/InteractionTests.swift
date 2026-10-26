import Foundation
import AppKit
import Testing
import TaktCore
@testable import Takt

@Test @MainActor func completionFeedbackFollowsSuccessfulCompletionOnly() throws {
    let state = AppState(demo: true)
    let item = try #require(state.data.items.first { $0.kind == .task && !$0.completed })
    var count = 0
    state.onTaskCompleted = { _ in count += 1 }
    state.complete(item.id)
    #expect(count == 1)
    state.complete(item.id) // Reopening is silent.
    #expect(count == 1)
    state.undo() // Undo/redo and other edits are silent.
    state.redo()
    #expect(count == 1)
    state.delete(item.id)
    state.complete(item.id)
    state.complete(UUID())
    #expect(count == 1)
}

@Test @MainActor func failedCompletionDoesNotPlayFeedback() throws {
    let state = AppState(demo: true)
    let index = try #require(state.data.items.firstIndex { $0.kind == .task && !$0.completed })
    let id = state.data.items[index].id
    state.data.items[index].duration = 0 // Reject the transaction during validation.
    var count = 0
    state.onTaskCompleted = { _ in count += 1 }
    state.complete(id)
    #expect(count == 0)
    #expect(!state.data.items[index].completed)
    #expect(state.errorMessage != nil)
}

@Test func feedbackPreferencesDecodeOlderDataAndPersistDisabledValues() throws {
    let legacy = try JSONEncoder().encode(Preferences())
    let decoded = try JSONDecoder().decode(Preferences.self, from: legacy)
    #expect(decoded.completionSoundEnabled ?? true)
    #expect(decoded.completionHapticsEnabled ?? true)
    var preferences = decoded
    preferences.completionSoundEnabled = false
    preferences.completionHapticsEnabled = false
    let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
    #expect(restored.completionSoundEnabled == false)
    #expect(restored.completionHapticsEnabled == false)
}

@Test @MainActor func selectingTaskReopensHiddenInspector() throws {
    let state = AppState(demo: true)
    let item = try #require(state.data.items.first)
    state.inspectorVisible = false
    state.select(item.id)
    #expect(state.inspectorVisible)
    #expect(state.selectedID == item.id)
}

@Test @MainActor func inlineCaptureUsesCurrentSmartListAndDuration() throws {
    let state = AppState(demo: true)
    state.scope = .week
    let parsed = QuickParser.parse("Из строки на 45 минут", projects: [], tags: [], calendar: state.calendar)
    let id = try #require(state.capture(parsed))
    let item = try #require(state.data.items.first { $0.id == id })
    #expect(item.duration == 45)
    #expect(item.schedule == .day(state.calendar.startOfDay(for: Date())))
    #expect(state.visibleItems.contains { $0.id == id })
}

@Test @MainActor func captureKeepsProjectAndTagContext() throws {
    let state = AppState(demo: true)
    let project = try #require(state.data.projects.first { $0.kind == .task })
    state.scope = .project(project.id)
    let id = try #require(state.capture(QuickParser.parse("Новая", projects: [], tags: [])))
    #expect(state.data.items.first { $0.id == id }?.projectID == project.id)
    let tag = try #require(state.data.tags.first)
    state.scope = .tag(tag.id)
    let tagged = try #require(state.capture(QuickParser.parse("Ещё одна", projects: [], tags: [])))
    #expect(state.data.items.first { $0.id == tagged }?.tagIDs == [tag.id])
}

@Test @MainActor func endingDragClearsGhostAndOffset() throws {
    let state = AppState(demo: true)
    let item = try #require(state.data.items.first)
    _ = state.beginDrag(item, offset: 15)
    let session = state.dragSessionID
    #expect(state.draggingID == item.id)
    state.endDrag()
    #expect(state.draggingID == nil && state.dragOffsetMinutes == 0)
    #expect(state.dragSessionID != session)
}

@Test @MainActor func completionDoesNotDuplicateNextOccurrence() throws {
    let state = AppState(demo: true)
    let item = try #require(state.data.items.first)
    state.update(item.id) { $0.recurrence = .daily }
    state.complete(item.id)
    state.complete(item.id)
    state.complete(item.id)
    #expect(state.data.items.filter { $0.repeatParentID == item.id }.count == 1)
}

@Test @MainActor func existingRowReadsEditsWithoutChangingScope() throws {
    let state = AppState(demo: true)
    let original = try #require(state.data.items.first)
    let tag = try #require(state.data.tags.first)
    state.select(original.id)
    let row = TaskRow(state: state, item: original)
    state.update(original.id) { $0.tagIDs = [tag.id]; $0.priority = 2; $0.duration = 75; $0.title = "Изменено" }
    #expect(row.item.tagIDs == [tag.id])
    #expect(row.item.priority == 2 && row.item.duration == 75 && row.item.title == "Изменено")
    #expect(state.scope == .all && state.selectedID == original.id)
    #expect(state.groups.flatMap(\.items).first { $0.id == original.id }?.tagIDs == [tag.id])
    state.undo()
    #expect(row.item.tagIDs == original.tagIDs && row.item.title == original.title)
}


@Test @MainActor func coloredTagTextRemainsReadableOnSelectedRows() throws {
    func luminance(_ rgb: [Double]) -> Double {
        let v = rgb.map { $0 <= 0.04045 ? $0/12.92 : pow(($0+0.055)/1.055, 2.4) }
        return v[0]*0.2126 + v[1]*0.7152 + v[2]*0.0722
    }
    for dark in [false, true] {
        let selected = dark ? [0.153, 0.180, 0.259] : [0.910, 0.933, 1.0]
        for hex in ProjectTagPalette.choices.map(\.hex) + ["AD94E8", "E6A467", "598BFF", "5BC9A2", "000000", "FFFFFF", "FF0000"] {
            let value = UInt64(SemanticTint.vibrantHex(hex), radix: 16)!
            let rgb = [Double((value >> 16)&255)/255, Double((value >> 8)&255)/255, Double(value&255)/255]
            let ns = try #require(SemanticTint.color(hex: hex, dark: dark).usingColorSpace(.sRGB))
            let foreground = luminance([ns.redComponent, ns.greenComponent, ns.blueComponent])
            let opacity = SemanticTint.capsuleOpacity(dark: dark)
            let background = luminance(zip(rgb, selected).map { $0 * opacity + $1 * (1 - opacity) })
            #expect((max(foreground,background)+0.05)/(min(foreground,background)+0.05) >= 4.5)
        }
    }
}

@Test @MainActor func stickyStripRestoresAtMovedPositionAndFitsScreen() {
    let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
    let expanded = NSRect(x: 180, y: 320, width: 330, height: 300)
    let strip = StickyGeometry.toggledFrame(expanded, wasCollapsed: false, expandedHeight: 300, visibleFrame: screen)
    #expect(strip.height == 36 && strip.maxY == expanded.maxY && strip.width == expanded.width)
    let moved = strip.offsetBy(dx: 260, dy: -120)
    let restored = StickyGeometry.toggledFrame(moved, wasCollapsed: true, expandedHeight: 300, visibleFrame: screen)
    #expect(restored.height == 300 && restored.maxY == moved.maxY && restored.minX == moved.minX)
    let nearBottom = NSRect(x: 1300, y: 4, width: 330, height: 36)
    let bounded = StickyGeometry.toggledFrame(nearBottom, wasCollapsed: true, expandedHeight: 460, visibleFrame: screen)
    #expect(screen.contains(bounded) && bounded.height == 460)
}

@Test @MainActor func contentUndoKeepsStickyStripLayout() throws {
    let state = AppState(demo: true)
    let note = try #require(state.data.items.first { $0.kind == .note })
    state.update(note.id) { $0.body = "Новый текст" }
    state.change(undo: false) { snapshot in
        let i = snapshot.items.firstIndex { $0.id == note.id }!
        snapshot.items[i].stickyCollapsed = true
        snapshot.items[i].stickyExpandedHeight = 420
        snapshot.items[i].stickyFrame = [280, 460, 330, 36]
    }
    state.undo()
    let undone = try #require(state.data.items.first { $0.id == note.id })
    #expect(undone.body == note.body && undone.stickyCollapsed == true)
    #expect(undone.stickyExpandedHeight == 420 && undone.stickyFrame == [280, 460, 330, 36])
    state.redo()
    let redone = try #require(state.data.items.first { $0.id == note.id })
    #expect(redone.body == "Новый текст" && redone.stickyCollapsed == true)
}

@Test @MainActor func commandEnterAppliesBeforeCreating() {
    let project = Project(name: "Работа"), tag = Tag(name: "идеи")
    for raw in ["Задача !", "Задача /", "Задача #"] {
        let parsed = QuickParser.parse(raw, projects: [project], tags: [tag])
        #expect(CaptureBehavior.submitAction(text: raw, parsed: parsed, suggestionCount: 1) == .applySuggestion)
    }
    for raw in ["Задача !2", "Задача /Работа", "Задача #идеи"] {
        let parsed = QuickParser.parse(raw, projects: [project], tags: [tag])
        #expect(CaptureBehavior.submitAction(text: raw, parsed: parsed, suggestionCount: 0) == .finishToken)
        #expect(CaptureBehavior.submitAction(text: raw + " ", parsed: parsed, suggestionCount: 0) == .create)
    }
    #expect(CaptureBehavior.submitAction(text: "Задача /", parsed: QuickParser.parse("Задача /", projects: [], tags: []), suggestionCount: 0) == .stay)
}

@Test @MainActor func deleteTagUnlinksOnlyThatTagAndUndoRestoresIt() throws {
    let state = AppState(demo: true)
    let parent = try #require(state.data.tags.first)
    let child = Tag(name: "Дочерний", parentID: parent.id)
    state.change { $0.tags.append(child); $0.items[0].tagIDs = [parent.id, child.id] }
    state.scope = .tag(parent.id)
    state.deleteTag(parent.id)
    #expect(!state.data.tags.contains { $0.id == parent.id })
    #expect(state.data.tags.first { $0.id == child.id }?.parentID == nil)
    #expect(state.data.items[0].tagIDs == [child.id] && state.scope == .all)
    _ = try state.data.validated()
    state.undo()
    #expect(state.data.tags.contains { $0.id == parent.id })
    #expect(state.data.items[0].tagIDs == [parent.id, child.id])
}

@Test @MainActor func projectOrderAndTaskTrashAreUndoable() throws {
    let state = AppState(demo: true)
    let first = state.data.projects[0], last = try #require(state.data.projects.last)
    state.moveProject(last.id, before: first.id)
    #expect(state.activeProjects.first?.id == last.id)
    let encoded = try JSONEncoder().encode(state.data)
    #expect(try JSONDecoder().decode(Snapshot.self, from: encoded).projects.first?.id == last.id)
    state.undo()
    #expect(state.data.projects.first?.id == first.id)
    let item = try #require(state.data.items.first)
    state.delete(item.id)
    #expect(!state.visibleItems.contains { $0.id == item.id })
    state.scope = .trash
    #expect(state.visibleItems.contains { $0.id == item.id })
    state.undo()
    #expect(state.data.items.first { $0.id == item.id }?.deleted == false)
}

@Test @MainActor func resizeTracksContinuouslyAndSwipeFiresOnce() {
    #expect(CalendarResizeMath.clampedDelta(17.5, top: false, duration: 60, pixels: 1.6) == 17.5)
    #expect(CalendarResizeMath.snappedMinutes(17.5, pixels: 1.6) == 15)
    #expect(CalendarResizeMath.clampedDelta(200, top: true, duration: 60, pixels: 1.6) == 72)
    var swipe = CalendarSwipeAccumulator()
    #expect(swipe.feed(dx: -30, dy: 1) == nil)
    #expect(swipe.feed(dx: -40, dy: 2) == nil)
    #expect(swipe.feed(dx: -100, dy: 0) == 1)
    swipe.reset()
    #expect(swipe.feed(dx: 160, dy: 0) == -1)
    swipe.reset()
    #expect(swipe.feed(dx: 2, dy: 90) == nil && !swipe.consumesHorizontal)
}

@Test @MainActor func timeZoneChangePreservesAllDayDatesAndTimedInstants() throws {
    let state = AppState(demo: true)
    let old = state.calendar
    let date = old.date(from: DateComponents(year: 2026, month: 10, day: 27))!
    var allDay = Item(title: "Дата"); allDay.schedule = .day(date)
    var timed = Item(title: "Время"); timed.schedule = .timed(date.addingTimeInterval(14*3600))
    state.change { $0.items = [allDay, timed] }
    state.setTimeZone("America/New_York")
    let day = try #require(state.data.items[0].schedule.date)
    #expect(state.calendar.component(.day, from: day) == 27 && state.calendar.component(.hour, from: day) == 0)
    #expect(state.data.items[1].schedule == timed.schedule)
}

@Test @MainActor func todayIncludesOverdueAndPostponesAsSingleUndoableChange() throws {
    let state = AppState(demo: true)
    state.scope = .today
    let overdue = try #require(state.overdueTasks.first)
    let original = overdue.schedule
    #expect(state.visibleItems.contains { $0.id == overdue.id })
    for grouping in Grouping.allCases {
        state.grouping = grouping
        #expect(state.groups.first?.id == "Просрочено")
    }
    let count = state.taskCount(in: .today)
    state.search = "несуществующий запрос"
    #expect(state.taskCount(in: .today) == count)
    state.search = ""
    state.postponeOverdueToToday()
    #expect(state.overdueTasks.isEmpty)
    let moved = try #require(state.data.items.first { $0.id == overdue.id })
    #expect(moved.schedule.date.map { state.calendar.isDateInToday($0) } == true)
    if let before = original.date, let after = moved.schedule.date, original.isTimed {
        #expect(state.calendar.component(.hour, from: before) == state.calendar.component(.hour, from: after))
    }
    state.undo()
    #expect(state.data.items.first { $0.id == overdue.id }?.schedule == original)
}

@Test @MainActor func queueFilteringSortingAndCountsStayIndependentOfMainSearch() throws {
    let state = AppState(demo: true)
    state.area = .calendar
    let original = state.queue
    #expect(!original.isEmpty)
    state.search = "нет совпадений"
    #expect(state.queue.count == original.count)
    state.queueSorting = .duration
    #expect(state.queue.map(\.duration) == original.map(\.duration).sorted())
    state.queueProjectID = try #require(original.first?.projectID)
    #expect(state.queue.allSatisfy { $0.projectID == state.queueProjectID })
    state.queuePriority = 1
    #expect(state.queue.allSatisfy { $0.priority == 1 })
    state.resetQueueFilters()
    #expect(!state.queueHasFilters)
    state.queueDateFilter = "Без даты"
    #expect(state.queue.allSatisfy { $0.schedule.date == nil })
    state.resetQueueFilters()
    state.queueInboxOnly = true
    #expect(state.queue.allSatisfy { $0.projectID == nil })
    let tag = try #require(state.data.tags.first)
    let id = try #require(original.first?.id)
    state.update(id) { $0.tagIDs = [tag.id] }
    #expect(state.taskCount(in: .tag(tag.id)) >= 1)
}

@Test @MainActor func hashtagsApplyInTaskTitlesNotesAndDescriptionsWithoutDuplicatingTags() throws {
    let state = AppState(demo: true)
    let id = try #require(state.data.items.first?.id)
    let tag = try #require(state.data.tags.first)
    state.update(id) { $0.body = "Описание #\(tag.name) и ссылка https://example.com/#fragment" }
    #expect(state.data.items.first { $0.id == id }?.tagIDs.contains(tag.id) == true)
    state.update(id) { $0.title = "Имя #новыйтег " }
    let new = try #require(state.data.tags.first { $0.name == "новыйтег" })
    #expect(state.data.items.first { $0.id == id }?.tagIDs.contains(new.id) == true)
    state.update(id) { $0.body += " ещё #новыйтег " }
    #expect(state.data.tags.filter { $0.name == "новыйтег" }.count == 1)
    #expect(state.data.items.first { $0.id == id }?.tagIDs.filter { $0 == new.id }.count == 1)
    #expect(Hashtags.names(in: "## Заголовок\n# Заголовок\nhttps://example.com/#fragment").isEmpty)
}

@Test func markdownSupportsBlocksAndSafeClickableLinks() {
    let markdown = "# Заголовок\n**Жирный** ~~старый~~\n- [x] Готово\n> Цитата\n```swift\nlet x = 1 < 2\n```\n| А | Б |\n| --- | --- |\n| 1 | 2 |\nhttps://example.com\n[Письмо](mailto:test@example.com)\n<script>alert(1)</script>"
    let html = MarkdownHTML.body(markdown)
    #expect(html.contains("<h1>Заголовок</h1>"))
    #expect(html.contains("<strong>Жирный</strong>"))
    #expect(html.contains("<del>старый</del>"))
    #expect(html.contains("<table>"))
    #expect(html.contains("<blockquote>"))
    #expect(html.contains("let x = 1 &lt; 2"))
    #expect(html.contains("href=\"https://example.com\""))
    #expect(!html.contains("<script>"))
    #expect(MarkdownHTML.safeURL("javascript:alert(1)") == nil)
    #expect(!MarkdownHTML.inline("[опасно](javascript:alert)").contains("href="))
}

@Test func customRecurrencePersistsAndAdvancesCalendarDays() throws {
    let calendar = Dates.calendar(zone: "Europe/Moscow")
    var item = Item(title: "Через три дня")
    let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 14, minute: 45)))
    item.schedule = .timed(date); item.recurrence = .intervalDays; item.repeatEveryDays = 3
    let decoded = try JSONDecoder().decode(Item.self, from: JSONEncoder().encode(item))
    let next = try #require(Dates.nextOccurrence(decoded, calendar: calendar))
    #expect(next.schedule.date == calendar.date(byAdding: .day, value: 3, to: date))
    #expect(next.repeatEveryDays == 3 && next.recurrence == .intervalDays)
    item.repeatEveryDays = 0
    var snapshot = Snapshot(); snapshot.items = [item]
    #expect(throws: (any Error).self) { try snapshot.validated() }
}

@Test @MainActor func hashtagCompletionUsesCaretAndUTF16RangesInEveryEditor() {
    let view = TagTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
    view.tags = [Tag(name: "работа"), Tag(name: "рабочие заметки"), Tag(name: "дом")]
    view.string = "📝 План #раб и дальнейший текст"
    let prefix = "📝 План #раб"
    view.setSelectedRange(NSRange(location: (prefix as NSString).length, length: 0))
    let range = view.rangeForUserCompletion
    #expect((view.string as NSString).substring(with: range) == "#раб")
    var index = 0
    #expect(view.completions(forPartialWordRange: range, indexOfSelectedItem: &index) == ["#работа", "#\"рабочие заметки\""])
    view.string = "## Заголовок"
    view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
    #expect(view.rangeForUserCompletion.location == NSNotFound)
    #expect(Hashtags.names(in: "`#код` и ```\n#не_тег\n```\n#тег ") == ["тег"])
}

@Test func quotedHashtagsAndPunctuationWorkInSmartCapture() {
    let tag = Tag(name: "мои идеи")
    let plain = Tag(name: "работа")
    let parsed = QuickParser.parse("Задача (#работа), затем #\"мои идеи\" завтра", projects: [], tags: [tag, plain])
    #expect(Set(parsed.tagIDs) == Set([tag.id, plain.id]))
    #expect(!parsed.title.contains("#"))
}

@Test @MainActor func hashtagsFilterSearchAcrossNotesListsAndQueue() throws {
    let state = AppState(demo: true)
    let tag = try #require(state.data.tags.first)
    let id = try #require(state.data.items.first { $0.kind == .task }?.id)
    state.update(id) { $0.tagIDs = [tag.id]; $0.schedule = .unscheduled }
    state.search = "#" + tag.name
    #expect(state.visibleItems.contains { $0.id == id })
    #expect(state.visibleItems.allSatisfy { $0.tagIDs.contains(tag.id) })
    state.queueSearch = state.search
    #expect(state.queue.contains { $0.id == id })
    var note = Item(title: "Заметка без тега в тексте", kind: .note); note.tagIDs = [tag.id]
    #expect(state.matchesQuery(note, "#" + tag.name))
    #expect(state.matchesQuery(note, "#"))
    #expect(!state.matchesQuery(note, "#несуществующий"))
}
