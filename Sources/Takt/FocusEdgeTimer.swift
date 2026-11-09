import AppKit
import SwiftUI
import Observation
import TaktCore

/// Anchored to the right edge; expanding keeps the pointer inside the window.
enum FocusEdgeGeometry {
    static let compact = NSSize(width: 84, height: 38)
    static let expanded = NSSize(width: 244, height: 116)
    static func frame(in screen: NSRect, expanded: Bool, fraction: Double = 0.60) -> NSRect {
        let size = expanded ? self.expanded : compact
        let position = fraction.isFinite ? min(1, max(0, fraction)) : 0.60
        let center = screen.minY + screen.height * position
        let y = max(screen.minY, min(screen.maxY - size.height, center - size.height / 2))
        return NSRect(x: screen.maxX - size.width, y: y, width: size.width, height: size.height)
    }
}

@Observable final class FocusEdgePresentation {
    var expanded = false
}

private final class FocusEdgePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
private final class FocusEdgeHost<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class FocusEdgeController {
    private let state: AppState
    private let defaults: UserDefaults?
    let presentation = FocusEdgePresentation()
    private(set) var panel: NSPanel?
    private var screen: NSScreen?
    private var collapseTask: Task<Void, Never>?
    private var enabled: Bool

    init(state: AppState, defaults: UserDefaults? = nil) {
        self.state = state; self.defaults = defaults
        enabled = defaults?.object(forKey: "focusEdgeEnabled") as? Bool ?? true
    }
    func sync() {
        guard state.pomodoro.session != nil, enabled else {
            collapseTask?.cancel(); presentation.expanded = false; panel?.orderOut(nil); return
        }
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
            panel.contentView = FocusEdgeHost(rootView: FocusEdgeTimerView(state: state, presentation: presentation,
                hover: { [weak self] in self?.hover($0) }, hide: { [weak self] in self?.hide() }))
            self.panel = panel
        }
        layout()
        panel?.orderFrontRegardless()
    }
    func show() { enabled = true; defaults?.set(true, forKey: "focusEdgeEnabled"); sync() }
    func hide() {
        enabled = false; defaults?.set(false, forKey: "focusEdgeEnabled")
        sync()
    }
    func hover(_ inside: Bool) {
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
        presentation.expanded = expanded; layout()
    }
    private func layout() {
        let current = screen.flatMap { old in NSScreen.screens.first { $0 === old } } ?? NSScreen.main ?? NSScreen.screens.first
        screen = current
        guard let current else { return }
        // Frequent hover and countdown changes are deliberately instant, with no
        // bouncing or animated digits; this also respects Reduce Motion.
        panel?.setFrame(FocusEdgeGeometry.frame(in: current.visibleFrame, expanded: presentation.expanded), display: true, animate: false)
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
    @Environment(\.colorSchemeContrast) private var contrast
    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: presentation.expanded ? 14 : 19, bottomLeadingRadius: presentation.expanded ? 14 : 19)
    }

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
                                    .buttonStyle(.plain).help("Скрыть каплю, не останавливая таймер")
                                    .accessibilityLabel("Скрыть таймер")
                            }
                            Text(session.title).font(.system(size: 12)).lineLimit(1).help(session.title)
                            HStack(spacing: 8) {
                                if seconds == 0 {
                                    Button(session.phase == .focus ? "Начать перерыв" : "Начать фокус") { state.pomodoro.next() }
                                } else {
                                    Button {
                                        if session.deadline == nil { state.pomodoro.resume() }
                                        else { state.pomodoro.pause(); state.pomodoro.skipResumeNote() }
                                    } label: {
                                        Label(session.deadline == nil ? "Продолжить" : "Пауза", systemImage: session.deadline == nil ? "play.fill" : "pause.fill")
                                    }
                                }
                                Button("Завершить") { state.pomodoro.stop() }
                            }.controlSize(.small)
                        }.padding(.horizontal, 14).padding(.vertical, 10)
                    } else {
                        Button { hover(true) } label: {
                            Text(clock).font(.system(size: 16, weight: .medium)).monospacedDigit().foregroundStyle(timerInk)
                                .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityLabel("\(session.phase == .focus ? "Фокус" : "Перерыв"), \(clock). Показать управление")
                            .help("Наведите, чтобы управлять таймером")
                    }
                }
                .frame(width: presentation.expanded ? FocusEdgeGeometry.expanded.width : FocusEdgeGeometry.compact.width,
                       height: presentation.expanded ? FocusEdgeGeometry.expanded.height : FocusEdgeGeometry.compact.height)
                .background(Color(nsColor: .windowBackgroundColor).opacity(previewOpaque || reduceTransparency || contrast == .increased ? 1 : presentation.expanded ? 0.98 : 0.84))
                .clipShape(shape)
                .overlay { shape.strokeBorder(timerInk.opacity(0.50), lineWidth: 1).allowsHitTesting(false) }
                .contentShape(Rectangle())
                .onHover(perform: hover)
                .onExitCommand { hover(false) }
                .contextMenu { Button("Скрыть таймер", action: hide) }
            }
        }
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
