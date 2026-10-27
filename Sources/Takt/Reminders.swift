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
            if pending.contains(where: { Self.isCurrent($0, for: reminder) }) { continue }
            let content = Self.content(for: reminder)
            var components = Dates.calendar(zone: snapshot.preferences.timeZone).dateComponents([.year,.month,.day,.hour,.minute,.second], from: reminder.fire)
            components.timeZone = TimeZone(identifier: snapshot.preferences.timeZone)
            let request = UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            try await center.add(request)
        }
    }
    static func isLegacy(_ content: UNNotificationContent) -> Bool {
        content.body.hasPrefix("Такт ·")
    }
    static func content(for reminder: PlannedReminder) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = reminder.title; content.body = "Напоминание о задаче"
        content.sound = UNNotificationSound(named: UNNotificationSoundName("Completion.wav"))
        content.threadIdentifier = "task-" + reminder.itemID.uuidString
        content.userInfo = ["eventKey": reminder.identifier, "itemID": reminder.itemID.uuidString, "formatVersion": 3]
        return content
    }
    static func isCurrent(_ request: UNNotificationRequest, for reminder: PlannedReminder) -> Bool {
        request.identifier == reminder.identifier && request.content.title == reminder.title &&
        request.content.userInfo["formatVersion"] as? Int == 3 && request.content.attachments.isEmpty
    }
}
