import AppKit
import Carbon

final class HotKeys {
    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private let action: (UInt32) -> Void
    private(set) var summary = ""
    init(action: @escaping (UInt32) -> Void) {
        self.action = action
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var key = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &key) == noErr,
                  key.signature == 0x54414B54 else { return OSStatus(eventNotHandledErr) }
            let id = key.id
            MainActor.assumeIsolated { Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue().action(id) }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        if status != noErr { summary = "Не удалось подключить горячие клавиши (\(status))" }
    }
    func register(shifted: Bool) {
        for reference in references { UnregisterEventHotKey(reference) }; references.removeAll()
        guard handler != nil else { return }
        var labels: [String] = []
        for (key, id, title) in [(kVK_ANSI_Q, UInt32(1), "Q — задача"), (kVK_ANSI_D, UInt32(2), "D — заметка")] {
            var reference: EventHotKeyRef?
            var useShift = shifted
            var result = RegisterEventHotKey(UInt32(key), UInt32(controlKey | (useShift ? shiftKey : 0)), EventHotKeyID(signature: 0x54414B54, id: id), GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &reference)
            if result != noErr && !shifted {
                useShift = true
                result = RegisterEventHotKey(UInt32(key), UInt32(controlKey | shiftKey), EventHotKeyID(signature: 0x54414B54, id: id), GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &reference)
            }
            if result == noErr, let reference { references.append(reference); labels.append("Control-\(useShift ? "Shift-" : "")\(title)") }
            else { labels.append("\(title): сочетание недоступно (\(result))") }
        }
        summary = labels.joined(separator: "\n")
    }
    func stop() {
        for reference in references { UnregisterEventHotKey(reference) }; references.removeAll()
        if let handler { RemoveEventHandler(handler) }; handler = nil
    }
}
