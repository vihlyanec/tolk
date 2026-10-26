import AppKit
import SwiftUI
import TaktCore
import UserNotifications
import WebKit
import CoreServices

final class KeyPanel: NSPanel {
    var escape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { escape?() }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate, NSMenuItemValidation {
    let state = AppState(demo: ProcessInfo.processInfo.arguments.contains("--demo") || ProcessInfo.processInfo.arguments.contains("--render") || Bundle.main.bundleIdentifier == "local.takt.demo")
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var quickPanel: KeyPanel?
    private var stickies: [UUID: NSPanel] = [:]
    private var statusItem: NSStatusItem?
    private var keys: HotKeys?
    private let reminders = Reminders()
    private let completionFeedback = CompletionFeedback()
    private var previousApplication: NSRunningApplication?
    private var lastShift: Bool?
    private var reminderTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.arguments.contains("--render") { renderPreviews(); return }
        // Register the actual bundle so notification banners resolve its .icns icon,
        // rather than relying only on the runtime Dock image.
        LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
        if let url = Bundle.main.url(forResource: "BrandIcon", withExtension: "png"), let icon = NSImage(contentsOf: url) { NSApp.applicationIconImage = icon }
        if !state.isDemo { state.appUpdater = AppUpdater() }
        makeMenu()
        state.showQuick = { [weak self] date in self?.openQuick(date: date) }
        state.showRangeQuick = { [weak self] date, duration in self?.openQuick(date: date, duration: duration) }
        state.showSticky = { [weak self] id in self?.openSticky(id: id) }
        state.showSettings = { [weak self] in self?.openSettings() }
        reminders.reportError = { [weak self] text in self?.state.errorMessage = text }
        state.didSave = { [weak self] in self?.refreshServices() }
        state.onTaskCompleted = { [weak self] preferences in self?.completionFeedback.play(preferences) }
        keys = HotKeys { [weak self] id in if id == 1 { self?.openQuick(date: nil) } else { self?.openSticky(id: nil) } }
        refreshServices()
        if !state.isDemo {
            reminderTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { if let self { self.reminders.sync(self.state.data) } }
            }
        }
        UNUserNotificationCenter.current().delegate = self
        showMain()
        for item in state.data.items where item.stickyOpen && !item.deleted { openSticky(id: item.id) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showMain(); return true }
    func applicationWillTerminate(_ notification: Notification) { keys?.stop(); reminderTimer?.invalidate() }
    private func makeMenu() {
        let bar = NSMenu()
        let app = NSMenu(); let appItem = NSMenuItem(); appItem.submenu = app; bar.addItem(appItem)
        add("О Толке", to: app, action: #selector(aboutAction))
        add("Проверить обновления…", to: app, action: #selector(checkUpdatesAction))
        add("Настройки…", to: app, action: #selector(settingsAction), key: ",")
        app.addItem(.separator()); add("Завершить Толк", to: app, action: #selector(quitAction), key: "q")
        let file = NSMenu(); let fileItem = NSMenuItem(title: "Файл", action: nil, keyEquivalent: ""); fileItem.submenu = file; bar.addItem(fileItem)
        add("Новая задача", to: file, action: #selector(quickAction), key: "n")
        add("Новая заметка", to: file, action: #selector(noteAction), key: "d")
        add("Главное окно", to: file, action: #selector(mainAction), key: "0")
        let edit = NSMenu(); let editItem = NSMenuItem(title: "Правка", action: nil, keyEquivalent: ""); editItem.submenu = edit; bar.addItem(editItem)
        add("Отменить изменение записи", to: edit, action: #selector(undoAction), key: "z")
        let redo = add("Повторить изменение записи", to: edit, action: #selector(redoAction), key: "z"); redo.keyEquivalentModifierMask = [.command,.shift]
        edit.addItem(.separator())
        for (title, selector, key) in [("Вырезать", #selector(NSText.cut(_:)), "x"), ("Копировать", #selector(NSText.copy(_:)), "c"), ("Вставить", #selector(NSText.paste(_:)), "v"), ("Выделить всё", #selector(NSText.selectAll(_:)), "a")] { edit.addItem(withTitle: title, action: selector, keyEquivalent: key) }
        NSApp.mainMenu = bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "checkmark.square", accessibilityDescription: "Толк")
        let statusMenu = NSMenu()
        add("Открыть Толк", to: statusMenu, action: #selector(mainAction))
        add("Добавить задачу", to: statusMenu, action: #selector(quickAction))
        add("Новая заметка", to: statusMenu, action: #selector(noteAction))
        statusMenu.addItem(.separator()); add("Настройки…", to: statusMenu, action: #selector(settingsAction))
        statusMenu.addItem(.separator()); add("Завершить Толк", to: statusMenu, action: #selector(quitAction))
        statusItem?.menu = statusMenu
    }
    @discardableResult private func add(_ title: String, to menu: NSMenu, action: Selector, key: String = "") -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key); item.target = self; return item
    }
    private func refreshServices() {
        if lastShift != state.data.preferences.shiftedShortcuts {
            lastShift = state.data.preferences.shiftedShortcuts; keys?.register(shifted: state.data.preferences.shiftedShortcuts)
        }
        for (id, window) in stickies {
            guard let item = state.data.items.first(where: { $0.id == id && !$0.deleted }) else { window.orderOut(nil); continue }
            window.level = item.stickyPinned ? .floating : .normal
            if !item.stickyOpen { window.orderOut(nil) }
        }
        if !state.isDemo { reminders.sync(state.data) }
    }
    private func host<V: View>(_ view: V) -> NSHostingView<V> { NSHostingView(rootView: view) }
    func showMain() {
        if mainWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 880), styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
            window.title = ProcessInfo.processInfo.arguments.contains("--demo") || Bundle.main.bundleIdentifier == "local.takt.demo" ? "Толк — демонстрация, данные не сохраняются" : "Толк"
            window.contentMinSize = NSSize(width: 1080, height: 640)
            window.contentView = host(MainView(state: state)); window.center(); window.delegate = self
            window.isReleasedWhenClosed = false; window.setFrameAutosaveName("TaktMain"); mainWindow = window
        }
        mainWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private func activeScreen() -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
    }
    private func bounded(_ origin: NSPoint, size: NSSize, screen: NSScreen) -> NSRect {
        let r = screen.visibleFrame
        return NSRect(x: max(r.minX, min(origin.x, r.maxX - size.width)), y: max(r.minY, min(origin.y, r.maxY - size.height)), width: min(size.width, r.width), height: min(size.height, r.height))
    }
    func openQuick(date: Date?, duration: Int? = nil) {
        if let quickPanel, quickPanel.isVisible { quickPanel.orderOut(nil); return }
        guard let screen = activeScreen() else { return }
        previousApplication = NSWorkspace.shared.frontmostApplication
        let panel = KeyPanel(contentRect: .zero, styleMask: [.borderless,.nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Быстрая задача · Толк"; panel.isReleasedWhenClosed = false; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.contentView = host(QuickCaptureView(state: state, initialDate: date, initialDuration: duration, heightChanged: { [weak self, weak panel] height in
            guard let self, let panel else { return }
            let frame = self.bounded(NSPoint(x: panel.frame.minX, y: panel.frame.maxY - height), size: NSSize(width: 640, height: height), screen: screen)
            panel.setFrame(frame, display: true)
        }) { [weak self] in self?.closeQuick() })
        let size = NSSize(width: 640, height: 62)
        panel.setFrame(bounded(NSPoint(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.midY - size.height / 2 + 100), size: size, screen: screen), display: true)
        panel.escape = { [weak self] in
            self?.state.change(undo: false) { $0.preferences.quickDraft = ""; $0.preferences.quickDraftLiterals = nil; $0.preferences.quickDraftBody = nil; $0.preferences.quickDraftDescriptionExpanded = nil }
            self?.closeQuick()
        }; panel.delegate = self
        quickPanel = panel; panel.orderFrontRegardless(); panel.makeKey()
    }
    private func closeQuick() {
        quickPanel?.orderOut(nil)
        if let previousApplication, previousApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApplication.activate() }
    }
    func openSticky(id: UUID?) {
        let itemID: UUID
        if let id { itemID = id } else {
            let project = state.data.projects.first { $0.kind == .note && !$0.archived }
            var item = Item(title: "Новая заметка", kind: .note, projectID: project?.id); item.stickyOpen = true
            state.add(item); itemID = item.id
        }
        guard let item = state.item(itemID), !item.deleted, let screen = activeScreen() else { return }
        if !state.data.items.contains(where: { $0.id == itemID }) { state.update(itemID) { $0.stickyOpen = true } }
        if let window = stickies[itemID] {
            state.update(itemID) { $0.stickyOpen = true }; window.orderFrontRegardless(); window.makeKey()
            if let editor = findEditor(in: window.contentView) { window.makeFirstResponder(editor) }; return
        }
        let panel = KeyPanel(contentRect: .zero, styleMask: [.borderless,.resizable,.nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Стикер · Толк"; panel.isReleasedWhenClosed = false; panel.level = item.stickyPinned ? .floating : .normal
        let collapsed = item.stickyCollapsed == true
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
        panel.contentMinSize = NSSize(width: 240, height: collapsed ? StickyGeometry.collapsedHeight : 220)
        if collapsed { panel.styleMask.remove(.resizable) }
        panel.contentView = host(StickyView(state: state, id: itemID, close: { [weak self] in self?.hideSticky(itemID) }, toggleCollapsed: { [weak self] in self?.toggleSticky(itemID) }))
        let saved = item.stickyFrame
        let size = NSSize(width: max(240, saved.flatMap { $0.count == 4 ? $0[2] : nil } ?? 330), height: collapsed ? StickyGeometry.collapsedHeight : max(220, saved.flatMap { $0.count == 4 ? $0[3] : nil } ?? 300))
        let origin = NSPoint(x: saved.flatMap { $0.count == 4 ? $0[0] : nil } ?? NSEvent.mouseLocation.x + 18, y: saved.flatMap { $0.count == 4 ? $0[1] : nil } ?? NSEvent.mouseLocation.y - size.height)
        let savedScreen = NSScreen.screens.first { $0.visibleFrame.contains(origin) } ?? screen
        panel.setFrame(bounded(origin, size: size, screen: savedScreen), display: true)
        panel.escape = { [weak self] in self?.hideSticky(itemID) }; panel.delegate = self
        stickies[itemID] = panel; state.update(itemID) { $0.stickyOpen = true }
        panel.orderFrontRegardless(); panel.makeKey()
        panel.contentView?.layoutSubtreeIfNeeded()
        if let editor = findEditor(in: panel.contentView) { panel.makeFirstResponder(editor) }
    }
    private func toggleSticky(_ id: UUID) {
        guard let window = stickies[id], let item = state.data.items.first(where: { $0.id == id && !$0.deleted }),
              let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(window.frame) }) ?? activeScreen() else { return }
        let wasCollapsed = item.stickyCollapsed == true
        let expandedHeight = wasCollapsed ? item.stickyExpandedHeight ?? 300 : window.frame.height
        let frame = StickyGeometry.toggledFrame(window.frame, wasCollapsed: wasCollapsed, expandedHeight: expandedHeight, visibleFrame: screen.visibleFrame)
        state.change(undo: false) { snapshot in
            if let index = snapshot.items.firstIndex(where: { $0.id == id }) {
                snapshot.items[index].stickyCollapsed = !wasCollapsed
                snapshot.items[index].stickyExpandedHeight = expandedHeight
            }
        }
        guard state.data.items.first(where: { $0.id == id })?.stickyCollapsed == !wasCollapsed else { return }
        window.contentMinSize = NSSize(width: 240, height: wasCollapsed ? 220 : StickyGeometry.collapsedHeight)
        if wasCollapsed { window.styleMask.insert(.resizable) } else { window.styleMask.remove(.resizable) }
        window.setFrame(frame, display: true)
        if wasCollapsed {
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else { return }
                window.contentView?.layoutSubtreeIfNeeded()
                if let editor = self.findEditor(in: window.contentView) { window.makeFirstResponder(editor) }
            }
        }
    }
    private func hideSticky(_ id: UUID) { stickies[id]?.orderOut(nil); state.update(id) { $0.stickyOpen = false } }
    private func findEditor(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let editor = view as? TagTextView, editor.isTitleField { return nil }
        if let editor = view as? NSTextView { return editor }
        for child in view.subviews { if let found = findEditor(in: child) { return found } }
        return nil
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === mainWindow || sender === settingsWindow { sender.orderOut(nil); return false }
        if sender === quickPanel { closeQuick(); return false }
        if let id = stickies.first(where: { $0.value === sender })?.key { hideSticky(id); return false }
        return true
    }
    func windowDidMove(_ notification: Notification) { saveStickyFrame(notification.object as? NSWindow) }
    func windowDidResize(_ notification: Notification) { saveStickyFrame(notification.object as? NSWindow) }
    private func saveStickyFrame(_ window: NSWindow?) {
        guard let window, let id = stickies.first(where: { $0.value === window })?.key else { return }
        let r = window.frame
        state.change(undo: false) { s in if let i = s.items.firstIndex(where: { $0.id == id }) { s.items[i].stickyFrame = [r.minX,r.minY,r.width,r.height]; if s.items[i].stickyCollapsed != true { s.items[i].stickyExpandedHeight = r.height } } }
    }
    private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 690), styleMask: [.titled,.closable], backing: .buffered, defer: false)
            window.title = "Настройки · Толк"; window.isReleasedWhenClosed = false; window.delegate = self
            window.contentView = host(SettingsView(state: state) { [weak self] in self?.keys?.summary ?? "" }); window.center(); settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner,.sound] }
    @objc private func mainAction() { showMain() }
    @objc private func quickAction() { openQuick(date: nil) }
    @objc private func noteAction() { openSticky(id: nil) }
    @objc private func settingsAction() { openSettings() }
    @objc private func quitAction() { NSApp.terminate(nil) }
    @objc private func undoAction() { state.undo() }
    @objc private func redoAction() { state.redo() }
    @objc private func checkUpdatesAction() {
        if state.appUpdater?.configured == true { state.appUpdater?.check() }
        else {
            let alert = NSAlert(); alert.messageText = "Обновления ещё не настроены"
            alert.informativeText = "В этой локальной сборке пока не подключён канал выпусков. После подключения GitHub здесь можно будет проверять новые версии."
            alert.addButton(withTitle: "Понятно"); alert.runModal()
        }
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkUpdatesAction) {
            return state.appUpdater?.configured != true || state.appUpdater?.canCheck == true
        }
        return true
    }
    @objc private func aboutAction() { NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Толк", .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.5", .credits: NSAttributedString(string: "Личный локальный менеджер задач")]) }

    private func renderPreviews() {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TAKT_RENDER_DIR"] ?? FileManager.default.currentDirectoryPath + "/build/previews")
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { FileHandle.standardError.write(Data(error.localizedDescription.utf8)); NSApp.terminate(nil); return }
        state.anchor = Date(); state.area = .calendar
        func render<V: View>(_ view: V, name: String, width: CGFloat, height: CGFloat, scheme: ColorScheme = .dark) {
            let root = NSHostingView(rootView: view.frame(width: width, height: height).environment(\.colorScheme, scheme))
            let frame = NSRect(x: 0, y: 0, width: width, height: height)
            let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            window.contentView = root; root.frame = frame
            root.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(name == "notes" ? 1.0 : 0.2))
            root.layoutSubtreeIfNeeded()
            if let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
                root.cacheDisplay(in: root.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
                do { try png.write(to: directory.appendingPathComponent(name + ".png")) } catch { FileHandle.standardError.write(Data(error.localizedDescription.utf8)) }
            }
        }
        let beforeCalendar = state.data
        if let source = state.data.items.first(where: { $0.schedule.isTimed }) {
            state.update(source.id) { $0.recurrence = .weekly }
            if let other = state.data.items.first(where: { $0.schedule.isTimed && $0.id != source.id }) { state.complete(other.id) }
            render(MainView(state: state), name: "calendar-completed", width: 1440, height: 880)
            state.anchor = state.calendar.date(byAdding: .day, value: 7, to: state.anchor) ?? state.anchor
            render(MainView(state: state), name: "calendar-recurring", width: 1440, height: 880)
        }
        state.change(undo: false) { $0 = beforeCalendar }; state.anchor = Date()
        let beforeSidebar = state.data
        state.area = .tasks
        state.change(undo: false) { snapshot in
            if !snapshot.projects.isEmpty { snapshot.projects[0].name = "📁 Проекты" }
            if snapshot.projects.count > 1 { snapshot.projects[1].name = "👤 Личное" }
            snapshot.projects.append(Project(name: "⏳ Когда-нибудь", color: "4F8CFF"))
        }
        render(Sidebar(state: state).font(.system(size: 13)), name: "sidebar-narrow", width: 252, height: 880)
        render(Sidebar(state: state).font(.system(size: 13)), name: "sidebar-narrow-light", width: 252, height: 880, scheme: .light)
        render(CreationSheet(state: state, kind: .project(nil)), name: "color-palette", width: 390, height: 460)
        render(CreationSheet(state: state, kind: .tag(nil)), name: "color-palette-light", width: 390, height: 420, scheme: .light)
        state.change(undo: false) { $0 = beforeSidebar }; state.area = .calendar
        render(MainView(state: state), name: "calendar", width: 1440, height: 880)
        let beforeResponsive = state.data
        if let project = state.activeProjects.first(where: { $0.kind == .task }), let week = state.calendar.dateInterval(of: .weekOfYear, for: state.anchor)?.start {
            state.change(undo: false) { snapshot in
                for offset in 0..<7 {
                    var item = Item(title: "Задача дня \(offset + 1)", projectID: project.id)
                    if let day = state.calendar.date(byAdding: .day, value: offset, to: week), let date = state.calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day) { item.schedule = .timed(date) }
                    item.duration = 60; snapshot.items.append(item)
                }
            }
            render(MainView(state: state), name: "calendar-compact", width: 1080, height: 700)
            render(MainView(state: state), name: "calendar-medium", width: 1280, height: 800)
            render(MainView(state: state), name: "calendar-wide", width: 1680, height: 950)
        }
        state.change(undo: false) { $0 = beforeResponsive }

        if let event = state.data.items.first(where: { $0.kind == .task && $0.schedule.isTimed }) {
            let before = state.data
            state.change(undo: false) { snapshot in
                if let index = snapshot.projects.firstIndex(where: { $0.id == event.projectID }) { snapshot.projects[index].color = "FFAD40" }
            }
            state.selectedID = nil
            render(CalendarEvent(state: state, item: event, width: 200, height: 110, pixelsPerMinute: 1.6).background(Palette.canvas), name: "event-idle", width: 200, height: 110)
            state.selectedID = event.id
            render(CalendarEvent(state: state, item: event, width: 200, height: 110, pixelsPerMinute: 1.6).background(Palette.canvas), name: "event-selected", width: 200, height: 110)
            state.selectedID = nil; state.change(undo: false) { $0 = before }
        }
        if let id = state.queue.first?.id {
            let before = state.data
            state.update(id) { item in
                item.title = "Длинное название задачи с большим количеством дополнительной информации"
                item.body = "Описание, которое не должно увеличивать высоту карточки в очереди"
                item.tagIDs = state.data.tags.map(\.id); item.priority = 1
            }
            render(PlanningQueue(state: state), name: "queue-compact", width: 310, height: 600)
            state.change(undo: false) { $0 = before }
        }
        render(TaskDatePopover(schedule: .constant(.timed(Date())), calendar: state.calendar, dismiss: {}), name: "date-popover", width: 300, height: 470)
        state.area = .tasks; state.scope = .today; state.selectedID = nil
        render(MainView(state: state), name: "today-overdue", width: 1280, height: 800)
        state.scope = .all
        state.area = .tasks; state.selectedID = state.data.items.first { $0.title == "Подготовить отчёт" }?.id
        if let id = state.selectedID {
            let tags = state.data.tags.map(\.id)
            state.update(id) { item in
                item.tagIDs = tags; item.priority = 1; item.body = "Сверить цифры и подготовить выводы для команды."
                item.checklist = [CheckItem(title: "Собрать данные"), CheckItem(title: "Проверить выводы")]
                item.recurrence = .weekly; item.reminderMinutes = 15
            }
        }
        render(MainView(state: state), name: "list", width: 1440, height: 880)
        render(MainView(state: state), name: "compact-list", width: 1080, height: 700)
        if let id = state.selectedID {
            render(ItemInspector(state: state, id: id), name: "inspector-timed", width: 285, height: 620)
            let before = state.data
            state.update(id) { item in
                item.title = "Подготовить материалы"; item.projectID = nil; item.section = "Без раздела"
                item.schedule = .day(state.calendar.startOfDay(for: Date())); item.duration = 30
                item.recurrence = .none; item.tagIDs = []; item.body = ""; item.checklist = []
                item.allDayReminders = [AllDayReminder()]
            }
            render(ItemInspector(state: state, id: id), name: "inspector-all-day", width: 285, height: 520)
            state.change(undo: false) { $0 = before }
        }
        state.change(undo: false) { $0.preferences.quickDraft = "Подготовить отчёт сегодня в 16:30 на 45 минут важно #идеи /Работа " }
        render(QuickCaptureView(state: state, dismiss: {}), name: "capture", width: 640, height: 62)
        state.change(undo: false) { $0.preferences.quickDraftBody = "Сверить цифры с командой.\nДобавить выводы и ссылку на материалы."; $0.preferences.quickDraftDescriptionExpanded = true }
        render(QuickCaptureView(state: state, dismiss: {}), name: "capture-description", width: 640, height: 215)
        state.change(undo: false) { $0.preferences.quickDraftBody = nil; $0.preferences.quickDraftDescriptionExpanded = nil }

        state.change(undo: false) { $0.preferences.theme = "light" }
        render(QuickCaptureView(state: state, dismiss: {}), name: "capture-light", width: 640, height: 62, scheme: .light)
        render(MainView(state: state), name: "list-light", width: 1440, height: 880, scheme: .light)
        state.change(undo: false) { $0.preferences.theme = "dark" }
        if let note = state.data.items.first(where: { $0.kind == .note }) {
            state.area = .notes; state.selectedID = note.id
            render(MainView(state: state), name: "notes", width: 1440, height: 880)
            render(MainView(state: state), name: "compact-notes", width: 1080, height: 700)
            state.change(undo: false) { $0.preferences.theme = "light" }
            render(MainView(state: state), name: "notes-light", width: 1440, height: 880, scheme: .light)
            state.change(undo: false) { $0.preferences.theme = "dark" }
            state.change(undo: false) { snapshot in
                snapshot.preferences.defaultTimedReminderOffsets = [10, 60]
                snapshot.preferences.defaultAllDayReminders = [AllDayReminder(), AllDayReminder(daysBefore: 1, minuteOfDay: 1080)]
            }
            render(SettingsView(state: state, shortcutStatus: { "Control-Q — задача\nControl-D — заметка" }), name: "settings", width: 580, height: 690)
            render(StickyView(state: state, id: note.id, close: {}), name: "sticky", width: 330, height: 300)
            state.update(note.id) { $0.stickyCollapsed = true; $0.stickyExpandedHeight = 300 }
            render(StickyView(state: state, id: note.id, close: {}), name: "sticky-collapsed", width: 330, height: StickyGeometry.collapsedHeight)
        }
        let markdown = "# План проекта\n\n**Жирный**, *курсив*, ~~зачёркнутый~~ и `код`.\n\n- [x] Подготовить материалы\n- [ ] Проверить результат\n\n> Хороший план оставляет место для изменений.\n\n| Задача | Статус |\n| --- | --- |\n| Дизайн | Готово |\n| Проверка | В работе |\n\n```swift\nlet done = true\n```\n\n[Ссылка](https://example.com) и https://example.com"
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 700, height: 820), configuration: configuration)
        let webWindow = NSWindow(contentRect: web.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        webWindow.appearance = NSAppearance(named: .darkAqua); webWindow.contentView = web
        web.loadHTMLString(MarkdownHTML.document(markdown, dark: true), baseURL: nil)
        let deadline = Date().addingTimeInterval(8)
        while web.isLoading && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        var snapshotFinished = false
        web.takeSnapshot(with: nil) { image, error in
            if let image, let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) {
                try? png.write(to: directory.appendingPathComponent("markdown-extended.png"))
            }
            if let error { FileHandle.standardError.write(Data(error.localizedDescription.utf8)) }
            snapshotFinished = true
        }
        let snapshotDeadline = Date().addingTimeInterval(5)
        while !snapshotFinished && Date() < snapshotDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        NSApp.terminate(nil)
    }
}

@main struct TaktApplication {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
