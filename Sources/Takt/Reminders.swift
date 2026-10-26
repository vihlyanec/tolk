import Foundation
import UserNotifications
import TaktCore

final class Reminders {
    private var debounce: Task<Void, Never>?
    private var worker: Task<Void, Never>?
    private var latest: Snapshot?
    var reportError: (String) -> Void = { _ in }
    func sync(_ snapshot: Snapshot) {
        latest = snapshot
        guard worker == nil else { return }
        debounce?.cancel()
        debounce = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            guard let self else { return }
            self.worker = Task { @MainActor [weak self] in
                guard let self else { return }
                while let snapshot = self.latest {
                    self.latest = nil
                    do { try await self.reconcile(snapshot) }
                    catch { self.reportError("Напоминания: \(error.localizedDescription)") }
                }
                self.worker = nil
            }
        }
    }
    private func reconcile(_ snapshot: Snapshot) async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let wanted = NotificationPlan.events(snapshot: snapshot)
        if settings.authorizationStatus == .notDetermined && !wanted.isEmpty {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                reportError("Напоминания отключены. Разрешите уведомления Толка в настройках macOS."); return
            }
        }
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        let deliveredKeys = Set(delivered.compactMap { $0.request.content.userInfo["eventKey"] as? String })
        let wantedIDs = Set(wanted.map(\.identifier))
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { Self.isLegacy($0.content) || ($0.identifier.hasPrefix("task-") && !wantedIDs.contains($0.identifier)) }.map(\.identifier))
        for reminder in wanted {
            guard reminder.fire > Date(), !deliveredKeys.contains(reminder.identifier) else { continue }
            if pending.contains(where: { $0.identifier == reminder.identifier && $0.content.title == reminder.title && $0.content.userInfo["formatVersion"] as? Int == 2 }) { continue }
            let content = Self.content(for: reminder, logo: Self.makeLogo())
            var components = Dates.calendar(zone: snapshot.preferences.timeZone).dateComponents([.year,.month,.day,.hour,.minute,.second], from: reminder.fire)
            components.timeZone = TimeZone(identifier: snapshot.preferences.timeZone)
            let request = UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            do { try await center.add(request) }
            catch {
                // An unavailable image must never prevent the reminder itself from being scheduled.
                guard !content.attachments.isEmpty else { throw error }
                content.attachments = []
                try await center.add(UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: request.trigger))
            }
        }
    }
    static func isLegacy(_ content: UNNotificationContent) -> Bool {
        content.body.hasPrefix("Такт ·")
    }
    static func content(for reminder: PlannedReminder, logo: UNNotificationAttachment? = nil) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = reminder.title; content.body = "Напоминание о задаче"
        content.sound = UNNotificationSound(named: UNNotificationSoundName("Completion.wav"))
        content.threadIdentifier = "task-" + reminder.itemID.uuidString
        content.userInfo = ["eventKey": reminder.identifier, "itemID": reminder.itemID.uuidString, "formatVersion": 2]
        if let logo { content.attachments = [logo] }
        return content
    }
    static func makeLogo(source: URL? = Bundle.main.url(forResource: "BrandIcon", withExtension: "png")) -> UNNotificationAttachment? {
        guard let source else { return nil }
        do {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tolk-notification-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = folder.appendingPathComponent("Logo-\(UUID().uuidString).png")
            try FileManager.default.copyItem(at: source, to: target)
            return try UNNotificationAttachment(identifier: "tolk-logo", url: target)
        } catch { return nil }
    }
}
