import AppKit
import SwiftUI
import Observation
import TaktCore

/// Anchored to the right edge; expanding keeps the pointer inside the window.
enum FocusEdgeGeometry {
    static let compact = NSSize(width: 72, height: 72)
    static let expanded = NSSize(width: 244, height: 116)
    static let expandedWithNote = NSSize(width: 300, height: 196)
    static func frame(in screen: NSRect, expanded: Bool, fraction: Double = 0.60, hasNote: Bool = false) -> NSRect {
        let size = expanded ? (hasNote ? expandedWithNote : self.expanded) : compact
        let position = fraction.isFinite ? min(1, max(0, fraction)) : 0.60
        let center = screen.minY + screen.height * position
        let y = max(screen.minY, min(screen.maxY - size.height, center - size.height / 2))
        return NSRect(x: screen.maxX - size.width, y: y, width: size.width, height: size.height)
    }
}

/// The centre counts remaining minutes; the head completes one clockwise lap
/// per minute. Both derive from the session deadline, never accumulated ticks.
nonisolated struct FocusEdgeDialReading {
    let minutes: Int
    let headDegrees: Double
    init(remaining: TimeInterval) {
        let remaining = remaining.isFinite ? max(0, remaining) : 0
        minutes = Int(ceil(remaining / 60))
        let second = (60 - remaining.truncatingRemainder(dividingBy: 60)).truncatingRemainder(dividingBy: 60)
        headDegrees = second * 6 - 90
    }
}

nonisolated private struct FocusEdgeOutline: InsettableShape {
    var expanded: Bool
    var inset: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: inset, dy: inset)
        if expanded {
            return UnevenRoundedRectangle(topLeadingRadius: max(0, 14 - inset), bottomLeadingRadius: max(0, 14 - inset)).path(in: rect)
        }
        return Circle().path(in: rect)
    }
    func inset(by amount: CGFloat) -> Self {
        var copy = self; copy.inset += amount; return copy
    }
}

@Observable final class FocusEdgePresentation {
    var expanded = false
}

private final class FocusEdgePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
private final class FocusEdgeHost: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class FocusEdgeController {
    private let state: AppState
    let presentation = FocusEdgePresentation()
    private(set) var panel: NSPanel?
    private var screen: NSScreen?
    private var collapseTask: Task<Void, Never>?
    private var expirationTask: Task<Void, Never>?
    private var hiddenSession: Pomodoro?
    private var pointerInside = false
    private var notePinned = false
    private var hasResumeNote: Bool { !(state.pomodoro.session?.resumeNote?.isEmpty ?? true) }
    private var shouldPinNote: Bool {
        state.pomodoro.session?.deadline == nil && hasResumeNote && !state.pomodoro.pausePrompt
    }

    init(state: AppState, defaults: UserDefaults? = nil) {
        self.state = state
        // Previous versions persisted the close button as a global off switch.
        // Dismissal is temporary; it must never disable future countdowns.
        defaults?.removeObject(forKey: "focusEdgeEnabled")
    }
    func sync() {
        expirationTask?.cancel(); expirationTask = nil
        let current = state.pomodoro.session
        if let hidden = hiddenSession, let current, hidden.taskID == current.taskID, hidden.phase == current.phase {
            if let deadline = current.deadline {
                if let previous = hidden.deadline {
                    if abs(deadline.timeIntervalSince(previous)) > 0.001 { hiddenSession = nil }
                } else { hiddenSession = nil }
            } else { hiddenSession = current }
        } else { hiddenSession = nil }
        guard let session = current, session.seconds(at: Date()) > 0, hiddenSession == nil else {
            collapseTask?.cancel(); presentation.expanded = false; notePinned = false; panel?.orderOut(nil); return
        }
        let wasPinned = notePinned
        notePinned = shouldPinNote
        if notePinned { collapseTask?.cancel(); presentation.expanded = true }
        else if wasPinned { presentation.expanded = pointerInside }
        if panel == nil {
            let screen = NSScreen.main ?? NSScreen.screens.first
            self.screen = screen
            let frame = FocusEdgeGeometry.frame(in: screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800), expanded: false)
            let panel = FocusEdgePanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "Таймер фокуса"; panel.isReleasedWhenClosed = false
            panel.isFloatingPanel = true; panel.level = .floating
            panel.hidesOnDeactivate = false; panel.becomesKeyOnlyIfNeeded = true
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.contentView = FocusEdgeHost(rootView: AnyView(FocusEdgeTimerView(state: state, presentation: presentation,
                hover: { [weak self] in self?.hover($0) }, hide: { [weak self] in self?.hide() })))
            self.panel = panel
        }
        layout()
        panel?.orderFrontRegardless()
        if let deadline = session.deadline {
            expirationTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow))) }
                catch { return }
                guard !Task.isCancelled else { return }
                self?.sync()
            }
        }
    }
    func show() { hiddenSession = nil; sync() }
    func hide() {
        hiddenSession = state.pomodoro.session
        sync()
    }
    func hover(_ inside: Bool) {
        pointerInside = inside
        collapseTask?.cancel()
        if inside { setExpanded(true) }
        else {
            // Crossing between the edge and a control must not make it flicker.
            collapseTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
                guard !Task.isCancelled else { return }
                self?.setExpanded(false)
            }
        }
    }
    private func setExpanded(_ expanded: Bool) {
        presentation.expanded = expanded || shouldPinNote; layout()
    }
    private func layout() {
        let current = screen.flatMap { old in NSScreen.screens.first { $0 === old } } ?? NSScreen.main ?? NSScreen.screens.first
        screen = current
        guard let current else { return }
        // Frequent hover and countdown changes are deliberately instant, with no
        // bouncing or animated digits; this also respects Reduce Motion.
        panel?.setFrame(FocusEdgeGeometry.frame(in: current.visibleFrame, expanded: presentation.expanded, hasNote: hasResumeNote), display: true, animate: false)
        let theme = state.data.preferences.theme
        panel?.appearance = theme == "dark" ? NSAppearance(named: .darkAqua) : theme == "light" ? NSAppearance(named: .aqua) : nil
    }
}

struct FocusEdgeTimerView: View {
    private let timerInk = Color(.sRGB, red: 1, green: 146.0 / 255, blue: 48.0 / 255, opacity: 1)
    let state: AppState
    let presentation: FocusEdgePresentation
    var previewDate: Date? = nil
    var previewOpaque = false
    var hover: (Bool) -> Void = { _ in }
    var hide: () -> Void = {}
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    private var shape: FocusEdgeOutline { FocusEdgeOutline(expanded: presentation.expanded) }
    private var hasNote: Bool { !(state.pomodoro.session?.resumeNote?.isEmpty ?? true) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let session = state.pomodoro.session {
                let seconds = session.seconds(at: previewDate ?? context.date)
                let clock = String(format: "%02d:%02d", seconds / 60, seconds % 60)
                Group {
                    if presentation.expanded {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(clock).font(.system(size: 25, weight: .medium)).monospacedDigit().foregroundStyle(timerInk)
                                Text(seconds == 0 ? "Готово" : session.deadline == nil ? "Пауза" : session.phase == .focus ? "Фокус" : "Перерыв")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                                Button(action: hide) { Image(systemName: "xmark").frame(width: 24, height: 24) }
                                    .buttonStyle(.plain).help("Скрыть таймер, не останавливая сеанс")
                                    .accessibilityLabel("Скрыть таймер")
                            }
                            Text(session.title).font(.system(size: 12)).lineLimit(1).help(session.title)
                            if let note = session.resumeNote, !note.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("С чего продолжить").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                                    Text(note).font(.system(size: 12)).lineLimit(3).help(note)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                            HStack(spacing: 8) {
                                if seconds == 0 {
                                    Button(session.phase == .focus ? "Начать перерыв" : "Начать фокус") { state.pomodoro.next() }
                                } else {
                                    Button {
                                        if session.deadline == nil { state.pomodoro.resume() }
                                        else { state.pomodoro.pause() }
                                    } label: {
                                        Label(session.deadline == nil ? "Продолжить" : "Пауза", systemImage: session.deadline == nil ? "play.fill" : "pause.fill")
                                    }
                                }
                                Button("Завершить") { state.pomodoro.stop() }
                                if session.deadline == nil && seconds > 0 {
                                    Button { state.pomodoro.requestResumeNote() } label: {
                                        Image(systemName: "square.and.pencil")
                                    }.help("Записать, с чего продолжить")
                                        .accessibilityLabel("Записать, с чего продолжить")
                                }
                            }.controlSize(.small)
                        }.padding(.horizontal, 14).padding(.vertical, 10)
                    } else {
                        Button { hover(true) } label: {
                            TimelineView(.animation(minimumInterval: 1.0 / 15,
                                paused: session.deadline == nil || reduceMotion || previewDate != nil)) { tick in
                                let date = previewDate ?? (reduceMotion ? context.date : tick.date)
                                let reading = FocusEdgeDialReading(remaining: session.deadline?.timeIntervalSince(date) ?? session.remaining)
                                FocusEdgeDial(reading: reading, paused: session.deadline == nil, ink: timerInk,
                                              increasedContrast: contrast == .increased)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Circle())
                        }.buttonStyle(.plain)
                            .accessibilityLabel("\(session.phase == .focus ? "Фокус" : "Перерыв"), \(clock). Показать управление")
                            .help("\(clock) · Наведите, чтобы управлять таймером")
                    }
                }
                .frame(width: presentation.expanded ? (hasNote ? FocusEdgeGeometry.expandedWithNote.width : FocusEdgeGeometry.expanded.width) : FocusEdgeGeometry.compact.width,
                       height: presentation.expanded ? (hasNote ? FocusEdgeGeometry.expandedWithNote.height : FocusEdgeGeometry.expanded.height) : FocusEdgeGeometry.compact.height)
                .background(Color(nsColor: .windowBackgroundColor).opacity(previewOpaque || reduceTransparency || contrast == .increased ? 1 : presentation.expanded ? 0.98 : 0.84))
                .clipShape(shape)
                .overlay { shape.strokeBorder(timerInk.opacity(0.50), lineWidth: 1).allowsHitTesting(false) }
                .contentShape(shape)
                .onHover(perform: hover)
                .onExitCommand { hover(false) }
                .contextMenu { Button("Скрыть таймер", action: hide) }
            }
        }
    }
}

private struct FocusEdgeDial: View {
    let reading: FocusEdgeDialReading
    let paused: Bool
    let ink: Color
    let increasedContrast: Bool
    private let tailDegrees = 78.0

    var body: some View {
        ZStack {
            Circle().strokeBorder(.primary.opacity(increasedContrast ? 0.25 : 0.08), lineWidth: 1)
                .padding(6)
            ForEach(0..<12) { tick in
                Capsule().fill(.primary.opacity(increasedContrast ? 0.65 : 0.30))
                    .frame(width: 1, height: tick.isMultiple(of: 3) ? 4 : 3)
                    .offset(y: -24)
                    .rotationEffect(.degrees(Double(tick) * 30))
            }
            Circle().trim(from: 0, to: tailDegrees / 360)
                .stroke(AngularGradient(colors: [ink.opacity(0.05), ink], center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(tailDegrees)),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .padding(6)
                .rotationEffect(.degrees(reading.headDegrees - tailDegrees))
            Circle().fill(ink).frame(width: 3.5, height: 3.5)
                .offset(x: 30)
                .rotationEffect(.degrees(reading.headDegrees))
            VStack(spacing: -1) {
                Text(reading.minutes.formatted()).font(.system(size: 24, weight: .medium))
                    .monospacedDigit().foregroundStyle(ink)
                HStack(spacing: 3) {
                    if paused { Image(systemName: "pause.fill").font(.system(size: 6, weight: .bold)) }
                    Text("мин").font(.system(size: 9, weight: .medium))
                }.foregroundStyle(.secondary)
            }
        }.accessibilityHidden(true)
    }
}

/// Render-only context for judging transparency. These are the real component
/// states over illustrative work content, not a replacement implementation.
struct FocusEdgePreviewBoard: View {
    let state: AppState
    let date: Date
    var opaque = false
    private let compact = FocusEdgePresentation()
    private let expanded: FocusEdgePresentation = {
        let value = FocusEdgePresentation(); value.expanded = true; return value
    }()
    var body: some View {
        HStack(spacing: 20) {
            column(.light)
            column(.dark)
        }.padding(20).background(Color(nsColor: .underPageBackgroundColor))
    }
    private func column(_ scheme: ColorScheme) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(scheme == .light ? "Светлый фон" : "Тёмный фон").font(.system(size: 15, weight: .semibold))
            sample(expanded: false)
            sample(expanded: true)
        }.padding(12)
            .background(scheme == .light ? Color.white : Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, scheme)
    }
    private func sample(expanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(expanded ? "При наведении" : "Без наведения").font(.system(size: 11)).foregroundStyle(.secondary)
            ZStack(alignment: .trailing) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("План проекта").font(.system(size: 18, weight: .semibold))
                    Text("Собрать материалы и сверить сроки.").font(.system(size: 12)).foregroundStyle(.secondary)
                    Divider()
                    Text("Следующий шаг — подготовить черновик.").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 162).background(Color(nsColor: .textBackgroundColor))
                FocusEdgeTimerView(state: state, presentation: expanded ? self.expanded : compact, previewDate: date, previewOpaque: opaque)
            }.clipped()
        }
    }
}
